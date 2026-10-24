import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/recorder/model/compare_options.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';
import 'package:mqttstudio/recorder/tools/recording_comparer.dart';
import '../helpers/test_setup.dart';

void main() {
  late RecordingLibrary library;
  late RecordingComparer comparer;

  setUp(() {
    library = RecordingLibrary(MemoryRecordingStore());
    comparer = RecordingComparer(library);
  });

  // out/temp every second with a JSON payload and a time stamp, out/state twice
  Future<RecordingInfo> expected(String name, {String prefix = 'out/', double every = 1, int count = 10}) => writeRecording(library, name, [
        for (var i = 0; i < count; i++) ...[
          recorded(i * every, '${prefix}temp', '{"ts": ${1000 + i * 7}, "v": ${20 + i}, "unit": "C"}'),
          if (i == 0 || i == 5) recorded(i * every + 0.1, '${prefix}state', i == 0 ? 'idle' : 'run'),
        ]
      ]);

  test('a remap maps the topics of B onto those of A', () async {
    var a = await expected('Expected');
    var b = await expected('Actual', prefix: 'test/out/');
    expect((await comparer.compare(a, b, CompareOptions())).countOf(TopicCompareStatus.onlyInB), 2);
    var result = await comparer.compare(a, b, CompareOptions(remaps: [TopicRemap('test/out/', 'out/')]));
    expect(result.isEqual, isTrue);
    expect(result.topics.map((t) => t.topic), ['out/state', 'out/temp']);
    expect(result.topics.last.countA, 10);
  });

  test('finds payload differences by JSON path, honoring ignore paths and number tolerance', () async {
    var a = await expected('A');
    var b = await writeRecording(library, 'B', [
      for (var i = 0; i < 10; i++) ...[
        // other time stamps, key order and from the 4th message a slightly different value
        recorded(i.toDouble(), 'out/temp', '{"unit": "C", "v": ${20 + i + (i >= 3 ? 0.05 : 0)}, "ts": ${5000 + i}}'),
        if (i == 0 || i == 5) recorded(i + 0.1, 'out/state', i == 0 ? 'idle' : 'run'),
      ]
    ]);
    var strict = await comparer.compare(a, b, CompareOptions(ignorePaths: [r'$.ts']));
    var temp = strict.topics.firstWhere((t) => t.topic == 'out/temp');
    expect(temp.status, TopicCompareStatus.different);
    expect(temp.payloadsDiffer, isTrue);
    expect(temp.firstDifference!.index, 3);
    expect(temp.firstDifference!.path, r'$.v');
    expect(temp.firstDifference!.payloadA, contains('"v": 23'));

    var tolerant = await comparer.compare(a, b, CompareOptions(ignorePaths: [r'$.ts'], numberTolerance: 0.1));
    expect(tolerant.isEqual, isTrue);

    var withTs = await comparer.compare(a, b, CompareOptions(numberTolerance: 0.1));
    expect(withTs.topics.firstWhere((t) => t.topic == 'out/temp').firstDifference!.path, r'$.ts');
  });

  test('reports missing topics, count and timing differences', () async {
    var a = await expected('A');
    var b = await writeRecording(library, 'B', [
      for (var i = 0; i < 8; i++) recorded(i * 2.0, 'out/temp', '{"ts": ${1000 + i * 7}, "v": ${20 + i}, "unit": "C"}'),
      recorded(1, 'out/extra', 'x'),
    ]);
    var result = await comparer.compare(a, b, CompareOptions(countTolerance: 10));
    var byTopic = {for (var t in result.topics) t.topic: t};
    expect(byTopic['out/state']!.status, TopicCompareStatus.onlyInA);
    expect(byTopic['out/extra']!.status, TopicCompareStatus.onlyInB);
    var temp = byTopic['out/temp']!;
    expect(temp.countDiffers, isTrue);
    expect(temp.timingDiffers, isTrue);
    expect(temp.medianIntervalAMicros, 1000000);
    expect(temp.medianIntervalBMicros, 2000000);
    // B has fewer messages: its first missing one
    expect(temp.firstDifference!.index, 8);
    expect(temp.firstDifference!.payloadB, isNull);
    expect(result.countOf(TopicCompareStatus.different), 1);

    var loose = await comparer.compare(a, b,
        CompareOptions(countTolerance: 25, timingTolerance: 100, payloads: false));
    expect(loose.topics.firstWhere((t) => t.topic == 'out/temp').status, TopicCompareStatus.equal);
    expect(CompareResult.fromJson(loose.toJson()).topics.length, loose.topics.length);
  });

  test('compares only the chosen ranges', () async {
    var a = await expected('A');
    var b = await expected('B', count: 4);
    var result = await comparer.compare(a, b, CompareOptions(rangeAToMicros: 3500000, payloads: true));
    expect(result.isEqual, isTrue);
  });
}
