import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:mqttstudio/recorder/model/message_condition.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';

// use 'dart run build_runner build' to run the code generator
part 'recorder_config.g.dart';

enum RecorderMode { normal, flightRecorder }

// The flight recorder keeps the last minutes in memory and saves them on request or on a condition (§5.5)
@JsonSerializable(explicitToJson: true)
class FlightRecorderOptions {
  // R17: the flight recorder holds at most 200 MB, in the browser 50 MB
  static int get defaultMaxMemoryBytes => (kIsWeb ? 50 : 200) * RecorderConfig.megabyte;

  int windowSeconds;
  int maxMemoryBytes;
  // null = only the SAVE button
  MessageCondition? saveWhen;
  // keeps capturing this long after SAVE or saveWhen before writing
  int postRollSeconds;
  // null = unlimited
  int? maxSaves;

  FlightRecorderOptions({
    this.windowSeconds = 600,
    int? maxMemoryBytes,
    this.saveWhen,
    this.postRollSeconds = 30,
    this.maxSaves,
  }) : maxMemoryBytes = maxMemoryBytes ?? defaultMaxMemoryBytes;

  factory FlightRecorderOptions.fromJson(Map<String, dynamic> json) => _$FlightRecorderOptionsFromJson(json);
  Map<String, dynamic> toJson() => _$FlightRecorderOptionsToJson(this);
}

// What and how long to record, as set in the record dialog (doc/recorder-design.md §5.4)
@JsonSerializable(explicitToJson: true)
class RecorderConfig {
  static const int megabyte = 1024 * 1024;
  static const int maxPreRollSeconds = 600;
  // R17: a recording stops at 1 GB, in the browser at 100 MB
  static int get defaultMaxBytes => kIsWeb ? 100 * megabyte : 1024 * megabyte;

  String name;
  List<RecorderFilter> filters;
  @JsonKey(defaultValue: RecorderMode.normal)
  RecorderMode mode;
  // null = start right away; else wait and keep preRollSeconds of messages from before it matched
  MessageCondition? startWhen;
  @JsonKey(defaultValue: 0)
  int preRollSeconds;
  // stop conditions, null = no limit; the first one reached stops the recording. The duration counts from the start
  // trigger.
  int? durationSeconds;
  int? maxMessages;
  int maxBytes;
  MessageCondition? stopWhen;
  // keeps recording this long after stopWhen matched
  @JsonKey(defaultValue: 0)
  int postRollSeconds;
  FlightRecorderOptions? flight;
  // longer payloads are stored cut and flagged, null = unlimited
  int? maxPayloadBytes;
  bool recordRetainedSnapshot;

  RecorderConfig({
    required this.name,
    required this.filters,
    this.mode = RecorderMode.normal,
    this.startWhen,
    this.preRollSeconds = 0,
    this.durationSeconds,
    this.maxMessages,
    int? maxBytes,
    this.stopWhen,
    this.postRollSeconds = 0,
    this.flight,
    this.maxPayloadBytes,
    this.recordRetainedSnapshot = true,
  }) : maxBytes = maxBytes ?? defaultMaxBytes;

  bool get isFlightRecorder => mode == RecorderMode.flightRecorder;

  FlightRecorderOptions get flightOptions => flight ?? FlightRecorderOptions();

  Iterable<RecorderFilter> get includes => filters.where((filter) => !filter.exclude);

  Iterable<RecorderFilter> get excludes => filters.where((filter) => filter.exclude);

  factory RecorderConfig.fromJson(Map<String, dynamic> json) => _$RecorderConfigFromJson(json);
  Map<String, dynamic> toJson() => _$RecorderConfigToJson(this);
}
