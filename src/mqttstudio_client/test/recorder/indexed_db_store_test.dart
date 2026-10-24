import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_sembast.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/indexed_db_recording_store.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:sembast/sembast_memory.dart';
import '../helpers/test_setup.dart';

void main() {
  test('keeps files in chunks across appends, reads, truncation and a new store', () async {
    // one factory stands for the browser's IndexedDB; a new store on it is a page reload
    var factory = IdbFactorySembast(newDatabaseFactoryMemory());
    var store = IndexedDbRecordingStore(factory);
    var size = IndexedDbRecordingStore.chunkSize;
    var bytes = Uint8List.fromList(List.generate(size * 2 + 100, (i) => i % 251));
    var file = await store.create('a.mqttrec');
    await file.append(Uint8List.sublistView(bytes, 0, size - 10));
    await file.append(Uint8List.sublistView(bytes, size - 10));
    expect(await file.length(), bytes.length);
    expect(await file.read(size - 20, 40), Uint8List.sublistView(bytes, size - 20, size + 20));

    var reloaded = IndexedDbRecordingStore(factory);
    expect(await reloaded.names(), ['a.mqttrec']);
    expect(await reloaded.modified('a.mqttrec'), isNotNull);
    var again = await reloaded.open('a.mqttrec');
    expect(await again.read(0, bytes.length), bytes);

    await again.truncate(size + 5);
    await again.append(Uint8List.fromList([1, 2, 3]));
    var third = await IndexedDbRecordingStore(factory).open('a.mqttrec');
    expect(await third.length(), size + 8);
    expect(await third.read(size + 4, 10), [bytes[size + 4], 1, 2, 3]);

    await reloaded.delete('a.mqttrec');
    expect(await IndexedDbRecordingStore(factory).names(), isEmpty);
    expect(await IndexedDbRecordingStore(factory).exists('a.mqttrec'), isFalse);
  });

  test('a library on it lists, edits and survives a reload', () async {
    var factory = IdbFactorySembast(newDatabaseFactoryMemory());
    var library = RecordingLibrary(IndexedDbRecordingStore(factory));
    var info = await writeRecording(library, 'Web', [recorded(0, 'a', '1'), recorded(1, 'a', '2')]);
    await library.updateMetadata(info, bookmarks: [Bookmark(500000, 'B')]);

    var after = await RecordingLibrary(IndexedDbRecordingStore(factory)).list();
    expect(after.single.name, 'Web');
    expect(after.single.footer.bookmarks.single.label, 'B');
    expect(after.single.footer.summary.messages, 2);
  });
}
