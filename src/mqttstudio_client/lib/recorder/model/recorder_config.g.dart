// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recorder_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FlightRecorderOptions _$FlightRecorderOptionsFromJson(
  Map<String, dynamic> json,
) => FlightRecorderOptions(
  windowSeconds: (json['windowSeconds'] as num?)?.toInt() ?? 600,
  maxMemoryBytes: (json['maxMemoryBytes'] as num?)?.toInt(),
  saveWhen: json['saveWhen'] == null
      ? null
      : MessageCondition.fromJson(json['saveWhen'] as Map<String, dynamic>),
  postRollSeconds: (json['postRollSeconds'] as num?)?.toInt() ?? 30,
  maxSaves: (json['maxSaves'] as num?)?.toInt(),
);

Map<String, dynamic> _$FlightRecorderOptionsToJson(
  FlightRecorderOptions instance,
) => <String, dynamic>{
  'windowSeconds': instance.windowSeconds,
  'maxMemoryBytes': instance.maxMemoryBytes,
  'saveWhen': instance.saveWhen?.toJson(),
  'postRollSeconds': instance.postRollSeconds,
  'maxSaves': instance.maxSaves,
};

RecorderConfig _$RecorderConfigFromJson(
  Map<String, dynamic> json,
) => RecorderConfig(
  name: json['name'] as String,
  filters: (json['filters'] as List<dynamic>)
      .map((e) => RecorderFilter.fromJson(e as Map<String, dynamic>))
      .toList(),
  mode:
      $enumDecodeNullable(_$RecorderModeEnumMap, json['mode']) ??
      RecorderMode.normal,
  startWhen: json['startWhen'] == null
      ? null
      : MessageCondition.fromJson(json['startWhen'] as Map<String, dynamic>),
  preRollSeconds: (json['preRollSeconds'] as num?)?.toInt() ?? 0,
  durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
  maxMessages: (json['maxMessages'] as num?)?.toInt(),
  maxBytes: (json['maxBytes'] as num?)?.toInt(),
  stopWhen: json['stopWhen'] == null
      ? null
      : MessageCondition.fromJson(json['stopWhen'] as Map<String, dynamic>),
  postRollSeconds: (json['postRollSeconds'] as num?)?.toInt() ?? 0,
  flight: json['flight'] == null
      ? null
      : FlightRecorderOptions.fromJson(json['flight'] as Map<String, dynamic>),
  maxPayloadBytes: (json['maxPayloadBytes'] as num?)?.toInt(),
  recordRetainedSnapshot: json['recordRetainedSnapshot'] as bool? ?? true,
);

Map<String, dynamic> _$RecorderConfigToJson(RecorderConfig instance) =>
    <String, dynamic>{
      'name': instance.name,
      'filters': instance.filters.map((e) => e.toJson()).toList(),
      'mode': _$RecorderModeEnumMap[instance.mode]!,
      'startWhen': instance.startWhen?.toJson(),
      'preRollSeconds': instance.preRollSeconds,
      'durationSeconds': instance.durationSeconds,
      'maxMessages': instance.maxMessages,
      'maxBytes': instance.maxBytes,
      'stopWhen': instance.stopWhen?.toJson(),
      'postRollSeconds': instance.postRollSeconds,
      'flight': instance.flight?.toJson(),
      'maxPayloadBytes': instance.maxPayloadBytes,
      'recordRetainedSnapshot': instance.recordRetainedSnapshot,
    };

const _$RecorderModeEnumMap = {
  RecorderMode.normal: 'normal',
  RecorderMode.flightRecorder: 'flightRecorder',
};
