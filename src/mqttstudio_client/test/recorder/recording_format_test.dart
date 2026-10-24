import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/recorder/format/record_codec.dart';
import 'package:mqttstudio/recorder/format/recording_reader.dart';
import 'package:mqttstudio/recorder/format/recording_writer.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/model/recording_summary.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';

RecordingHeader header({String id = 'rec-1'}) => RecordingHeader(
      id: id,
      startedAt: DateTime.utc(2026, 10, 23, 20),
      filters: [RecorderFilter('plant/#'), RecorderFilter('plant/debug/#', exclude: true)],
      broker: 'broker.local:1883',
      protocol: MqttProtocolVersion.v5,
      clientId: 'demo-rec-7f3a',
      projectName: 'Demo factory',
      appVersion: '1.0.3',
    );

RecordedMessage text(int offsetMs, String topic, String payload, {bool retain = false, bool snapshot = false}) =>
    RecordedMessage(
        offsetMicros: offsetMs * 1000,
        topic: topic,
        payload: Uint8List.fromList(utf8.encode(payload)),
        qos: MqttQos.atLeastOnce,
        retain: retain,
        snapshot: snapshot);

Future<List<RecordingEntry>> readAll(RecordingReader reader, {int? from}) => reader.entries(from: from).toList();

Future<RecordingReader> reopen(MemoryRecordingStore store, String name) async => RecordingReader.open(await store.open(name));

void main() {
  late MemoryRecordingStore store;

  setUp(() => store = MemoryRecordingStore());

  test('messages, markers and the footer survive a round trip', () async {
    var writer = await RecordingWriter.start(await store.create('a.mqttrec'), header());
    var properties = MqttMessageProperties(
      contentType: 'application/json',
      responseTopic: 'reply/1',
      correlationData: Uint8List.fromList([1, 2, 3]),
      messageExpiryInterval: 60,
      payloadFormatUtf8: true,
      userProperties: [MqttUserPropertyEntry('a', '1'), MqttUserPropertyEntry('a', '2')],
    );
    writer.addMessage(text(0, 'plant/state', '{"ok":true}', retain: true, snapshot: true));
    writer.addMessage(RecordedMessage(
        offsetMicros: 1500,
        topic: 'plant/image',
        payload: Uint8List.fromList([255, 216, 255, 0]),
        payloadLength: 10000,
        qos: MqttQos.exactlyOnce,
        truncated: true,
        properties: properties));
    writer.addMarker(RecordingMarker(2000, RecordingMarker.connectionLost));
    writer.addMessage(RecordedMessage(offsetMicros: 5000000000, topic: 'plant/state', payload: Uint8List(0)));
    var footer = await writer.finish(name: 'Night shift', durationMicros: 6000000000, bookmarks: [Bookmark(1000, 'Line stop')]);

    expect(footer.topics, ['plant/state', 'plant/image']);
    var reader = await reopen(store, 'a.mqttrec');
    expect(reader.isComplete, isTrue);
    expect(reader.header.clientId, 'demo-rec-7f3a');
    expect(reader.header.filters.last.exclude, isTrue);
    expect(reader.footer!.name, 'Night shift');
    expect(reader.footer!.duration, const Duration(microseconds: 6000000000));
    expect(reader.footer!.bookmarks.single.label, 'Line stop');

    var entries = await readAll(reader);
    expect(entries.length, 4);
    var first = (entries[0] as MessageEntry).message;
    expect(first.topic, 'plant/state');
    expect(utf8.decode(first.payload), '{"ok":true}');
    expect(first.qos, MqttQos.atLeastOnce);
    expect(first.retain && first.snapshot, isTrue);

    var image = (entries[1] as MessageEntry).message;
    expect(image.truncated, isTrue);
    expect(image.payloadLength, 10000);
    expect(image.payload, [255, 216, 255, 0]);
    expect(image.qos, MqttQos.exactlyOnce);
    expect(image.properties!.contentType, 'application/json');
    expect(image.properties!.responseTopic, 'reply/1');
    expect(image.properties!.correlationData, [1, 2, 3]);
    expect(image.properties!.messageExpiryInterval, 60);
    expect(image.properties!.payloadFormatUtf8, isTrue);
    expect(image.properties!.userProperties.map((p) => '${p.key}=${p.value}'), ['a=1', 'a=2']);

    expect((entries[2] as MarkerEntry).marker.kind, RecordingMarker.connectionLost);
    expect((entries[3] as MessageEntry).message.offsetMicros, 5000000000);
  });

  test('the summary counts, measures intervals and finds payload types', () async {
    var writer = await RecordingWriter.start(await store.create('s.mqttrec'), header());
    for (var i = 0; i < 10; i++) {
      writer.addMessage(text(i * 1000, 'plant/temp', i < 5 ? '20.5' : '${20 + i}'));
    }
    writer.addMessage(text(0, 'plant/state', '{"status":"running"}', retain: true, snapshot: true));
    writer.addMarker(RecordingMarker(9000, RecordingMarker.connectionLost));
    var footer = await writer.finish(name: 's', durationMicros: 10000000);

    var summary = footer.summary;
    expect(summary.messages, 11);
    expect(summary.markers[RecordingMarker.connectionLost], 1);
    var temp = summary.perTopic['plant/temp']!;
    expect(temp.count, 10);
    expect(temp.intervalMinMicros, 1000000);
    expect(temp.intervalMaxMicros, 1000000);
    expect(temp.averageInterval, const Duration(seconds: 1));
    expect(temp.medianInterval!.inMilliseconds, closeTo(1000, 1));
    expect(temp.mainKind, 'Number');
    expect(temp.numericMin, 20.5);
    expect(temp.numericMax, 29);
    expect(temp.consecutiveDuplicates, 4);
    expect(temp.peakRatePerSecond, 1);
    var state = summary.perTopic['plant/state']!;
    expect(state.mainKind, 'Json');
    expect(state.snapshotCount, 1);
    expect(state.retainedCount, 1);
  });

  test('the summary survives JSON', () {
    var summary = RecordingSummary()
      ..messages = 3
      ..perTopic['t'] = (TopicSummary()
        ..count = 3
        ..histogram[5] = 2
        ..numericMin = 1.5);
    var copy = RecordingSummary.fromJson(jsonDecode(jsonEncode(summary.toJson())) as Map<String, dynamic>);
    expect(copy.perTopic['t']!.histogram[5], 2);
    expect(copy.perTopic['t']!.numericMin, 1.5);
  });

  test('an unfinished recording is recovered up to its last intact record', () async {
    var writer = await RecordingWriter.start(await store.create('crash.mqttrec'), header());
    for (var i = 0; i < 5; i++) {
      writer.addMessage(text(i * 100, 'plant/temp', '$i'));
    }
    await writer.flush();
    // half of a sixth record, as if the app died while writing it
    var partial = RecordCodec.encodeMessage(text(600, 'plant/temp', '6'), 0, null);
    await (await store.open('crash.mqttrec')).append(Uint8List.sublistView(partial, 0, partial.length ~/ 2));

    var reader = await reopen(store, 'crash.mqttrec');
    expect(reader.isComplete, isFalse);
    var footer = await reader.recover('Crash');
    expect(footer.recovered, isTrue);
    expect(footer.summary.messages, 5);
    expect(footer.summary.markers[RecordingMarker.recovered], 1);

    var again = await reopen(store, 'crash.mqttrec');
    expect(again.isComplete, isTrue);
    var entries = await readAll(again);
    expect(entries.whereType<MessageEntry>().map((e) => utf8.decode(e.message.payload)), ['0', '1', '2', '3', '4']);
    expect(entries.last, isA<MarkerEntry>());
  });

  test('reading stops at a record with a wrong checksum', () async {
    var writer = await RecordingWriter.start(await store.create('bad.mqttrec'), header());
    writer.addMessage(text(0, 'plant/temp', 'one'));
    writer.addMessage(text(1, 'plant/temp', 'two'));
    await writer.flush();
    var bytes = store.bytesOf('bad.mqttrec');
    // flip a byte in the payload of the last message
    bytes[bytes.length - 6] ^= 0xff;
    store.replace('bad.mqttrec', bytes);

    var reader = await reopen(store, 'bad.mqttrec');
    var footer = await reader.recover('Bad');
    expect(footer.summary.messages, 1);
  });

  test('a footer rewrite keeps the messages', () async {
    var writer = await RecordingWriter.start(await store.create('r.mqttrec'), header());
    writer.addMessage(text(0, 'plant/temp', '1'));
    await writer.finish(name: 'Old', durationMicros: 1000);
    var reader = await reopen(store, 'r.mqttrec');
    await reader.rewriteFooter(reader.footer!
      ..name = 'New'
      ..notes = 'checked');

    var again = await reopen(store, 'r.mqttrec');
    expect(again.footer!.name, 'New');
    expect(again.footer!.notes, 'checked');
    expect((await readAll(again)).length, 1);
  });

  test('the seek index points at messages to continue reading from', () async {
    var writer = await RecordingWriter.start(await store.create('seek.mqttrec'), header());
    for (var i = 0; i < 2500; i++) {
      writer.addMessage(text(i, 'plant/a${i % 3}', '$i'));
    }
    await writer.finish(name: 'seek', durationMicros: 2500000);
    var reader = await reopen(store, 'seek.mqttrec');
    expect(reader.footer!.seekIndex.map((e) => e.index), [0, 1000, 2000]);

    var entry = reader.seekEntryFor(1500 * 1000)!;
    expect(entry.index, 1000);
    var rest = await readAll(reader, from: entry.position);
    expect(rest.length, 1500);
    var first = (rest.first as MessageEntry).message;
    expect(utf8.decode(first.payload), '1000');
    expect(first.topic, 'plant/a1');
  });

  test('a folder store writes, recovers and rewrites real files', () async {
    var folder = await Directory.systemTemp.createTemp('mqttrec');
    addTearDown(() => folder.delete(recursive: true));
    var library = RecordingLibrary(FolderRecordingStore(folder));
    var file = await library.create('Disk', DateTime(2026, 10, 23));
    var writer = await RecordingWriter.start(file, header());
    writer.addMessage(text(0, 'plant/temp', '1'));
    await writer.finish(name: 'Disk', durationMicros: 1000);
    library.finishedWriting(file.name);

    var info = (await library.list()).single;
    await library.updateMetadata(info, name: 'Disk renamed');
    var reader = await library.open((await library.list()).single);
    expect(reader.footer!.name, 'Disk renamed');
    expect((await readAll(reader)).length, 1);
    await reader.close();
  });

  test('the file name holds the name and the start time', () {
    var name = RecordingNames.fileNameFor('Line 1: night/shift', DateTime(2026, 10, 23, 22, 0, 4));
    expect(name, 'Line 1_ night_shift 2026-10-23 220004.mqttrec');
  });

  group('RecordingLibrary', () {
    late RecordingLibrary library;

    setUp(() => library = RecordingLibrary(store));

    Future<void> record(String name, DateTime startedAt, {String id = 'x'}) async {
      var file = await library.create(name, startedAt);
      var h = header(id: id)..startedAt = startedAt.toUtc();
      var writer = await RecordingWriter.start(file, h);
      writer.addMessage(text(0, 'plant/temp', '1'));
      await writer.finish(name: name, durationMicros: 1000);
      library.finishedWriting(file.name);
    }

    test('lists finished recordings newest first and hides the one being written', () async {
      await record('Older', DateTime(2026, 10, 22), id: 'a');
      await record('Newer', DateTime(2026, 10, 23), id: 'b');
      var file = await library.create('Running', DateTime(2026, 10, 24));
      await RecordingWriter.start(file, header(id: 'c'));

      var infos = await library.list();
      expect(infos.map((i) => i.name), ['Newer', 'Older']);
      expect((await library.findById('a'))!.name, 'Older');
    });

    test('recovers an unfinished recording nobody writes to', () async {
      var file = await store.create('Crashed 2026-10-23 220004.mqttrec');
      var writer = await RecordingWriter.start(file, header(id: 'crash'));
      writer.addMessage(text(0, 'plant/temp', '1'));
      await writer.flush();

      var infos = await library.list();
      expect(infos.single.name, 'Crashed');
      expect(infos.single.footer.recovered, isTrue);
    });

    test('renames, keeps notes and deletes', () async {
      await record('Night', DateTime(2026, 10, 23), id: 'n');
      var info = (await library.list()).single;
      var changes = 0;
      library.changedEvent.subscribe((_) => changes++);

      var renamed = await library.updateMetadata(info, name: 'Night shift', notes: 'line stop at 00:45');
      expect(renamed.name, 'Night shift');
      expect((await library.list()).single.footer.notes, 'line stop at 00:45');

      await library.delete(renamed);
      expect(await library.list(), isEmpty);
      expect(changes, 2);
    });

    test('two recordings with the same name and time get different files', () async {
      var first = await library.create('Same', DateTime(2026, 10, 23));
      var second = await library.create('Same', DateTime(2026, 10, 23));
      expect(first.name, isNot(second.name));
    });
  });
}
