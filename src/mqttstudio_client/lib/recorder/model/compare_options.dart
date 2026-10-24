import 'package:json_annotation/json_annotation.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';

// use 'dart run build_runner build' to run the code generator
part 'compare_options.g.dart';

// What to compare between two recordings (doc/recorder-design.md §9)
@JsonSerializable(explicitToJson: true)
class CompareOptions {
  // map topics of B onto topics of A, e.g. test/ → prod/
  List<TopicRemap> remaps;
  // same topics, count per topic within countTolerance percent
  bool counts;
  double countTolerance;
  // per topic, the payloads in order are equal
  bool payloads;
  // JSON paths left out of the payload comparison, e.g. $.ts
  List<String> ignorePaths;
  // absolute, for JSON numbers and number payloads
  double numberTolerance;
  // per topic, the median interval within timingTolerance percent
  bool timing;
  double timingTolerance;
  // optional ranges, null = the whole recording
  int? rangeAFromMicros;
  int? rangeAToMicros;
  int? rangeBFromMicros;
  int? rangeBToMicros;

  CompareOptions({
    List<TopicRemap>? remaps,
    this.counts = true,
    this.countTolerance = 0,
    this.payloads = true,
    List<String>? ignorePaths,
    this.numberTolerance = 0,
    this.timing = true,
    this.timingTolerance = 10,
    this.rangeAFromMicros,
    this.rangeAToMicros,
    this.rangeBFromMicros,
    this.rangeBToMicros,
  })  : remaps = remaps ?? [],
        ignorePaths = ignorePaths ?? [];

  factory CompareOptions.fromJson(Map<String, dynamic> json) => _$CompareOptionsFromJson(json);
  Map<String, dynamic> toJson() => _$CompareOptionsToJson(this);
}

enum TopicCompareStatus { equal, different, onlyInA, onlyInB }

// The first message of a topic whose payload differs
@JsonSerializable()
class PayloadDifference {
  // position among the messages of the topic, from 0
  int index;
  int offsetAMicros;
  int offsetBMicros;
  // text, or base64 for binary payloads; null when one recording has fewer messages
  String? payloadA;
  String? payloadB;
  // the JSON path that differs, null for non-JSON payloads
  String? path;

  PayloadDifference(this.index, this.offsetAMicros, this.offsetBMicros, this.payloadA, this.payloadB, this.path);

  factory PayloadDifference.fromJson(Map<String, dynamic> json) => _$PayloadDifferenceFromJson(json);
  Map<String, dynamic> toJson() => _$PayloadDifferenceToJson(this);
}

@JsonSerializable(explicitToJson: true)
class TopicComparison {
  // the topic of A, or the remapped topic of B
  String topic;
  TopicCompareStatus status;
  int countA;
  int countB;
  int? medianIntervalAMicros;
  int? medianIntervalBMicros;
  bool countDiffers;
  bool timingDiffers;
  bool payloadsDiffer;
  PayloadDifference? firstDifference;

  TopicComparison(this.topic,
      {this.status = TopicCompareStatus.equal,
      this.countA = 0,
      this.countB = 0,
      this.medianIntervalAMicros,
      this.medianIntervalBMicros,
      this.countDiffers = false,
      this.timingDiffers = false,
      this.payloadsDiffer = false,
      this.firstDifference});

  factory TopicComparison.fromJson(Map<String, dynamic> json) => _$TopicComparisonFromJson(json);
  Map<String, dynamic> toJson() => _$TopicComparisonToJson(this);
}

@JsonSerializable(explicitToJson: true)
class CompareResult {
  String recordingA;
  String recordingB;
  CompareOptions options;
  List<TopicComparison> topics;

  CompareResult(this.recordingA, this.recordingB, this.options, this.topics);

  bool get isEqual => topics.every((topic) => topic.status == TopicCompareStatus.equal);

  int countOf(TopicCompareStatus status) => topics.where((topic) => topic.status == status).length;

  factory CompareResult.fromJson(Map<String, dynamic> json) => _$CompareResultFromJson(json);
  Map<String, dynamic> toJson() => _$CompareResultToJson(this);
}
