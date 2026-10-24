import 'package:json_annotation/json_annotation.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/recorder/model/recording_summary.dart';

// use 'dart run build_runner build' to run the code generator
part 'recording_header.g.dart';

enum RecordingOrigin { live, flightRecorder, viewerBuffer, edit, import }

// A topic filter the recorder subscribes to, or excludes on the client because MQTT has no exclusions
@JsonSerializable(explicitToJson: true)
class RecorderFilter {
  String filter;
  bool exclude;
  // QoS 2 keeps the QoS the publisher used, the broker delivers min(publish QoS, subscription QoS)
  MqttQos qos;
  // color of the recorded topics under this filter, null for exclusions
  TopicColor? color;

  RecorderFilter(this.filter, {this.exclude = false, this.qos = MqttQos.exactlyOnce, this.color});

  RecorderFilter copy() => RecorderFilter(filter, exclude: exclude, qos: qos, color: color);

  factory RecorderFilter.fromJson(Map<String, dynamic> json) => _$RecorderFilterFromJson(json);
  Map<String, dynamic> toJson() => _$RecorderFilterToJson(this);
}

// Written once at the start of a recording, never changed afterwards
@JsonSerializable(explicitToJson: true)
class RecordingHeader {
  String id;
  // UTC. The wall time of a message is startedAt + its offset.
  DateTime startedAt;
  List<RecorderFilter> filters;
  // host:port or URL
  String broker;
  MqttProtocolVersion protocol;
  String clientId;
  // the project it was recorded from, null for imports
  String? projectName;
  String appVersion;
  RecordingOrigin origin;
  // for edits and merges: the recordings it was made from
  @JsonKey(defaultValue: <String>[])
  List<String> sourceRecordingIds;

  RecordingHeader({
    required this.id,
    required this.startedAt,
    required this.filters,
    required this.broker,
    required this.protocol,
    required this.clientId,
    this.projectName,
    required this.appVersion,
    this.origin = RecordingOrigin.live,
    List<String>? sourceRecordingIds,
  }) : sourceRecordingIds = sourceRecordingIds ?? [];

  factory RecordingHeader.fromJson(Map<String, dynamic> json) => _$RecordingHeaderFromJson(json);
  Map<String, dynamic> toJson() => _$RecordingHeaderToJson(this);
}

@JsonSerializable()
class Bookmark {
  int offsetMicros;
  String label;

  Bookmark(this.offsetMicros, this.label);

  Duration get offset => Duration(microseconds: offsetMicros);

  factory Bookmark.fromJson(Map<String, dynamic> json) => _$BookmarkFromJson(json);
  Map<String, dynamic> toJson() => _$BookmarkToJson(this);
}

// Where to start reading for a given offset: every 1000th message
@JsonSerializable()
class SeekEntry {
  int offsetMicros;
  // file position of the message record
  int position;
  // number of messages before it
  int index;

  SeekEntry(this.offsetMicros, this.position, this.index);

  factory SeekEntry.fromJson(Map<String, dynamic> json) => _$SeekEntryFromJson(json);
  Map<String, dynamic> toJson() => _$SeekEntryToJson(this);
}

// Written when a recording is finalized. Name, notes and bookmarks can be changed later by rewriting it.
@JsonSerializable(explicitToJson: true)
class RecordingFooter {
  String name;
  String notes;
  int durationMicros;
  bool recovered;
  List<Bookmark> bookmarks;
  // all recorded topics, the index of a topic in this list is its topic index in the file
  List<String> topics;
  RecordingSummary summary;
  List<SeekEntry> seekIndex;

  RecordingFooter({
    required this.name,
    this.notes = '',
    required this.durationMicros,
    this.recovered = false,
    List<Bookmark>? bookmarks,
    List<String>? topics,
    RecordingSummary? summary,
    List<SeekEntry>? seekIndex,
  })  : bookmarks = bookmarks ?? [],
        topics = topics ?? [],
        summary = summary ?? RecordingSummary(),
        seekIndex = seekIndex ?? [];

  Duration get duration => Duration(microseconds: durationMicros);

  factory RecordingFooter.fromJson(Map<String, dynamic> json) => _$RecordingFooterFromJson(json);
  Map<String, dynamic> toJson() => _$RecordingFooterToJson(this);
}
