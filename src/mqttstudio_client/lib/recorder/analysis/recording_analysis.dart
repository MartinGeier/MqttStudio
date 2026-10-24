import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:mqttstudio/common/utils/json_path.dart';
import 'package:mqttstudio/recorder/format/recording_reader.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_summary.dart';
import 'package:typed_data/typed_buffers.dart';

// A pause in the messages of a topic (doc/recorder-design.md §7.5)
class RecordingGap {
  final String topic;
  final int startMicros;
  final int lengthMicros;
  // the recorder's connection was lost during the gap
  bool connectionLost = false;

  RecordingGap(this.topic, this.startMicros, this.lengthMicros);

  int get endMicros => startMicros + lengthMicros;
}

// What one pass over a recording found about one topic
class TopicAnalysis {
  final String topic;
  // density over the whole recording, RecordingAnalysis.bucketCount buckets
  final Int32List buckets = Int32List(RecordingAnalysis.bucketCount);
  // the offset of every message, for the density at any zoom; null when the recording has too many messages
  Float64Buffer? offsets = Float64Buffer();
  // intervals of at least minGapMicros, so the gap threshold can change without another pass
  final List<RecordingGap> gapCandidates = [];
  // 1 s, or twice the median interval: a shorter pause is no gap
  final int minGapMicros;
  // the same payload again within RecordingAnalysis.repeatWindow, e.g. QoS 1 redeliveries
  int quickRepeats = 0;
  final List<int> quickRepeatOffsets = [];
  // paths of numbers in the JSON payloads, for the charts
  final Set<JsonPath> jsonNumbers = {};
  int messages = 0;
  int _lastOffset = -1;
  int _jsonSamples = 0;
  // payload hashes of the messages within the repeat window, oldest first
  final List<(int, int)> _recent = [];

  TopicAnalysis(this.topic, this.minGapMicros);
}

// The data the TIMELINE, the gap and duplicate lists and the CHARTS need, from one pass over the messages
class RecordingAnalysis {
  static const int bucketCount = 2048;
  static const int maxExactOffsets = 4000000;
  static const Duration minGap = Duration(seconds: 1);
  static const Duration minDefaultGap = Duration(seconds: 5);
  static const Duration repeatWindow = Duration(milliseconds: 100);
  static const int maxListed = 1000;
  static const int maxGapCandidates = 10000;
  static const int maxJsonPaths = 50;

  final int durationMicros;
  final Map<String, TopicAnalysis> topics = {};
  final List<RecordingMarker> markers = [];

  RecordingAnalysis(this.durationMicros);

  bool get hasExactOffsets => topics.values.every((topic) => topic.offsets != null);

  // gaps longer than 10 × the median interval, at least 5 s
  static Duration defaultGapThreshold(TopicSummary? summary) {
    var median = summary?.medianInterval;
    if (median == null) {
      return minDefaultGap;
    }
    var tenTimes = median * 10;
    return tenTimes > minDefaultGap ? tenTimes : minDefaultGap;
  }

  List<RecordingGap> gapsOf(String topic, Duration threshold) =>
      topics[topic]?.gapCandidates.where((gap) => gap.lengthMicros > threshold.inMicroseconds).toList() ?? [];

  // message counts of a topic in `bins` equal parts of [fromMicros, toMicros)
  List<int> density(String topic, int fromMicros, int toMicros, int bins) {
    var counts = List.filled(bins, 0);
    var analysis = topics[topic];
    if (analysis == null || toMicros <= fromMicros || bins <= 0) {
      return counts;
    }
    var span = (toMicros - fromMicros) / bins;
    var offsets = analysis.offsets;
    if (offsets != null) {
      var index = _lowerBound(offsets, fromMicros.toDouble());
      for (var bin = 0; bin < bins; bin++) {
        var end = fromMicros + span * (bin + 1);
        var count = 0;
        while (index < offsets.length && offsets[index] < end) {
          count++;
          index++;
        }
        counts[bin] = count;
      }
      return counts;
    }
    // without offsets, spread the fixed buckets over the bins they overlap
    var bucketSpan = max(1, durationMicros) / bucketCount;
    for (var bucket = 0; bucket < bucketCount; bucket++) {
      var count = analysis.buckets[bucket];
      if (count == 0) {
        continue;
      }
      var middle = (bucket + 0.5) * bucketSpan;
      if (middle < fromMicros || middle >= toMicros) {
        continue;
      }
      counts[min(bins - 1, ((middle - fromMicros) / span).floor())] += count;
    }
    return counts;
  }

  static int _lowerBound(Float64Buffer values, double value) {
    var low = 0;
    var high = values.length;
    while (low < high) {
      var middle = (low + high) >> 1;
      if (values[middle] < value) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}

// Builds a RecordingAnalysis from a finished recording. It runs on the main isolate and yields every few thousand
// records, so the UI stays responsive and the pass can be cancelled.
class RecordingAnalyzer {
  static const int _yieldEvery = 2000;
  static const int _jsonSampleCount = 20;
  static const int _jsonSampleEvery = 1000;
  static const int _maxJsonLength = 64 * 1024;

  static Future<RecordingAnalysis?> analyze(RecordingReader reader,
      {void Function(double progress)? onProgress, bool Function()? isCancelled}) async {
    var footer = reader.footer!;
    var analysis = RecordingAnalysis(max(1, footer.durationMicros));
    var exact = footer.summary.messages <= RecordingAnalysis.maxExactOffsets;
    var end = reader.footerPosition ?? await reader.file.length();
    var start = reader.dataStart;
    var cursor = reader.cursor();
    var count = 0;
    while (true) {
      var entry = await cursor.next();
      if (entry == null) {
        break;
      }
      switch (entry) {
        case MessageEntry(:var message):
          _add(analysis, message, exact, footer.summary);
        case MarkerEntry(:var marker):
          analysis.markers.add(marker);
      }
      if (++count % _yieldEvery == 0) {
        onProgress?.call((entry.position - start) / max(1, end - start));
        await Future<void>.delayed(Duration.zero);
        if (isCancelled?.call() ?? false) {
          return null;
        }
      }
    }
    _markConnectionLoss(analysis);
    onProgress?.call(1);
    return analysis;
  }

  static void _add(RecordingAnalysis analysis, RecordedMessage message, bool exact, RecordingSummary summary) {
    var topic = analysis.topics[message.topic] ??= _newTopic(message.topic, exact, summary.perTopic[message.topic]);
    var offset = message.offsetMicros;
    topic.messages++;
    var bucket = (offset * RecordingAnalysis.bucketCount / analysis.durationMicros).floor();
    topic.buckets[bucket.clamp(0, RecordingAnalysis.bucketCount - 1)]++;
    topic.offsets?.add(offset.toDouble());
    if (topic._lastOffset >= 0 &&
        offset - topic._lastOffset >= topic.minGapMicros &&
        topic.gapCandidates.length < RecordingAnalysis.maxGapCandidates) {
      topic.gapCandidates.add(RecordingGap(message.topic, topic._lastOffset, offset - topic._lastOffset));
    }
    topic._lastOffset = offset;
    _checkRepeat(topic, message);
    _sampleJson(topic, message);
  }

  static TopicAnalysis _newTopic(String topic, bool exact, TopicSummary? summary) {
    var median = summary?.medianInterval?.inMicroseconds ?? 0;
    return TopicAnalysis(topic, max(RecordingAnalysis.minGap.inMicroseconds, 2 * median))
      ..offsets = exact ? Float64Buffer() : null;
  }

  static void _checkRepeat(TopicAnalysis topic, RecordedMessage message) {
    var window = RecordingAnalysis.repeatWindow.inMicroseconds;
    var recent = topic._recent;
    while (recent.isNotEmpty && message.offsetMicros - recent.first.$1 > window) {
      recent.removeAt(0);
    }
    var hash = Object.hash(message.payloadLength, Object.hashAll(message.payload));
    if (recent.any((entry) => entry.$2 == hash)) {
      topic.quickRepeats++;
      if (topic.quickRepeatOffsets.length < RecordingAnalysis.maxListed) {
        topic.quickRepeatOffsets.add(message.offsetMicros);
      }
    }
    recent.add((message.offsetMicros, hash));
    if (recent.length > 64) {
      recent.removeAt(0);
    }
  }

  // parses a few JSON payloads of each topic to find the numbers a chart can show
  static void _sampleJson(TopicAnalysis topic, RecordedMessage message) {
    var sample = topic._jsonSamples < _jsonSampleCount || topic.messages % _jsonSampleEvery == 0;
    if (!sample || message.truncated || message.payload.isEmpty || message.payload.length > _maxJsonLength) {
      return;
    }
    var first = message.payload.first;
    // { or [
    if (first != 0x7b && first != 0x5b) {
      return;
    }
    topic._jsonSamples++;
    try {
      var json = jsonDecode(utf8.decode(message.payload));
      var room = RecordingAnalysis.maxJsonPaths - topic.jsonNumbers.length;
      if (room > 0) {
        topic.jsonNumbers.addAll(JsonPath.numericPaths(json, max: room));
      }
    } on FormatException {
      return;
    }
  }

  static void _markConnectionLoss(RecordingAnalysis analysis) {
    var losses = analysis.markers.where((marker) => marker.kind == RecordingMarker.connectionLost).toList();
    if (losses.isEmpty) {
      return;
    }
    for (var topic in analysis.topics.values) {
      for (var gap in topic.gapCandidates) {
        gap.connectionLost = losses.any((loss) => loss.offsetMicros >= gap.startMicros && loss.offsetMicros <= gap.endMicros);
      }
    }
  }
}
