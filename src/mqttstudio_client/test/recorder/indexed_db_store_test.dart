import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_sembast.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/recorder/format/recording_writer.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/indexed_db_recording_store.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:sembast/sembast_memory.dart' show newDatabaseFactoryMemory;
import '../helpers/test_setup.dart';

// IndexedDB that fails while failures are left, as when the browser's quota is exceeded
class FailingIdbFactory implements IdbFactory {
  final IdbFactory inner;
  int failures = 0;

  FailingIdbFactory(this.inner);

  @override
  Future<Database> open(String dbName, {int? version, OnUpgradeNeededFunction? onUpgradeNeeded, OnBlockedFunction? onBlocked}) {
    if (failures > 0) {
      failures--;
      return Future.error(StateError('QuotaExceededError'));
    }
    return inner.open(dbName, version: version, onUpgradeNeeded: onUpgradeNeeded, onBlocked: onBlocked);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  test('a failed write fails only for its caller, later writes go through', () async {
    var factory = FailingIdbFactory(IdbFactorySembast(newDatabaseFactoryMemory()));
    var store = IndexedDbRecordingStore(factory);
    factory.failures = 1;
    await expectLater(store.create('a.mqttrec'), throwsStateError);
    var file = await store.create('b.mqttrec');
    await file.append(Uint8List.fromList([1, 2, 3]));
    await file.close();
    expect(await IndexedDbRecordingStore(factory).names(), ['b.mqttrec']);
    await store.delete('b.mqttrec');
    expect(await IndexedDbRecordingStore(factory).names(), isEmpty);
  });

  test('a closed file is no longer kept in memory', () async {
    var factory = IdbFactorySembast(newDatabaseFactoryMemory());
    var store = IndexedDbRecordingStore(factory);
    var file = await store.create('a.mqttrec');
    await file.append(Uint8List.fromList([1, 2, 3]));
    var second = await store.open('a.mqttrec');
    await file.close();
    expect(await second.length(), 3);
    await second.close();

    // another tab changes the file; this store reads it again
    var other = await IndexedDbRecordingStore(factory).open('a.mqttrec');
    await other.truncate(1);
    await other.close();
    var again = await store.open('a.mqttrec');
    expect(await again.length(), 1);
    await again.close();
  });

  test('importing an unfinished recording recovers it', () async {
    var source = IndexedDbRecordingStore(IdbFactorySembast(newDatabaseFactoryMemory()));
    var file = await source.create('Crashed 2026-10-23 220004.mqttrec');
    var writer = await RecordingWriter.start(
        file,
        RecordingHeader(
            id: 'crash',
            startedAt: DateTime.utc(2026, 10, 23),
            filters: [],
            broker: 'b',
            protocol: MqttProtocolVersion.v5,
            clientId: 'c',
            appVersion: ''));
    writer.addMessage(recorded(0, 'a', '1'));
    await writer.abandon();
    var bytes = await (await source.open(file.name)).read(0, 1 << 20);

    var library = RecordingLibrary(IndexedDbRecordingStore(IdbFactorySembast(newDatabaseFactoryMemory())));
    var info = await library.importBytes(file.name, bytes);
    expect(info.name, 'Crashed');
    expect(info.footer.recovered, isTrue);
    expect(info.footer.summary.messages, 1);
  });
}
