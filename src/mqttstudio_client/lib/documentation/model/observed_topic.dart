import 'package:json_annotation/json_annotation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';

// use 'dart run build_runner build' to run the code generator
part 'observed_topic.g.dart';

enum DiscoverySource { live, recording, buffer }

enum DiscoveryStop { duration, messages, manual }

// What the last discovery saw of a documented topic or template (doc/documentation-design.md §4.2). Discovery
// replaces it every time; the user never edits it (T5).
@JsonSerializable(explicitToJson: true)
class ObservedTopic {
  static const int maxInstances = 200;
  static const int maxParameterValues = 20;
  static const int maxPayloadLength = 4096;

  DiscoverySource source;
  // the recording's name for a recording
  String? sourceName;
  DateTime from;
  DateTime to;
  int messages;
  int instanceCount;
  // the first concrete topics seen, at most maxInstances
  List<String> instances;
  // values of each parameter, at most maxParameterValues each
  Map<String, List<String>> parameterValues;
  DateTime? firstSeen;
  DateTime? lastSeen;
  // delivered QoS (0, 1, 2) and how often
  Map<int, int> qosCounts;
  // retained messages the broker sent on subscribe
  int retainedSnapshot;
  // live messages with the retain flag, only known with MQTT 5 Retain As Published (T10)
  int retainedLive;
  ObservedInterval interval;
  int sizeMin;
  int sizeMax;
  double sizeAverage;
  // PayloadFormat name and how often
  Map<String, int> formats;
  double? numericMin;
  double? numericMax;
  // JSON payloads; its minimum and maximum are the observed ranges
  SchemaNode? schema;
  // field path and the share of JSON messages that had it, 0..1
  Map<String, double> fieldPresence;
  Map<String, int> userPropertyKeys;
  Map<String, int> contentTypes;
  // the last payload as text, cut to maxPayloadLength
  String? lastPayload;
  String? lastTopic;
  DateTime? lastPayloadAt;

  ObservedTopic(
      {this.source = DiscoverySource.live,
      this.sourceName,
      required this.from,
      required this.to,
      this.messages = 0,
      this.instanceCount = 0,
      List<String>? instances,
      Map<String, List<String>>? parameterValues,
      this.firstSeen,
      this.lastSeen,
      Map<int, int>? qosCounts,
      this.retainedSnapshot = 0,
      this.retainedLive = 0,
      ObservedInterval? interval,
      this.sizeMin = 0,
      this.sizeMax = 0,
      this.sizeAverage = 0,
      Map<String, int>? formats,
      this.numericMin,
      this.numericMax,
      this.schema,
      Map<String, double>? fieldPresence,
      Map<String, int>? userPropertyKeys,
      Map<String, int>? contentTypes,
      this.lastPayload,
      this.lastTopic,
      this.lastPayloadAt})
      : instances = instances ?? [],
        parameterValues = parameterValues ?? {},
        qosCounts = qosCounts ?? {},
        interval = interval ?? ObservedInterval(),
        formats = formats ?? {},
        fieldPresence = fieldPresence ?? {},
        userPropertyKeys = userPropertyKeys ?? {},
        contentTypes = contentTypes ?? {};

  // the format most messages had
  PayloadFormat get mainFormat {
    String? best;
    for (var entry in formats.entries) {
      if (best == null || entry.value > formats[best]!) {
        best = entry.key;
      }
    }
    return PayloadFormat.values.where((format) => format.name == best).firstOrNull ?? PayloadFormat.unknown;
  }

  // the QoS most messages were delivered with
  int? get mainQos {
    int? best;
    for (var entry in qosCounts.entries) {
      if (best == null || entry.value > qosCounts[best]!) {
        best = entry.key;
      }
    }
    return best;
  }

  factory ObservedTopic.fromJson(Map<String, dynamic> json) => _$ObservedTopicFromJson(json);
  Map<String, dynamic> toJson() => _$ObservedTopicToJson(this);
}

// Inter-arrival times per concrete topic, merged over the instances of a template
@JsonSerializable()
class ObservedInterval {
  IntervalKind kind;
  int? medianMs;
  int? p10Ms;
  int? p90Ms;
  int? minMs;
  int? maxMs;
  // messages per second of all instances together
  double rate;

  ObservedInterval(
      {this.kind = IntervalKind.unknown, this.medianMs, this.p10Ms, this.p90Ms, this.minMs, this.maxMs, this.rate = 0});

  factory ObservedInterval.fromJson(Map<String, dynamic> json) => _$ObservedIntervalFromJson(json);
  Map<String, dynamic> toJson() => _$ObservedIntervalToJson(this);
}

// What a discovery listens to and when it stops (§5.1), remembered for the next one
@JsonSerializable(explicitToJson: true)
class DiscoverySettings {
  static const int defaultDurationSeconds = 300;

  List<RecorderFilter> filters;
  DiscoveryStop stop;
  int durationSeconds;
  int maxMessages;
  bool detectTemplates;
  bool inferSchemas;
  bool keepExamples;
  bool ignoreSys;

  DiscoverySettings(
      {List<RecorderFilter>? filters,
      this.stop = DiscoveryStop.duration,
      this.durationSeconds = DiscoverySettings.defaultDurationSeconds,
      this.maxMessages = 100000,
      this.detectTemplates = true,
      this.inferSchemas = true,
      this.keepExamples = true,
      this.ignoreSys = true})
      : filters = filters ?? [RecorderFilter('#')];

  DiscoverySettings copy() => DiscoverySettings.fromJson(toJson());

  factory DiscoverySettings.fromJson(Map<String, dynamic> json) => _$DiscoverySettingsFromJson(json);
  Map<String, dynamic> toJson() => _$DiscoverySettingsToJson(this);
}
