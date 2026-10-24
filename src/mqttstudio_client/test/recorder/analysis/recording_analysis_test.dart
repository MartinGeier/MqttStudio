import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/common/utils/json_path.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/recorder/analysis/recording_analysis.dart';
import 'package:mqttstudio/recorder/analysis/recording_message_source.dart';
import 'package:mqttstudio/recorder/analysis/recording_values.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';
import '../../helpers/test_setup.dart';

void main() {
  group('JsonPath', () {
    test('parses and prints the subset', () {
      var path = JsonPath.parse(r"$.a['b c'][2].d");
      expect(path.segments, ['a', 'b c', 2, 'd']);
      expect(path.toString(), r"$.a['b c'][2].d");
      expect(JsonPath.parse(r'$').segments, isEmpty);
      expect(JsonPath.parse(r"$['it\'s']").segments, ["it's"]);
    });

    test('rejects what is not in the subset', () {
      for (var text in ['a.b', r'$.*', r'$..a', r'$[-1]', r'$.a[', r"$['a'", r'$.1a']) {
        expect(() => JsonPath.parse(text), throwsFormatException, reason: text);
      }
    });

    test('evaluates and finds numbers', () {
      var json = {
        'temp': 21.5,
        'pos': {'lat': 46.5, 'lon': 11.3},
        'list': [1, 'x', 3],
        'name': 'a'
      };
      expect(JsonPath.parse(r'$.pos.lat').evaluate(json), 46.5);
      expect(JsonPath.parse(r'$.list[2]').evaluate(json), 3);
      expect(JsonPath.parse(r'$.missing.x').evaluate(json), isNull);
      expect(JsonPath.numericPaths(json).map((p) => p.toString()),
          [r'$.temp', r'$.pos.lat', r'$.pos.lon', r'$.list[0]', r'$.list[2]']);
      expect(JsonPath.numericPaths(json, max: 2), hasLength(2));
    });
  });

  group('RecordingAnalyzer', () {
    late RecordingLibrary library;

    setUp(() => library = RecordingLibrary(MemoryRecordingStore()));

    Future<RecordingAnalysis> analyze(RecordingInfo info) async {
      var reader = await library.open(info);
      try {
        return (await RecordingAnalyzer.analyze(reader))!;
      } finally {
        await reader.close();
      }
    }

    test('finds gaps, labels connection loss and counts quick repeats', () async {
      var entries = <Object>[];
      // a/temp every second for 100 s, with a hole from 40 s to 70 s while the connection was lost
      for (var s = 0; s < 100; s++) {
        if (s >= 40 && s < 70) {
          if (s == 45) {
            entries.add(RecordingMarker(45 * 1000000, RecordingMarker.connectionLost));
          }
          continue;
        }
        entries.add(recorded(s.toDouble(), 'a/temp', '$s'));
        // a redelivery 50 ms later
        if (s == 10) {
          entries.add(recorded(10.05, 'a/temp', '10'));
        }
      }
      entries.add(recorded(99.5, 'b/json', '{"v": 1, "pos": {"lat": 46.5, "lon": 11.3}}'));
      var info = await writeRecording(library, 'Gaps', entries, durationMicros: 100000000);
      var analysis = await analyze(info);

      var threshold = RecordingAnalysis.defaultGapThreshold(info.footer.summary.perTopic['a/temp']);
      // 10 × the median from the histogram, which is about 1 s
      expect(threshold.inSeconds, inInclusiveRange(5, 12));
      var gaps = analysis.gapsOf('a/temp', threshold);
      expect(gaps, hasLength(1));
      expect(gaps.single.startMicros, 39000000);
      expect(gaps.single.lengthMicros, 31000000);
      expect(gaps.single.connectionLost, isTrue);
      expect(analysis.gapsOf('a/temp', Duration(seconds: 40)), isEmpty);

      expect(analysis.topics['a/temp']!.quickRepeats, 1);
      expect(analysis.topics['a/temp']!.quickRepeatOffsets, [10050000]);
      expect(analysis.markers.single.kind, RecordingMarker.connectionLost);
      expect(analysis.topics['b/json']!.jsonNumbers.map((p) => p.toString()), [r'$.v', r'$.pos.lat', r'$.pos.lon']);
    });

    test('density counts messages in a window', () async {
      var info = await writeRecording(
          library, 'Density', [for (var s = 0; s < 10; s++) recorded(s.toDouble(), 't', '$s')],
          durationMicros: 10000000);
      var analysis = await analyze(info);
      expect(analysis.density('t', 0, 10000000, 2), [5, 5]);
      expect(analysis.density('t', 2000000, 4000000, 2), [1, 1]);
      expect(analysis.density('missing', 0, 10, 3), [0, 0, 0]);
      // the coarse buckets give the same total when the offsets are dropped
      analysis.topics['t']!.offsets = null;
      expect(analysis.density('t', 0, 10000000, 2).reduce((a, b) => a + b), 10);
    });
  });

  group('RecordingValues', () {
    late RecordingLibrary library;

    setUp(() => library = RecordingLibrary(MemoryRecordingStore()));

    test('loads numbers and JSON values in a range with statistics', () async {
      var info = await writeRecording(library, 'Values', [
        for (var s = 0; s < 10; s++) ...[
          recorded(s.toDouble(), 'n', '${s * 2}'),
          recorded(s + 0.5, 'j', '{"t": $s, "pos": {"lat": 46.$s, "lon": 11.$s}}'),
        ],
        recorded(9.9, 'n', 'not a number'),
      ]);
      var reader = await library.open(info);
      try {
        var all = (await RecordingValues.load(reader, 'n', const ValueSelector.payload()))!;
        expect(all.count, 10);
        expect(all.min, 0);
        expect(all.max, 18);
        expect(all.average, 9);
        expect(all.skipped, 1);

        var range = (await RecordingValues.load(reader, 'j', ValueSelector.json(JsonPath.parse(r'$.t')),
            fromMicros: 2000000, toMicros: 5000000))!;
        expect(range.points.map((p) => p.value), [2, 3, 4]);

        var thin = (await RecordingValues.load(reader, 'n', const ValueSelector.payload(), maxPoints: 4))!;
        // two slices, each keeps its lowest and its highest value
        expect(thin.points.map((p) => p.value), [0, 8, 10, 18]);

        var track = (await RecordingValues.track(reader, 'j',
            latitude: JsonPath.parse(r'$.pos.lat'), longitude: JsonPath.parse(r'$.pos.lon')))!;
        expect(track, hasLength(10));
        expect(track.first.latitude, 46.0);
      } finally {
        await reader.close();
      }
    });
  });

  group('RecordingMessageSource', () {
    test('loads a range with colors from the filters and hides a filter', () async {
      var library = RecordingLibrary(MemoryRecordingStore());
      var info = await writeRecording(library, 'Source', [
        for (var s = 0; s < 10; s++) recorded(s.toDouble(), s.isEven ? 'a/x' : 'b/y', '$s'),
      ], filters: [
        RecorderFilter('a/#', color: TopicColor(Colors.blue)),
        RecorderFilter('b/#', color: TopicColor(Colors.pink)),
      ]);
      var source = RecordingMessageSource();
      var reader = await library.open(info);
      try {
        expect(await source.load(reader, fromMicros: 2000000, toMicros: 7000000), isTrue);
      } finally {
        await reader.close();
      }
      expect(source.isLive, isFalse);
      expect(source.messageBuffer.length, 6);
      // newest first, at the wall time of the recording
      var newest = source.messageBuffer.getMessages(null).first;
      expect(newest.topicName, 'b/y');
      expect(newest.receivedOn, DateTime.utc(2026, 10, 24, 8, 0, 7).toLocal());
      expect(source.getTopicColor('a/x').color.toARGB32(), Colors.blue.toARGB32());
      expect(source.topicSubscriptions.map((s) => s.topic), ['a/#', 'b/#']);

      source.toggleFilter('b/#');
      expect(source.messageBuffer.length, 3);
      expect(source.topicSubscriptions.last.paused, isTrue);
      expect(source.messageBuffer.getMessagesTree(null).children.map((n) => n.topicLevelName), ['a']);
    });
  });
}
