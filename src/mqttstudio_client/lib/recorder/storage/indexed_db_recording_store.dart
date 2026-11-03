import 'dart:math';
import 'dart:typed_data';
import 'package:idb_shim/idb.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';

// The recordings library in the browser (doc/recorder-design.md §4.4): each file in 1 MB chunks in IndexedDB, plus
// one record per file with its length and time, so listing doesn't read the chunks. A file is kept in memory while
// it is open and every change is written through, in order.
class IndexedDbRecordingStore implements RecordingStore {
  static const String databaseName = 'mqttstudio_recordings';
  static const String filesStore = 'files';
  static const String chunksStore = 'chunks';
  static const int chunkSize = 1024 * 1024;

  final IdbFactory _factory;
  Database? _database;
  // the files that are open, shared by all their handles; the last close lets go of the bytes
  final Map<String, _ChunkedData> _loaded = {};
  // writes go to IndexedDB one after the other, so an older state never overwrites a newer one. A failed write only
  // fails for its caller; the chain goes on with the next one.
  Future<void> _writes = Future.value();

  IndexedDbRecordingStore(this._factory);

  @override
  String? get location => null;

  Future<Database> _db() async => _database ??= await _factory.open(databaseName, version: 1, onUpgradeNeeded: (event) {
        var db = event.database;
        if (!db.objectStoreNames.contains(filesStore)) {
          db.createObjectStore(filesStore);
        }
        if (!db.objectStoreNames.contains(chunksStore)) {
          db.createObjectStore(chunksStore);
        }
      });

  static String _chunkKey(String name, int index) => '$name|$index';

  @override
  Future<List<String>> names() async {
    var db = await _db();
    var txn = db.transaction(filesStore, idbModeReadOnly);
    var keys = await txn.objectStore(filesStore).getAllKeys();
    await txn.completed;
    return [for (var key in keys) key as String];
  }

  @override
  Future<bool> exists(String name) async => _loaded.containsKey(name) || await _meta(name) != null;

  @override
  Future<DateTime?> modified(String name) async {
    var meta = await _meta(name);
    var millis = meta?['modified'];
    return millis is int ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  Future<Map?> _meta(String name) async {
    var db = await _db();
    var txn = db.transaction(filesStore, idbModeReadOnly);
    var value = await txn.objectStore(filesStore).getObject(name);
    await txn.completed;
    return value as Map?;
  }

  @override
  Future<RecordingFile> open(String name) async {
    var data = _loaded[name];
    if (data == null) {
      // a file that was just closed may still be on its way into IndexedDB
      await _writes;
      data = _loaded[name];
    }
    if (data == null) {
      var meta = await _meta(name);
      if (meta == null) {
        throw StateError('No such recording: $name');
      }
      var length = meta['length'] as int;
      var db = await _db();
      var txn = db.transaction(chunksStore, idbModeReadOnly);
      var store = txn.objectStore(chunksStore);
      var chunks = <Uint8List>[];
      for (var i = 0; i * chunkSize < length; i++) {
        chunks.add(_bytesOf(await store.getObject(_chunkKey(name, i))));
      }
      await txn.completed;
      data = _loaded[name] ??= _ChunkedData(chunks, length);
    }
    data.handles++;
    return _IdbRecordingFile(name, this, data);
  }

  @override
  Future<RecordingFile> create(String name) async {
    var data = _ChunkedData([], 0)..handles = 1;
    _loaded[name] = data;
    try {
      await _persist(name, data, {});
    } catch (_) {
      _loaded.remove(name);
      rethrow;
    }
    return _IdbRecordingFile(name, this, data);
  }

  @override
  Future<void> delete(String name) async {
    var data = _loaded.remove(name);
    var meta = await _meta(name);
    var length = data?.length ?? (meta?['length'] as int? ?? 0);
    await _enqueue(() async {
      var db = await _db();
      var txn = db.transaction([filesStore, chunksStore], idbModeReadWrite);
      await txn.objectStore(filesStore).delete(name);
      var chunks = txn.objectStore(chunksStore);
      for (var i = 0; i * chunkSize < max(length, 1); i++) {
        await chunks.delete(_chunkKey(name, i));
      }
      await txn.completed;
    });
  }

  Future<void> _enqueue(Future<void> Function() write) {
    var result = _writes.then((_) => write());
    _writes = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  void _release(String name, _ChunkedData data) {
    data.handles--;
    if (data.handles <= 0 && identical(_loaded[name], data)) {
      _loaded.remove(name);
    }
  }

  // writes the changed chunks and the file record; chunks past the end are removed
  Future<void> _persist(String name, _ChunkedData data, Set<int> changed, {int removedFrom = -1, int removedTo = -1}) {
    var snapshot = {for (var index in changed) if (index < data.chunks.length) index: Uint8List.fromList(data.chunks[index])};
    var length = data.length;
    return _enqueue(() async {
      var db = await _db();
      var txn = db.transaction([filesStore, chunksStore], idbModeReadWrite);
      var chunks = txn.objectStore(chunksStore);
      for (var entry in snapshot.entries) {
        await chunks.put(entry.value, _chunkKey(name, entry.key));
      }
      for (var i = removedFrom; i >= 0 && i < removedTo; i++) {
        await chunks.delete(_chunkKey(name, i));
      }
      await txn.objectStore(filesStore).put({'length': length, 'modified': DateTime.now().millisecondsSinceEpoch}, name);
      await txn.completed;
    });
  }

  static Uint8List _bytesOf(Object? value) {
    if (value is Uint8List) {
      return value;
    }
    if (value is List) {
      return Uint8List.fromList(value.cast<int>());
    }
    return Uint8List(0);
  }
}

// The bytes of a file as full chunks of chunkSize and one last, partly filled chunk
class _ChunkedData {
  final List<Uint8List> chunks;
  int length;
  // open handles
  int handles = 0;

  _ChunkedData(this.chunks, this.length);
}

class _IdbRecordingFile implements RecordingFile {
  static const int _size = IndexedDbRecordingStore.chunkSize;

  @override
  final String name;
  final IndexedDbRecordingStore _store;
  final _ChunkedData _data;
  bool _closed = false;

  _IdbRecordingFile(this.name, this._store, this._data);

  @override
  Future<int> length() async => _data.length;

  @override
  Future<Uint8List> read(int position, int count) async {
    var end = min(_data.length, position + count);
    if (position >= end) {
      return Uint8List(0);
    }
    var result = Uint8List(end - position);
    var done = 0;
    while (position + done < end) {
      var at = position + done;
      var chunk = _data.chunks[at ~/ _size];
      var offset = at % _size;
      var take = min(chunk.length - offset, end - at);
      result.setRange(done, done + take, chunk, offset);
      done += take;
    }
    return result;
  }

  @override
  Future<void> append(Uint8List bytes) {
    var changed = <int>{};
    var done = 0;
    while (done < bytes.length) {
      var index = _data.length ~/ _size;
      var offset = _data.length % _size;
      if (index == _data.chunks.length) {
        _data.chunks.add(Uint8List(0));
      }
      var take = min(_size - offset, bytes.length - done);
      var chunk = _data.chunks[index];
      var grown = Uint8List(offset + take)
        ..setRange(0, offset, chunk)
        ..setRange(offset, offset + take, bytes, done);
      _data.chunks[index] = grown;
      _data.length += take;
      done += take;
      changed.add(index);
    }
    return _store._persist(name, _data, changed);
  }

  @override
  Future<void> truncate(int length) {
    if (length >= _data.length) {
      return Future.value();
    }
    var oldCount = _data.chunks.length;
    var keep = (length + _size - 1) ~/ _size;
    _data.chunks.removeRange(keep, _data.chunks.length);
    var changed = <int>{};
    if (keep > 0 && length % _size != 0) {
      _data.chunks[keep - 1] = Uint8List.fromList(Uint8List.sublistView(_data.chunks[keep - 1], 0, length % _size));
      changed.add(keep - 1);
    }
    _data.length = length;
    return _store._persist(name, _data, changed, removedFrom: keep, removedTo: oldCount);
  }

  // the time of the file record is the library's sign that the file is still written (recording_library.dart)
  @override
  Future<void> touch() => _store._persist(name, _data, {});

  @override
  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      _store._release(name, _data);
    }
  }
}
