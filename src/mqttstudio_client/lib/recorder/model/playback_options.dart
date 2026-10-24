import 'package:json_annotation/json_annotation.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;

// use 'dart run build_runner build' to run the code generator
part 'playback_options.g.dart';

enum RetainedSnapshotMode { publish, skip }

enum RetainOverride { asRecorded, never, always }

// Replaces the start of a recorded topic, e.g. prod/ -> test/
@JsonSerializable()
class TopicRemap {
  String from;
  String to;

  TopicRemap(this.from, this.to);

  factory TopicRemap.fromJson(Map<String, dynamic> json) => _$TopicRemapFromJson(json);
  Map<String, dynamic> toJson() => _$TopicRemapToJson(this);
}

// How to play a recording back (doc/recorder-design.md §6.2)
@JsonSerializable(explicitToJson: true)
class PlaybackOptions {
  static const List<double> speeds = [0.1, 0.25, 0.5, 1, 2, 5, 10, 100, maxSpeed];
  // as fast as the rate limit allows
  static const double maxSpeed = 0;

  // recorded topics to play, null = all, also topics recorded later
  List<String>? topics;
  double speed;
  bool loop;
  // offsets in the recording, null = its start or end
  int? rangeStartMicros;
  int? rangeEndMicros;
  // gaps longer than this are shortened to it, null = keep all gaps
  int? compressGapsOverMicros;
  // the first rule whose prefix matches is applied
  List<TopicRemap> remaps;
  RetainedSnapshotMode snapshot;
  RetainOverride retain;
  // null = as recorded
  MqttQos? qos;
  bool republishProperties;

  PlaybackOptions({
    this.topics,
    this.speed = 1,
    this.loop = false,
    this.rangeStartMicros,
    this.rangeEndMicros,
    this.compressGapsOverMicros,
    List<TopicRemap>? remaps,
    this.snapshot = RetainedSnapshotMode.publish,
    this.retain = RetainOverride.asRecorded,
    this.qos,
    this.republishProperties = true,
  }) : remaps = remaps ?? [];

  bool get isMaxSpeed => speed == maxSpeed;

  bool plays(String topic) => topics == null || topics!.contains(topic);

  String remap(String topic) {
    for (var rule in remaps) {
      if (rule.from.isNotEmpty && topic.startsWith(rule.from)) {
        return rule.to + topic.substring(rule.from.length);
      }
    }
    return topic;
  }

  PlaybackOptions copy() => PlaybackOptions.fromJson(toJson());

  factory PlaybackOptions.fromJson(Map<String, dynamic> json) => _$PlaybackOptionsFromJson(json);
  Map<String, dynamic> toJson() => _$PlaybackOptionsToJson(this);
}
