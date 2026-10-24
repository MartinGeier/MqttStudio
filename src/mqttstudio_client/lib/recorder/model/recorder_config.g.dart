// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recorder_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RecorderConfig _$RecorderConfigFromJson(Map<String, dynamic> json) =>
    RecorderConfig(
      name: json['name'] as String,
      filters: (json['filters'] as List<dynamic>)
          .map((e) => RecorderFilter.fromJson(e as Map<String, dynamic>))
          .toList(),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      maxMessages: (json['maxMessages'] as num?)?.toInt(),
      maxBytes: (json['maxBytes'] as num?)?.toInt(),
      maxPayloadBytes: (json['maxPayloadBytes'] as num?)?.toInt(),
      recordRetainedSnapshot: json['recordRetainedSnapshot'] as bool? ?? true,
    );

Map<String, dynamic> _$RecorderConfigToJson(RecorderConfig instance) =>
    <String, dynamic>{
      'name': instance.name,
      'filters': instance.filters.map((e) => e.toJson()).toList(),
      'durationSeconds': instance.durationSeconds,
      'maxMessages': instance.maxMessages,
      'maxBytes': instance.maxBytes,
      'maxPayloadBytes': instance.maxPayloadBytes,
      'recordRetainedSnapshot': instance.recordRetainedSnapshot,
    };
