import 'dart:math';
import 'package:json_annotation/json_annotation.dart';

// use 'dart run build_runner build' to run the code generator
part 'recording_summary.g.dart';

// Time between two messages of a topic in 32 buckets on a log scale from 1 ms to about 10 hours
class IntervalHistogram {
  static const int bucketCount = 32;
  static const double _maxMs = 36000000;
  static final double _ratio = pow(_maxMs, 1 / bucketCount).toDouble();

  static int bucketOf(int intervalMicros) {
    var ms = intervalMicros / 1000;
    if (ms < 1) {
      return 0;
    }
    return min(bucketCount - 1, (log(ms) / log(_ratio)).floor());
  }

  static double lowerBoundMs(int bucket) => bucket == 0 ? 0 : pow(_ratio, bucket).toDouble();

  static double upperBoundMs(int bucket) => pow(_ratio, bucket + 1).toDouble();
}

// Statistics of one recorded topic, kept up to date while recording
@JsonSerializable()
class TopicSummary {
  int count = 0;
  int firstOffsetMicros = 0;
  int lastOffsetMicros = 0;
  int retainedCount = 0;
  int snapshotCount = 0;
  int truncatedCount = 0;
  // payload sizes as published, also for truncated payloads
  int payloadMin = 0;
  int payloadMax = 0;
  int payloadTotal = 0;
  // PayloadType names (Number, Json, Image, GnssCoordinates, Text) and Empty
  Map<String, int> kinds = {};
  int? intervalMinMicros;
  int? intervalMaxMicros;
  int intervalSumMicros = 0;
  List<int> histogram = List.filled(IntervalHistogram.bucketCount, 0);
  double? numericMin;
  double? numericMax;
  double numericSum = 0;
  int numericCount = 0;
  // messages with the same payload as the previous message of the topic
  int consecutiveDuplicates = 0;
  int peakRatePerSecond = 0;

  TopicSummary();

  int get intervalCount => count > 1 ? count - 1 : 0;

  Duration? get averageInterval => intervalCount == 0 ? null : Duration(microseconds: intervalSumMicros ~/ intervalCount);

  // approximate, the geometric middle of the bucket that holds the median
  Duration? get medianInterval {
    if (intervalCount == 0) {
      return null;
    }
    var middle = (intervalCount + 1) ~/ 2;
    var seen = 0;
    for (var bucket = 0; bucket < histogram.length; bucket++) {
      seen += histogram[bucket];
      if (seen >= middle) {
        var low = max(IntervalHistogram.lowerBoundMs(bucket), intervalMinMicros! / 1000);
        var high = min(IntervalHistogram.upperBoundMs(bucket), intervalMaxMicros! / 1000);
        var ms = low <= 0 ? high / 2 : sqrt(low * high);
        return Duration(microseconds: (ms * 1000).round());
      }
    }
    return null;
  }

  double get averagePayload => count == 0 ? 0 : payloadTotal / count;

  // the payload type most messages had
  String? get mainKind {
    String? best;
    var bestCount = 0;
    kinds.forEach((kind, count) {
      if (count > bestCount) {
        best = kind;
        bestCount = count;
      }
    });
    return best;
  }

  factory TopicSummary.fromJson(Map<String, dynamic> json) => _$TopicSummaryFromJson(json);
  Map<String, dynamic> toJson() => _$TopicSummaryToJson(this);
}

@JsonSerializable(explicitToJson: true)
class RecordingSummary {
  int messages = 0;
  int payloadBytes = 0;
  int peakRatePerSecond = 0;
  // number of markers per kind (connectionLost, reconnected, …)
  Map<String, int> markers = {};
  Map<String, TopicSummary> perTopic = {};

  RecordingSummary();

  factory RecordingSummary.fromJson(Map<String, dynamic> json) => _$RecordingSummaryFromJson(json);
  Map<String, dynamic> toJson() => _$RecordingSummaryToJson(this);
}
