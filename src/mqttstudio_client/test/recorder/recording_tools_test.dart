import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/common/utils/json_path.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/recorder/format/recording_reader.dart';
import 'package:mqttstudio/recorder/model/anonymize_rule.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';
import 'package:mqttstudio/recorder/tools/recording_editor.dart';
import 'package:mqttstudio/recorder/tools/recording_export.dart';
import 'package:mqttstudio/recorder/tools/recording_import.dart';
import '../helpers/test_setup.dart';

RecordedMessage retained(double seconds, String topic, String payload) => RecordedMessage(
    offsetMicros: (seconds * 1000000).round(),
    topic: topic,
    payload: Uint8List.fromList(utf8.encode(payload)),
    retain: true,
    qos: MqttQos.atLeastOnce);

void main() {
  late RecordingLibrary library;
  late RecordingEditor editor;

  setUp(() {
    library = RecordingLibrary(MemoryRecordingStore());
    editor = RecordingEditor(library);
  });

  Future<List<Object>> entriesOf(RecordingInfo info) async {
    var reader = await library.open(info);
    try {
      return [
        for (var entry in await reader.entries().toList())
          if (entry is MessageEntry) entry.message else (entry as MarkerEntry).marker
      ];
    } finally {
      await reader.close();
    }
  }

  Future<List<RecordedMessage>> messagesOf(RecordingInfo info) async => (await entriesOf(info)).whereType<RecordedMessage>().toList();

  List<String> payloads(List<RecordedMessage> messages) => [for (var m in messages) utf8.decode(m.payload)];

  // a/temp every second for 10 s, a/state retained at 1 s and 6 s, a connection loss at 4.5 s, bookmark at 7 s
  Future<RecordingInfo> source() => writeRecording(
      library,
      'Line',
      [
        for (var s = 0; s < 10; s++) ...[
          recorded(s.toDouble(), 'a/temp', '$s'),
          if (s == 1) retained(1.5, 'a/state', 'idle'),
          if (s == 4) RecordingMarker(4500000, RecordingMarker.connectionLost),
          if (s == 6) retained(6.5, 'a/state', 'run'),
        ],
      ],
      durationMicros: 10000000,
      filters: [RecorderFilter('a/#')],
      bookmarks: [Bookmark(7000000, 'Here')]);

  group('RecordingEditor', () {
    test('trim rebases the range and starts with the retained state', () async {
      var info = await source();
      info = await library.updateMetadata(info, projectName: 'Line project');
      var trimmed = await editor.trim(info, 3000000, 7000000);
      // an edit stays with the project of its source
      expect(trimmed.projectName, 'Line project');
      expect(trimmed.name, 'Line (trimmed)');
      expect(trimmed.header.origin, RecordingOrigin.edit);
      expect(trimmed.header.sourceRecordingIds, [info.id]);
      expect(trimmed.header.startedAt, info.header.startedAt.add(Duration(seconds: 3)));
      expect(trimmed.footer.durationMicros, 4000000);
      expect(trimmed.footer.bookmarks.single.offsetMicros, 4000000);
      var messages = await messagesOf(trimmed);
      // the snapshot first, then 3…7 with the state change at 6.5
      expect(payloads(messages), ['idle', '3', '4', '5', '6', 'run', '7']);
      expect(messages.first.snapshot, isTrue);
      expect(messages.first.offsetMicros, 0);
      expect(messages[1].offsetMicros, 0);
      expect((await entriesOf(trimmed)).whereType<RecordingMarker>().single.offsetMicros, 1500000);
    });

    test('a metadata change keeps what an older RecordingInfo does not know', () async {
      var info = await source();
      await library.updateMetadata(info, name: 'Renamed');
      // info still has the old name
      var updated = await library.updateMetadata(info, notes: 'n');
      expect(updated.name, 'Renamed');
      expect((await library.list()).single.footer.notes, 'n');
    });

    test('keeps topics, renames them and splits', () async {
      var info = await source();
      var kept = await editor.keepTopics(info, {'a/state'});
      expect(payloads(await messagesOf(kept)), ['idle', 'run']);
      expect(kept.name, 'Line (a/state)');

      var renamed = await editor.renameTopics(info, [TopicRemap('a/', 'site1/a/')]);
      expect(renamed.footer.topics, containsAll(['site1/a/temp', 'site1/a/state']));
      expect(renamed.header.filters.single.filter, 'site1/a/#');

      var parts = await editor.splitAt(info, info.footer.bookmarks.map((b) => b.offsetMicros).toList());
      expect(parts.map((p) => p.name), ['Line (part 1)', 'Line (part 2)']);
      expect(parts.first.footer.durationMicros, 7000000);
      expect(payloads(await messagesOf(parts.last)).first, 'run');

      var byTopic = await editor.splitByTopic(info);
      expect(byTopic.map((p) => p.footer.topics.single), ['a/state', 'a/temp']);
    });

    test('merge interleaves by wall time', () async {
      var first = await writeRecording(library, 'One', [recorded(0, 'x', '1'), recorded(2, 'x', '3')], durationMicros: 2000000);
      // starts a second later
      var second = await writeRecording(library, 'Two', [recorded(0, 'y', '2'), recorded(4, 'y', '4')],
          durationMicros: 5000000, startedAt: DateTime.utc(2026, 10, 24, 8, 0, 1));
      var merged = await editor.merge([second, first], 'Both');
      var messages = await messagesOf(merged);
      expect(payloads(messages), ['1', '2', '3', '4']);
      expect(messages.map((m) => m.offsetMicros), [0, 1000000, 2000000, 5000000]);
      expect(merged.header.startedAt, first.header.startedAt);
      expect(merged.header.sourceRecordingIds, [second.id, first.id]);
      expect(merged.footer.durationMicros, 6000000);
      expect(merged.header.filters.single.filter, '#');
    });

    test('anonymize hashes consistently, masks, fixes, removes and jitters', () async {
      var info = await writeRecording(library, 'Secret', [
        recorded(0, 'plant/ACME-01/state', '{"user": "anna", "temp": 20, "ip": "10.0.0.1"}'),
        recorded(1, 'plant/ACME-01/state', '{"user": "anna", "temp": 30, "ip": "10.0.0.2"}'),
        recorded(2, 'plant/ACME-01/log', 'secret text'),
      ]);
      var rules = [
        AnonymizeRule('plant/+/state', AnonymizeTarget.jsonPath, AnonymizeAction.hash, jsonPath: r'$.user'),
        AnonymizeRule('plant/+/state', AnonymizeTarget.jsonPath, AnonymizeAction.remove, jsonPath: r'$.ip'),
        AnonymizeRule('plant/+/state', AnonymizeTarget.jsonPath, AnonymizeAction.jitterNumber, jsonPath: r'$.temp', percent: 10),
        AnonymizeRule('plant/+/log', AnonymizeTarget.wholePayload, AnonymizeAction.mask),
        AnonymizeRule('plant/#', AnonymizeTarget.topicLevel, AnonymizeAction.fixed, level: 1, value: 'site'),
      ];
      var anonymized = await editor.anonymize(info, rules);
      expect(anonymized.name, 'Secret (anonymized)');
      var messages = await messagesOf(anonymized);
      expect(messages.map((m) => m.topic), ['plant/site/state', 'plant/site/state', 'plant/site/log']);
      var first = jsonDecode(utf8.decode(messages[0].payload)) as Map<String, dynamic>;
      var second = jsonDecode(utf8.decode(messages[1].payload)) as Map<String, dynamic>;
      expect(first['user'], hasLength(12));
      expect(first['user'], second['user']);
      expect(first['user'], isNot('anna'));
      expect(first.containsKey('ip'), isFalse);
      expect(first['temp'], inInclusiveRange(18, 22));
      expect(first['temp'], isA<int>());
      expect(utf8.decode(messages[2].payload), '***********');

      // another run uses another salt
      var again = Anonymizer(rules).hash('anna');
      expect(again, isNot(first['user']));
    });

    test('anonymize rules round trip through their file and report problems', () {
      var rules = [
        AnonymizeRule('a/#', AnonymizeTarget.jsonPath, AnonymizeAction.fixed, jsonPath: r'$.x', value: '0'),
        AnonymizeRule('a/#', AnonymizeTarget.wholePayload, AnonymizeAction.hash),
      ];
      var decoded = AnonymizeRule.decodeList(AnonymizeRule.encodeList(rules));
      expect(decoded.map((r) => r.toJson()), rules.map((r) => r.toJson()));
      expect(() => AnonymizeRule.decodeList('{"a": 1}'), throwsFormatException);
      expect(AnonymizeRule('a/#', AnonymizeTarget.jsonPath, AnonymizeAction.mask, jsonPath: 'x').problem, 'jsonPath');
      expect(AnonymizeRule('a/#', AnonymizeTarget.topicLevel, AnonymizeAction.mask).problem, 'level');
      expect(rules.first.problem, isNull);
    });

    test('anonymizes user properties with an option', () {
      var message = RecordedMessage(
          offsetMicros: 0,
          topic: 'a',
          payload: Uint8List.fromList(utf8.encode('x')),
          properties: MqttMessageProperties(userProperties: [MqttUserPropertyEntry('user', 'anna')]));
      var rule = AnonymizeRule('a', AnonymizeTarget.wholePayload, AnonymizeAction.fixed, value: 'hidden');
      expect(Anonymizer([rule]).apply(message).properties!.userProperties.single.value, 'anna');
      expect(Anonymizer([rule], properties: true, random: Random(1)).apply(message).properties!.userProperties.single.value,
          'hidden');
    });
  });

  group('export and import', () {
    Future<String> export(RecordingInfo info, ExportFormat format,
        {Set<String>? topics, int? from, int? to, List<JsonPath> columns = const []}) async {
      var reader = await library.open(info);
      try {
        var out = StringBuffer();
        await RecordingExport.writeText(reader, out,
            format: format, topics: topics, fromMicros: from, toMicros: to, columns: columns);
        return out.toString();
      } finally {
        await reader.close();
      }
    }

    test('JSON lines round trip keeps messages, markers, bookmarks and binary payloads', () async {
      var info = await writeRecording(library, 'Round', [
        recorded(0, 'a/temp', '21.5'),
        RecordingMarker(500000, RecordingMarker.connectionLost),
        RecordedMessage(offsetMicros: 1000000, topic: 'a/img', payload: Uint8List.fromList([0xff, 0xd8, 0xff, 0x00])),
        retained(2, 'a/state', 'line, "one"'),
      ], bookmarks: [Bookmark(1000000, 'B')], durationMicros: 3000000);
      var text = await export(info, ExportFormat.jsonLines);
      var lines = const LineSplitter().convert(text);
      expect(jsonDecode(lines.first)['format'], 'mqttstudio-recording');
      expect(lines.where((l) => l.contains('payloadBase64')), hasLength(1));

      var imported = await RecordingImport(library).importText(text, ImportFormat.jsonLines, name: 'Back');
      expect(imported.header.origin, RecordingOrigin.import);
      expect(imported.header.startedAt, info.header.startedAt);
      expect(imported.footer.bookmarks.single.label, 'B');
      var entries = await entriesOf(imported);
      expect(entries.whereType<RecordingMarker>().single.offsetMicros, 500000);
      var messages = entries.whereType<RecordedMessage>().toList();
      expect(messages[1].payload, [0xff, 0xd8, 0xff, 0x00]);
      expect(utf8.decode(messages[2].payload), 'line, "one"');
      expect(messages[2].retain, isTrue);
      expect(messages[2].offsetMicros, 2000000);
    });

    test('CSV exports topics and a range with JSON path columns and imports again', () async {
      var info = await writeRecording(library, 'Csv', [
        recorded(0, 'a', '{"v": 1}'),
        recorded(1, 'b', 'skip'),
        recorded(2, 'a', '{"v": 2, "s": "x,y"}'),
        recorded(3, 'a', 'multi\nline'),
      ]);
      var text = await export(info, ExportFormat.csv, topics: {'a'}, from: 1000000, columns: [JsonPath.parse(r'$.v')]);
      var lines = const LineSplitter().convert(text);
      expect(lines.first, r'time,offset_ms,topic,qos,retain,payload,payload_encoding,$.v');
      expect(lines[1], contains(',1000.000,a,0,false,"{""v"": 2, ""s"": ""x,y""}",text,2'));

      var imported = await RecordingImport(library).importText(text, ImportFormat.csv, name: 'Csv back');
      var messages = await messagesOf(imported);
      expect(payloads(messages), ['{"v": 2, "s": "x,y"}', 'multi\nline']);
      expect(messages.last.offsetMicros, 1000000);
    });

    test('imports mosquitto_sub output with and without times', () async {
      var importer = RecordingImport(library);
      var timed = await importer.importText(
          '1729760000.250000 plant/temp 21.5\n1729760001.750000 plant/temp 21.6\nnot a line\n', ImportFormat.mosquittoTimed,
          name: 'Timed');
      expect(importer.skipped, 1);
      expect((await messagesOf(timed)).last.offsetMicros, 1500000);
      expect(timed.header.startedAt, DateTime.utc(2024, 10, 24, 8, 53, 20, 250));

      var verbose = await importer.importText('a/b hello world\na/c 2\n', ImportFormat.mosquittoVerbose,
          name: 'Verbose', interval: Duration(milliseconds: 500));
      var messages = await messagesOf(verbose);
      expect(payloads(messages), ['hello world', '2']);
      expect(messages.last.offsetMicros, 500000);

      expect(RecordingImport.formatOf('x.txt', '1729760000.25 a b'), ImportFormat.mosquittoTimed);
      expect(RecordingImport.formatOf('x.txt', 'a/b c'), ImportFormat.mosquittoVerbose);
      expect(RecordingImport.formatOf('x.csv', 'whatever'), ImportFormat.csv);
      expect(RecordingImport.formatOf('x.jsonl', ''), ImportFormat.jsonLines);
      expect(() => importer.importText('', ImportFormat.mosquittoVerbose, name: 'Empty'), throwsFormatException);
    });
  });
}
