// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'observed_topic.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ObservedTopic _$ObservedTopicFromJson(Map<String, dynamic> json) => ObservedTopic(
      source: $enumDecodeNullable(_$DiscoverySourceEnumMap, json['source']) ?? DiscoverySource.live,
      sourceName: json['sourceName'] as String?,
      from: DateTime.parse(json['from'] as String),
      to: DateTime.parse(json['to'] as String),
      messages: (json['messages'] as num?)?.toInt() ?? 0,
      instanceCount: (json['instanceCount'] as num?)?.toInt() ?? 0,
      instances: (json['instances'] as List<dynamic>?)?.map((e) => e as String).toList(),
      parameterValues: (json['parameterValues'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, (e as List<dynamic>).map((e) => e as String).toList()),
      ),
      firstSeen: json['firstSeen'] == null ? null : DateTime.parse(json['firstSeen'] as String),
      lastSeen: json['lastSeen'] == null ? null : DateTime.parse(json['lastSeen'] as String),
      qosCounts: (json['qosCounts'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(int.parse(k), (e as num).toInt()),
      ),
      retainedSnapshot: (json['retainedSnapshot'] as num?)?.toInt() ?? 0,
      retainedLive: (json['retainedLive'] as num?)?.toInt() ?? 0,
      interval: json['interval'] == null ? null : ObservedInterval.fromJson(json['interval'] as Map<String, dynamic>),
      sizeMin: (json['sizeMin'] as num?)?.toInt() ?? 0,
      sizeMax: (json['sizeMax'] as num?)?.toInt() ?? 0,
      sizeAverage: (json['sizeAverage'] as num?)?.toDouble() ?? 0,
      formats: (json['formats'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, (e as num).toInt()),
      ),
      numericMin: (json['numericMin'] as num?)?.toDouble(),
      numericMax: (json['numericMax'] as num?)?.toDouble(),
      schema: json['schema'] == null ? null : SchemaNode.fromJson(json['schema'] as Map<String, dynamic>),
      fieldPresence: (json['fieldPresence'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, (e as num).toDouble()),
      ),
      userPropertyKeys:
          (json['userPropertyKeys'] as Map<String, dynamic>?)?.map((k, e) => MapEntry(k, (e as num).toInt())),
      contentTypes: (json['contentTypes'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, (e as num).toInt()),
      ),
      lastPayload: json['lastPayload'] as String?,
      lastTopic: json['lastTopic'] as String?,
      lastPayloadAt: json['lastPayloadAt'] == null ? null : DateTime.parse(json['lastPayloadAt'] as String),
    );

Map<String, dynamic> _$ObservedTopicToJson(ObservedTopic instance) => <String, dynamic>{
      'source': _$DiscoverySourceEnumMap[instance.source]!,
      'sourceName': instance.sourceName,
      'from': instance.from.toIso8601String(),
      'to': instance.to.toIso8601String(),
      'messages': instance.messages,
      'instanceCount': instance.instanceCount,
      'instances': instance.instances,
      'parameterValues': instance.parameterValues,
      'firstSeen': instance.firstSeen?.toIso8601String(),
      'lastSeen': instance.lastSeen?.toIso8601String(),
      'qosCounts': instance.qosCounts.map((k, e) => MapEntry(k.toString(), e)),
      'retainedSnapshot': instance.retainedSnapshot,
      'retainedLive': instance.retainedLive,
      'interval': instance.interval.toJson(),
      'sizeMin': instance.sizeMin,
      'sizeMax': instance.sizeMax,
      'sizeAverage': instance.sizeAverage,
      'formats': instance.formats,
      'numericMin': instance.numericMin,
      'numericMax': instance.numericMax,
      'schema': instance.schema?.toJson(),
      'fieldPresence': instance.fieldPresence,
      'userPropertyKeys': instance.userPropertyKeys,
      'contentTypes': instance.contentTypes,
      'lastPayload': instance.lastPayload,
      'lastTopic': instance.lastTopic,
      'lastPayloadAt': instance.lastPayloadAt?.toIso8601String(),
    };

const _$DiscoverySourceEnumMap = {
  DiscoverySource.live: 'live',
  DiscoverySource.recording: 'recording',
  DiscoverySource.buffer: 'buffer',
};

ObservedInterval _$ObservedIntervalFromJson(Map<String, dynamic> json) => ObservedInterval(
      kind: $enumDecodeNullable(_$IntervalKindEnumMap, json['kind']) ?? IntervalKind.unknown,
      medianMs: (json['medianMs'] as num?)?.toInt(),
      p10Ms: (json['p10Ms'] as num?)?.toInt(),
      p90Ms: (json['p90Ms'] as num?)?.toInt(),
      minMs: (json['minMs'] as num?)?.toInt(),
      maxMs: (json['maxMs'] as num?)?.toInt(),
      rate: (json['rate'] as num?)?.toDouble() ?? 0,
    );

Map<String, dynamic> _$ObservedIntervalToJson(ObservedInterval instance) => <String, dynamic>{
      'kind': _$IntervalKindEnumMap[instance.kind]!,
      'medianMs': instance.medianMs,
      'p10Ms': instance.p10Ms,
      'p90Ms': instance.p90Ms,
      'minMs': instance.minMs,
      'maxMs': instance.maxMs,
      'rate': instance.rate,
    };

const _$IntervalKindEnumMap = {
  IntervalKind.unknown: 'unknown',
  IntervalKind.periodic: 'periodic',
  IntervalKind.event: 'event',
  IntervalKind.onChange: 'onChange',
  IntervalKind.periodicAndOnChange: 'periodicAndOnChange',
};

DiscoverySettings _$DiscoverySettingsFromJson(Map<String, dynamic> json) => DiscoverySettings(
      filters:
          (json['filters'] as List<dynamic>?)?.map((e) => RecorderFilter.fromJson(e as Map<String, dynamic>)).toList(),
      stop: $enumDecodeNullable(_$DiscoveryStopEnumMap, json['stop']) ?? DiscoveryStop.duration,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? DiscoverySettings.defaultDurationSeconds,
      maxMessages: (json['maxMessages'] as num?)?.toInt() ?? 100000,
      detectTemplates: json['detectTemplates'] as bool? ?? true,
      inferSchemas: json['inferSchemas'] as bool? ?? true,
      keepExamples: json['keepExamples'] as bool? ?? true,
      ignoreSys: json['ignoreSys'] as bool? ?? true,
    );

Map<String, dynamic> _$DiscoverySettingsToJson(DiscoverySettings instance) => <String, dynamic>{
      'filters': instance.filters.map((e) => e.toJson()).toList(),
      'stop': _$DiscoveryStopEnumMap[instance.stop]!,
      'durationSeconds': instance.durationSeconds,
      'maxMessages': instance.maxMessages,
      'detectTemplates': instance.detectTemplates,
      'inferSchemas': instance.inferSchemas,
      'keepExamples': instance.keepExamples,
      'ignoreSys': instance.ignoreSys,
    };

const _$DiscoveryStopEnumMap = {
  DiscoveryStop.duration: 'duration',
  DiscoveryStop.messages: 'messages',
  DiscoveryStop.manual: 'manual',
};
