// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playback_options.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TopicRemap _$TopicRemapFromJson(Map<String, dynamic> json) =>
    TopicRemap(json['from'] as String, json['to'] as String);

Map<String, dynamic> _$TopicRemapToJson(TopicRemap instance) =>
    <String, dynamic>{'from': instance.from, 'to': instance.to};

PlaybackOptions _$PlaybackOptionsFromJson(
  Map<String, dynamic> json,
) => PlaybackOptions(
  topics: (json['topics'] as List<dynamic>?)?.map((e) => e as String).toList(),
  speed: (json['speed'] as num?)?.toDouble() ?? 1,
  loop: json['loop'] as bool? ?? false,
  rangeStartMicros: (json['rangeStartMicros'] as num?)?.toInt(),
  rangeEndMicros: (json['rangeEndMicros'] as num?)?.toInt(),
  compressGapsOverMicros: (json['compressGapsOverMicros'] as num?)?.toInt(),
  remaps: (json['remaps'] as List<dynamic>?)
      ?.map((e) => TopicRemap.fromJson(e as Map<String, dynamic>))
      .toList(),
  snapshot:
      $enumDecodeNullable(_$RetainedSnapshotModeEnumMap, json['snapshot']) ??
      RetainedSnapshotMode.publish,
  retain:
      $enumDecodeNullable(_$RetainOverrideEnumMap, json['retain']) ??
      RetainOverride.asRecorded,
  qos: $enumDecodeNullable(_$MqttQosEnumMap, json['qos']),
  republishProperties: json['republishProperties'] as bool? ?? true,
);

Map<String, dynamic> _$PlaybackOptionsToJson(PlaybackOptions instance) =>
    <String, dynamic>{
      'topics': instance.topics,
      'speed': instance.speed,
      'loop': instance.loop,
      'rangeStartMicros': instance.rangeStartMicros,
      'rangeEndMicros': instance.rangeEndMicros,
      'compressGapsOverMicros': instance.compressGapsOverMicros,
      'remaps': instance.remaps.map((e) => e.toJson()).toList(),
      'snapshot': _$RetainedSnapshotModeEnumMap[instance.snapshot]!,
      'retain': _$RetainOverrideEnumMap[instance.retain]!,
      'qos': _$MqttQosEnumMap[instance.qos],
      'republishProperties': instance.republishProperties,
    };

const _$RetainedSnapshotModeEnumMap = {
  RetainedSnapshotMode.publish: 'publish',
  RetainedSnapshotMode.skip: 'skip',
};

const _$RetainOverrideEnumMap = {
  RetainOverride.asRecorded: 'asRecorded',
  RetainOverride.never: 'never',
  RetainOverride.always: 'always',
};

const _$MqttQosEnumMap = {
  MqttQos.atMostOnce: 'atMostOnce',
  MqttQos.atLeastOnce: 'atLeastOnce',
  MqttQos.exactlyOnce: 'exactlyOnce',
  MqttQos.reserved1: 'reserved1',
  MqttQos.failure: 'failure',
};
