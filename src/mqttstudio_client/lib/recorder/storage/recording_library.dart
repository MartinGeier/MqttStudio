import 'dart:io';
import 'package:clock/clock.dart';
import 'package:event/event.dart';
import 'package:flutter/foundation.dart';
import 'package:mqttstudio/recorder/format/recording_reader.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';
import 'package:path_provider/path_provider.dart';

// A finished recording as the library lists it: header, footer and size, without its messages
class RecordingInfo {
  final String fileName;
  final RecordingHeader header;
  final RecordingFooter footer;
  final int size;

  RecordingInfo(this.fileName, this.header, this.footer, this.size);

  String get id => header.id;

  String get name => footer.name;
}

// The recordings outside the projects (doc/recorder-design.md R2, R24): a folder on desktop, memory in the browser
class RecordingLibrary {
  // an unfinished file that was written to more recently than this may still be recording, e.g. from the CLI
  static const Duration activeWriteGrace = Duration(seconds: 15);

  RecordingStore _store;
  // the folder used when the user chose none, null in the browser
  final String? defaultLocation;
  // a recording was added, finished, changed or deleted, or the folder changed
  final changedEvent = Event();
  // files this app is writing right now: not listed and never recovered
  final Set<String> _writing = {};

  RecordingLibrary(this._store, {this.defaultLocation});

  // Desktop: the folder the user chose in the recorder tab, else Documents\MQTT Studio\Recordings. MSIX doesn't
  // virtualize Documents, so the CLI and Explorer see the same files. The browser keeps recordings in memory for now
  // (doc/recorder-design.md §4.4 plans IndexedDB).
  static Future<RecordingLibrary> forPlatform({String? folder}) async {
    if (kIsWeb) {
      return RecordingLibrary(MemoryRecordingStore());
    }
    var documents = await getApplicationDocumentsDirectory();
    var separator = Platform.pathSeparator;
    var defaultFolder = '${documents.path}${separator}MQTT Studio${separator}Recordings';
    return RecordingLibrary(FolderRecordingStore(Directory(folder ?? defaultFolder)), defaultLocation: defaultFolder);
  }

  RecordingStore get store => _store;

  // the folder the recordings are in, null in the browser
  String? get location => _store.location;

  bool get isDefaultLocation => location == defaultLocation;

  // reads and writes recordings in another folder from now on; the recordings in the old one stay where they are
  Future<void> useFolder(String path) async {
    if (_writing.isNotEmpty) {
      throw StateError('The recordings folder cannot change while a recording is written');
    }
    var folder = Directory(path);
    await folder.create(recursive: true);
    _store = FolderRecordingStore(folder);
    changedEvent.broadcast();
  }

  // newest first. Recordings left unfinished by a crash are recovered on the way.
  Future<List<RecordingInfo>> list() async {
    var infos = <RecordingInfo>[];
    for (var fileName in await store.names()) {
      if (_writing.contains(fileName)) {
        continue;
      }
      var info = await _read(fileName, recoverIfIdle: true);
      if (info != null) {
        infos.add(info);
      }
    }
    infos.sort((a, b) => b.header.startedAt.compareTo(a.header.startedAt));
    return infos;
  }

  Future<RecordingInfo?> findById(String id) async {
    for (var info in await list()) {
      if (info.id == id) {
        return info;
      }
    }
    return null;
  }

  // a new file for a recording with this name. Call finishedWriting once it is finished or abandoned.
  Future<RecordingFile> create(String name, DateTime startedAt) async {
    var fileName = RecordingNames.fileNameFor(name, startedAt);
    var number = 2;
    while (await store.exists(fileName) || _writing.contains(fileName)) {
      fileName = RecordingNames.fileNameFor('$name ($number)', startedAt);
      number++;
    }
    _writing.add(fileName);
    return store.create(fileName);
  }

  void finishedWriting(String fileName) {
    _writing.remove(fileName);
    changedEvent.broadcast();
  }

  Future<RecordingReader> open(RecordingInfo info) => _openReader(info.fileName);

  // closes the file again when it is no recording, so no handle is left behind
  Future<RecordingReader> _openReader(String fileName) async {
    var file = await store.open(fileName);
    try {
      return await RecordingReader.open(file);
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  // changes what is kept in the footer; the messages stay untouched (R9)
  Future<RecordingInfo> updateMetadata(RecordingInfo info, {String? name, String? notes, List<Bookmark>? bookmarks}) async {
    var reader = await open(info);
    try {
      var footer = reader.footer!
        ..name = name ?? info.footer.name
        ..notes = notes ?? info.footer.notes
        ..bookmarks = bookmarks ?? info.footer.bookmarks;
      await reader.rewriteFooter(footer);
      var updated = RecordingInfo(info.fileName, reader.header, footer, await reader.file.length());
      changedEvent.broadcast();
      return updated;
    } finally {
      await reader.close();
    }
  }

  Future<void> delete(RecordingInfo info) async {
    await store.delete(info.fileName);
    changedEvent.broadcast();
  }

  // copies a .mqttrec file into the library, desktop only
  Future<RecordingInfo> importFile(String path) async {
    var source = File(path);
    var bytes = await source.readAsBytes();
    var fileName = source.uri.pathSegments.last;
    if (!fileName.toLowerCase().endsWith(RecordingNames.extension)) {
      throw FormatException('$fileName is not an MQTT Studio recording');
    }
    var number = 2;
    var baseName = fileName.substring(0, fileName.length - RecordingNames.extension.length);
    while (await store.exists(fileName)) {
      fileName = '$baseName ($number)${RecordingNames.extension}';
      number++;
    }
    var file = await store.create(fileName);
    try {
      await file.append(bytes);
    } finally {
      await file.close();
    }
    var info = await _read(fileName, recoverIfIdle: true);
    if (info == null) {
      await store.delete(fileName);
      throw FormatException('${source.uri.pathSegments.last} is not an MQTT Studio recording');
    }
    changedEvent.broadcast();
    return info;
  }

  Future<RecordingInfo?> _read(String fileName, {required bool recoverIfIdle}) async {
    RecordingReader? reader;
    try {
      reader = await _openReader(fileName);
      if (!reader.isComplete) {
        if (!recoverIfIdle || !await _isIdle(fileName)) {
          return null;
        }
        await reader.recover(_nameFromFile(fileName));
      }
      return RecordingInfo(fileName, reader.header, reader.footer!, await reader.file.length());
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    } finally {
      await reader?.close();
    }
  }

  Future<bool> _isIdle(String fileName) async {
    var modified = await store.modified(fileName);
    return modified == null || clock.now().difference(modified) > activeWriteGrace;
  }

  // "Line 1 night shift 2026-10-23 220004.mqttrec" -> "Line 1 night shift"
  static String _nameFromFile(String fileName) {
    var name = fileName.substring(0, fileName.length - RecordingNames.extension.length);
    var stamp = RegExp(r' \d{4}-\d{2}-\d{2} \d{6}$');
    return name.replaceFirst(stamp, '');
  }
}
