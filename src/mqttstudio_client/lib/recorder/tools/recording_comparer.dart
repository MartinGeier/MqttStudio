import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:mqttstudio/common/utils/json_path.dart';
import 'package:mqttstudio/recorder/format/recording_reader.dart';
import 'package:mqttstudio/recorder/model/compare_options.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';

class _TopicData {
  int count = 0;
  int lastOffset = -1;
  final List<int> intervals = [];
  // A only: the payloads and offsets in order, for the payload comparison
  final List<Uint8List> payloads = [];
  final List<int> offsets = [];
}

// Compares two recordings by topic: counts, payloads in order and timing (doc/recorder-design.md §9). The payloads
// of A are kept in memory while B is read, so A should fit into memory.
class RecordingComparer {
  static const int _yieldEvery = 2000;

  final RecordingLibrary library;
  void Function(double progress)? onProgress;

  RecordingComparer(this.library, {this.onProgress});

  Future<CompareResult> compare(RecordingInfo a, RecordingInfo b, CompareOptions options) async {
    var remap = PlaybackOptions(remaps: options.remaps);
    var ignored = {for (var path in options.ignorePaths) JsonPath.parse(path).toString()};
    var topicsA = <String, _TopicData>{};
    await _read(a, options.rangeAFromMicros, options.rangeAToMicros, 0, (message) {
      var data = topicsA.putIfAbsent(message.topic, _TopicData.new);
      _count(data, message);
      if (options.payloads) {
        data.payloads.add(message.payload);
        data.offsets.add(message.offsetMicros);
      }
    });

    var topicsB = <String, _TopicData>{};
    var differences = <String, PayloadDifference>{};
    await _read(b, options.rangeBFromMicros, options.rangeBToMicros, 0.5, (message) {
      var topic = remap.remap(message.topic);
      var data = topicsB.putIfAbsent(topic, _TopicData.new);
      var index = data.count;
      _count(data, message);
      var dataA = topicsA[topic];
      if (!options.payloads || dataA == null || differences.containsKey(topic)) {
        return;
      }
      if (index >= dataA.payloads.length) {
        differences[topic] = PayloadDifference(index, -1, message.offsetMicros, null, _text(message.payload), null);
        return;
      }
      var path = _differs(dataA.payloads[index], message.payload, ignored, options.numberTolerance);
      if (path != null) {
        differences[topic] = PayloadDifference(index, dataA.offsets[index], message.offsetMicros, _text(dataA.payloads[index]),
            _text(message.payload), path.isEmpty ? null : path);
      }
    });

    var result = <TopicComparison>[];
    for (var topic in {...topicsA.keys, ...topicsB.keys}.toList()..sort()) {
      var dataA = topicsA[topic];
      var dataB = topicsB[topic];
      var comparison = TopicComparison(topic,
          countA: dataA?.count ?? 0,
          countB: dataB?.count ?? 0,
          medianIntervalAMicros: dataA == null ? null : _median(dataA.intervals),
          medianIntervalBMicros: dataB == null ? null : _median(dataB.intervals));
      if (dataA == null) {
        comparison.status = TopicCompareStatus.onlyInB;
      } else if (dataB == null) {
        comparison.status = TopicCompareStatus.onlyInA;
      } else {
        comparison.countDiffers = options.counts && _beyond(dataA.count, dataB.count, options.countTolerance);
        comparison.timingDiffers = options.timing &&
            comparison.medianIntervalAMicros != null &&
            comparison.medianIntervalBMicros != null &&
            _beyond(comparison.medianIntervalAMicros!, comparison.medianIntervalBMicros!, options.timingTolerance);
        var difference = differences[topic];
        // B has fewer messages: the first one it misses
        if (options.payloads && difference == null && dataB.count < dataA.payloads.length) {
          var index = dataB.count;
          difference = PayloadDifference(index, dataA.offsets[index], -1, _text(dataA.payloads[index]), null, null);
        }
        comparison.payloadsDiffer = difference != null;
        comparison.firstDifference = difference;
        if (comparison.countDiffers || comparison.timingDiffers || comparison.payloadsDiffer) {
          comparison.status = TopicCompareStatus.different;
        }
      }
      result.add(comparison);
    }
    onProgress?.call(1);
    return CompareResult(a.name, b.name, options, result);
  }

  static void _count(_TopicData data, RecordedMessage message) {
    if (data.lastOffset >= 0) {
      data.intervals.add(message.offsetMicros - data.lastOffset);
    }
    data.lastOffset = message.offsetMicros;
    data.count++;
  }

  // more than tolerance percent apart
  static bool _beyond(int a, int b, double tolerancePercent) {
    if (a == b) {
      return false;
    }
    return (a - b).abs() / max(1, a.abs()) * 100 > tolerancePercent;
  }

  static int? _median(List<int> values) {
    if (values.isEmpty) {
      return null;
    }
    var sorted = List.of(values)..sort();
    return sorted[sorted.length ~/ 2];
  }

  static String _text(Uint8List payload) {
    try {
      return utf8.decode(payload);
    } on FormatException {
      return base64Encode(payload);
    }
  }

  // null when equal, '' when different without a JSON path, else the JSON path that differs
  static String? _differs(Uint8List a, Uint8List b, Set<String> ignored, double tolerance) {
    if (_sameBytes(a, b)) {
      return null;
    }
    String textA;
    String textB;
    try {
      textA = utf8.decode(a);
      textB = utf8.decode(b);
    } on FormatException {
      return '';
    }
    var numberA = num.tryParse(textA.trim());
    var numberB = num.tryParse(textB.trim());
    if (numberA != null && numberB != null) {
      return (numberA - numberB).abs() <= tolerance ? null : '';
    }
    Object? jsonA;
    Object? jsonB;
    try {
      jsonA = jsonDecode(textA);
      jsonB = jsonDecode(textB);
    } on FormatException {
      return '';
    }
    return _jsonDiff(jsonA, jsonB, const [], ignored, tolerance);
  }

  // key order doesn't matter; returns the path of the first difference
  static String? _jsonDiff(Object? a, Object? b, List<Object> path, Set<String> ignored, double tolerance) {
    var here = JsonPath(path).toString();
    if (ignored.contains(here)) {
      return null;
    }
    if (a is num && b is num) {
      return (a - b).abs() <= tolerance ? null : here;
    }
    if (a is Map && b is Map) {
      for (var key in {...a.keys, ...b.keys}) {
        var child = [...path, '$key'];
        if (ignored.contains(JsonPath(child).toString())) {
          continue;
        }
        if (!a.containsKey(key) || !b.containsKey(key)) {
          return JsonPath(child).toString();
        }
        var difference = _jsonDiff(a[key], b[key], child, ignored, tolerance);
        if (difference != null) {
          return difference;
        }
      }
      return null;
    }
    if (a is List && b is List) {
      for (var i = 0; i < max(a.length, b.length); i++) {
        if (i >= a.length || i >= b.length) {
          return JsonPath([...path, i]).toString();
        }
        var difference = _jsonDiff(a[i], b[i], [...path, i], ignored, tolerance);
        if (difference != null) {
          return difference;
        }
      }
      return null;
    }
    return a == b ? null : here;
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  Future<void> _read(RecordingInfo info, int? fromMicros, int? toMicros, double progressBase,
      void Function(RecordedMessage message) visit) async {
    var reader = await library.open(info);
    try {
      var from = fromMicros ?? 0;
      var to = toMicros ?? info.footer.durationMicros;
      var end = reader.footerPosition ?? await reader.file.length();
      var cursor = reader.cursor(from: reader.seekEntryFor(from)?.position);
      var count = 0;
      while (true) {
        var entry = await cursor.next();
        if (entry == null) {
          break;
        }
        if (entry is MessageEntry) {
          var offset = entry.message.offsetMicros;
          if (offset > to) {
            break;
          }
          if (offset >= from) {
            visit(entry.message);
          }
        }
        if (++count % _yieldEvery == 0) {
          onProgress?.call(progressBase + 0.5 * (entry.position - reader.dataStart) / max(1, end - reader.dataStart));
          await Future<void>.delayed(Duration.zero);
        }
      }
    } finally {
      await reader.close();
    }
  }
}
