import 'dart:io';
import 'dart:typed_data';

// One recording's bytes. Writing only appends; a footer rewrite truncates first.
abstract class RecordingFile {
  String get name;

  Future<int> length();

  // up to count bytes from position, fewer at the end of the file
  Future<Uint8List> read(int position, int count);

  Future<void> append(Uint8List bytes);

  Future<void> truncate(int length);

  Future<void> close();
}

// Where the recordings of the library are kept: a folder on desktop, memory in the browser and in tests
abstract class RecordingStore {
  // a folder the user can open, null when there is none
  String? get location;

  Future<List<String>> names();

  Future<bool> exists(String name);

  // when the file was last written, null if the store doesn't know
  Future<DateTime?> modified(String name);

  Future<RecordingFile> open(String name);

  // a new, empty file
  Future<RecordingFile> create(String name);

  Future<void> delete(String name);
}

class FolderRecordingStore implements RecordingStore {
  final Directory folder;

  FolderRecordingStore(this.folder);

  @override
  String? get location => folder.path;

  @override
  Future<List<String>> names() async {
    if (!await folder.exists()) {
      return [];
    }
    return [
      await for (var entity in folder.list())
        if (entity is File && entity.path.toLowerCase().endsWith(RecordingNames.extension))
          entity.uri.pathSegments.last
    ];
  }

  @override
  Future<bool> exists(String name) => File(_path(name)).exists();

  @override
  Future<DateTime?> modified(String name) => File(_path(name)).lastModified();

  @override
  Future<RecordingFile> open(String name) async => _IoRecordingFile(name, await File(_path(name)).open(mode: FileMode.append));

  @override
  Future<RecordingFile> create(String name) async {
    await folder.create(recursive: true);
    return _IoRecordingFile(name, await File(_path(name)).open(mode: FileMode.write));
  }

  // Sync clients like OneDrive and virus scanners open new files for a moment, so a delete that finds the file in
  // use is tried a few times before it fails
  @override
  Future<void> delete(String name) async {
    for (var attempt = 1;; attempt++) {
      try {
        await File(_path(name)).delete();
        return;
      } on FileSystemException {
        if (attempt == 5) {
          rethrow;
        }
        await Future.delayed(Duration(milliseconds: 200 * attempt));
      }
    }
  }

  String _path(String name) => '${folder.path}${Platform.pathSeparator}$name';
}

class _IoRecordingFile implements RecordingFile {
  @override
  final String name;
  final RandomAccessFile _file;
  // RandomAccessFile allows one operation at a time
  Future<void> _pending = Future.value();

  _IoRecordingFile(this.name, this._file);

  Future<T> _serial<T>(Future<T> Function() operation) {
    var result = _pending.then((_) => operation());
    _pending = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<int> length() => _serial(() => _file.length());

  @override
  Future<Uint8List> read(int position, int count) => _serial(() async {
        await _file.setPosition(position);
        return _file.read(count);
      });

  @override
  Future<void> append(Uint8List bytes) => _serial(() async {
        await _file.setPosition(await _file.length());
        await _file.writeFrom(bytes);
      });

  @override
  Future<void> truncate(int length) => _serial(() => _file.truncate(length));

  @override
  Future<void> close() => _serial(() async {
        await _file.flush();
        await _file.close();
      });
}

class MemoryRecordingStore implements RecordingStore {
  final Map<String, BytesBuilder> _files = {};

  @override
  String? get location => null;

  @override
  Future<List<String>> names() async => _files.keys.toList();

  @override
  Future<bool> exists(String name) async => _files.containsKey(name);

  @override
  Future<DateTime?> modified(String name) async => null;

  @override
  Future<RecordingFile> open(String name) async {
    if (!_files.containsKey(name)) {
      throw FileSystemException('No such recording', name);
    }
    return _MemoryRecordingFile(name, this);
  }

  @override
  Future<RecordingFile> create(String name) async {
    _files[name] = BytesBuilder(copy: false);
    return _MemoryRecordingFile(name, this);
  }

  @override
  Future<void> delete(String name) async => _files.remove(name);

  // for tests: the raw bytes of a recording
  Uint8List bytesOf(String name) => _files[name]!.toBytes();

  void replace(String name, Uint8List bytes) => _files[name] = BytesBuilder(copy: false)..add(bytes);
}

class _MemoryRecordingFile implements RecordingFile {
  @override
  final String name;
  final MemoryRecordingStore _store;

  _MemoryRecordingFile(this.name, this._store);

  BytesBuilder get _bytes => _store._files[name]!;

  @override
  Future<int> length() async => _bytes.length;

  @override
  Future<Uint8List> read(int position, int count) async {
    var all = _bytes.toBytes();
    if (position >= all.length) {
      return Uint8List(0);
    }
    return Uint8List.sublistView(all, position, position + count > all.length ? all.length : position + count);
  }

  @override
  Future<void> append(Uint8List bytes) async => _bytes.add(bytes);

  @override
  Future<void> truncate(int length) async {
    var kept = Uint8List.sublistView(_bytes.toBytes(), 0, length);
    _store.replace(name, Uint8List.fromList(kept));
  }

  @override
  Future<void> close() async {}
}

// A recording loaded into memory, read only. The instances of a recorded device share one, so 100 instances
// don't open the file 100 times.
class BytesRecordingFile implements RecordingFile {
  @override
  final String name;
  final Uint8List bytes;

  BytesRecordingFile(this.name, this.bytes);

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<Uint8List> read(int position, int count) async {
    if (position >= bytes.length) {
      return Uint8List(0);
    }
    return Uint8List.sublistView(bytes, position, position + count > bytes.length ? bytes.length : position + count);
  }

  @override
  Future<void> append(Uint8List bytes) => throw UnsupportedError('$name is read only');

  @override
  Future<void> truncate(int length) => throw UnsupportedError('$name is read only');

  @override
  Future<void> close() async {}
}

class RecordingNames {
  static const String extension = '.mqttrec';

  // "<name> <yyyy-MM-dd HHmmss>.mqttrec", with characters Windows doesn't allow in file names replaced
  static String fileNameFor(String name, DateTime startedAt) {
    var local = startedAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    var stamp = '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}${two(local.minute)}${two(local.second)}';
    var safe = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_').trim();
    if (safe.length > 80) {
      safe = safe.substring(0, 80).trim();
    }
    return '${safe.isEmpty ? 'Recording' : safe} $stamp$extension';
  }
}
