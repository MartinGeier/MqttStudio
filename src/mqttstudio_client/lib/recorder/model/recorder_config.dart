import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';

// use 'dart run build_runner build' to run the code generator
part 'recorder_config.g.dart';

// What and how long to record, as set in the record dialog (doc/recorder-design.md §5.4)
@JsonSerializable(explicitToJson: true)
class RecorderConfig {
  static const int megabyte = 1024 * 1024;
  // R17: a recording stops at 1 GB, in the browser at 100 MB
  static int get defaultMaxBytes => kIsWeb ? 100 * megabyte : 1024 * megabyte;

  String name;
  List<RecorderFilter> filters;
  // stop conditions, null = no limit; the first one reached stops the recording
  int? durationSeconds;
  int? maxMessages;
  int maxBytes;
  // longer payloads are stored cut and flagged, null = unlimited
  int? maxPayloadBytes;
  bool recordRetainedSnapshot;

  RecorderConfig({
    required this.name,
    required this.filters,
    this.durationSeconds,
    this.maxMessages,
    int? maxBytes,
    this.maxPayloadBytes,
    this.recordRetainedSnapshot = true,
  }) : maxBytes = maxBytes ?? defaultMaxBytes;

  Iterable<RecorderFilter> get includes => filters.where((filter) => !filter.exclude);

  Iterable<RecorderFilter> get excludes => filters.where((filter) => filter.exclude);

  factory RecorderConfig.fromJson(Map<String, dynamic> json) => _$RecorderConfigFromJson(json);
  Map<String, dynamic> toJson() => _$RecorderConfigToJson(this);
}
