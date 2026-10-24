// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'topic_spec.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TopicSpec _$TopicSpecFromJson(Map<String, dynamic> json) => TopicSpec(
      payload: json['payload'] == null ? null : PayloadSpec.fromJson(json['payload'] as Map<String, dynamic>),
      qos: $enumDecodeNullable(_$MqttQosEnumMap, json['qos']),
      retain: $enumDecodeNullable(_$RetainModeEnumMap, json['retain']) ?? RetainMode.unknown,
      interval: json['interval'] == null ? null : IntervalSpec.fromJson(json['interval'] as Map<String, dynamic>),
      mqtt5: json['mqtt5'] == null ? null : Mqtt5Spec.fromJson(json['mqtt5'] as Map<String, dynamic>),
      producers: (json['producers'] as List<dynamic>?)?.map((e) => e as String).toList(),
      consumers: (json['consumers'] as List<dynamic>?)?.map((e) => e as String).toList(),
      accessNotes: json['accessNotes'] as String? ?? '',
      sensitivity: $enumDecodeNullable(_$SensitivityEnumMap, json['sensitivity']) ?? Sensitivity.none,
      lastWill: json['lastWill'] as bool? ?? false,
    );

Map<String, dynamic> _$TopicSpecToJson(TopicSpec instance) => <String, dynamic>{
      'payload': instance.payload.toJson(),
      'qos': _$MqttQosEnumMap[instance.qos],
      'retain': _$RetainModeEnumMap[instance.retain]!,
      'interval': instance.interval.toJson(),
      'mqtt5': instance.mqtt5.toJson(),
      'producers': instance.producers,
      'consumers': instance.consumers,
      'accessNotes': instance.accessNotes,
      'sensitivity': _$SensitivityEnumMap[instance.sensitivity]!,
      'lastWill': instance.lastWill,
    };

const _$MqttQosEnumMap = {
  MqttQos.atMostOnce: 'atMostOnce',
  MqttQos.atLeastOnce: 'atLeastOnce',
  MqttQos.exactlyOnce: 'exactlyOnce',
  MqttQos.reserved1: 'reserved1',
  MqttQos.failure: 'failure',
};

const _$RetainModeEnumMap = {
  RetainMode.unknown: 'unknown',
  RetainMode.never: 'never',
  RetainMode.always: 'always',
  RetainMode.mixed: 'mixed',
};

const _$SensitivityEnumMap = {
  Sensitivity.none: 'none',
  Sensitivity.personal: 'personal',
  Sensitivity.confidential: 'confidential',
  Sensitivity.safety: 'safety',
};

PayloadSpec _$PayloadSpecFromJson(Map<String, dynamic> json) => PayloadSpec(
      format: $enumDecodeNullable(_$PayloadFormatEnumMap, json['format']) ?? PayloadFormat.unknown,
      unit: json['unit'] as String?,
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
      allowedValues: (json['allowedValues'] as List<dynamic>?)?.map((e) => e as String).toList(),
      encoding: json['encoding'] as String?,
      schema: json['schema'] == null ? null : SchemaNode.fromJson(json['schema'] as Map<String, dynamic>),
      examples:
          (json['examples'] as List<dynamic>?)?.map((e) => DocExample.fromJson(e as Map<String, dynamic>)).toList(),
    );

Map<String, dynamic> _$PayloadSpecToJson(PayloadSpec instance) => <String, dynamic>{
      'format': _$PayloadFormatEnumMap[instance.format]!,
      'unit': instance.unit,
      'min': instance.min,
      'max': instance.max,
      'allowedValues': instance.allowedValues,
      'encoding': instance.encoding,
      'schema': instance.schema?.toJson(),
      'examples': instance.examples.map((e) => e.toJson()).toList(),
    };

const _$PayloadFormatEnumMap = {
  PayloadFormat.unknown: 'unknown',
  PayloadFormat.json: 'json',
  PayloadFormat.number: 'number',
  PayloadFormat.boolean: 'boolean',
  PayloadFormat.string: 'string',
  PayloadFormat.binary: 'binary',
  PayloadFormat.image: 'image',
  PayloadFormat.gnss: 'gnss',
  PayloadFormat.empty: 'empty',
};

SchemaNode _$SchemaNodeFromJson(Map<String, dynamic> json) => SchemaNode(
      type: $enumDecodeNullable(_$SchemaTypeEnumMap, json['type']) ?? SchemaType.object,
      description: json['description'] as String? ?? '',
      unit: json['unit'] as String?,
      format: json['format'] as String?,
      minimum: (json['minimum'] as num?)?.toDouble(),
      maximum: (json['maximum'] as num?)?.toDouble(),
      enumValues: (json['enumValues'] as List<dynamic>?)?.map((e) => e as String).toList(),
      properties: (json['properties'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, SchemaNode.fromJson(e as Map<String, dynamic>)),
      ),
      required: (json['required'] as List<dynamic>?)?.map((e) => e as String).toSet(),
      items: json['items'] == null ? null : SchemaNode.fromJson(json['items'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$SchemaNodeToJson(SchemaNode instance) => <String, dynamic>{
      'type': _$SchemaTypeEnumMap[instance.type]!,
      'description': instance.description,
      'unit': instance.unit,
      'format': instance.format,
      'minimum': instance.minimum,
      'maximum': instance.maximum,
      'enumValues': instance.enumValues,
      'properties': instance.properties.map((k, e) => MapEntry(k, e.toJson())),
      'required': instance.required.toList(),
      'items': instance.items?.toJson(),
    };

const _$SchemaTypeEnumMap = {
  SchemaType.object: 'object',
  SchemaType.array: 'array',
  SchemaType.string: 'string',
  SchemaType.number: 'number',
  SchemaType.integer: 'integer',
  SchemaType.boolean: 'boolean',
  SchemaType.nullValue: 'nullValue',
  SchemaType.mixed: 'mixed',
};

IntervalSpec _$IntervalSpecFromJson(Map<String, dynamic> json) => IntervalSpec(
      kind: $enumDecodeNullable(_$IntervalKindEnumMap, json['kind']) ?? IntervalKind.unknown,
      nominalMs: (json['nominalMs'] as num?)?.toInt(),
      staleAfterMs: (json['staleAfterMs'] as num?)?.toInt(),
    );

Map<String, dynamic> _$IntervalSpecToJson(IntervalSpec instance) => <String, dynamic>{
      'kind': _$IntervalKindEnumMap[instance.kind]!,
      'nominalMs': instance.nominalMs,
      'staleAfterMs': instance.staleAfterMs,
    };

const _$IntervalKindEnumMap = {
  IntervalKind.unknown: 'unknown',
  IntervalKind.periodic: 'periodic',
  IntervalKind.event: 'event',
  IntervalKind.onChange: 'onChange',
  IntervalKind.periodicAndOnChange: 'periodicAndOnChange',
};

Mqtt5Spec _$Mqtt5SpecFromJson(Map<String, dynamic> json) => Mqtt5Spec(
      contentType: json['contentType'] as String?,
      utf8Payload: json['utf8Payload'] as bool?,
      messageExpirySeconds: (json['messageExpirySeconds'] as num?)?.toInt(),
      responseTopic: json['responseTopic'] as String?,
      correlationData: json['correlationData'] as String?,
      userProperties: (json['userProperties'] as List<dynamic>?)
          ?.map((e) => DocUserProperty.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$Mqtt5SpecToJson(Mqtt5Spec instance) => <String, dynamic>{
      'contentType': instance.contentType,
      'utf8Payload': instance.utf8Payload,
      'messageExpirySeconds': instance.messageExpirySeconds,
      'responseTopic': instance.responseTopic,
      'correlationData': instance.correlationData,
      'userProperties': instance.userProperties.map((e) => e.toJson()).toList(),
    };

DocUserProperty _$DocUserPropertyFromJson(Map<String, dynamic> json) => DocUserProperty(
      key: json['key'] as String? ?? '',
      description: json['description'] as String? ?? '',
      example: json['example'] as String? ?? '',
    );

Map<String, dynamic> _$DocUserPropertyToJson(DocUserProperty instance) => <String, dynamic>{
      'key': instance.key,
      'description': instance.description,
      'example': instance.example,
    };

DocExample _$DocExampleFromJson(Map<String, dynamic> json) => DocExample(
      payload: json['payload'] as String? ?? '',
      topic: json['topic'] as String?,
      capturedAt: json['capturedAt'] == null ? null : DateTime.parse(json['capturedAt'] as String),
      note: json['note'] as String? ?? '',
    );

Map<String, dynamic> _$DocExampleToJson(DocExample instance) => <String, dynamic>{
      'payload': instance.payload,
      'topic': instance.topic,
      'capturedAt': instance.capturedAt?.toIso8601String(),
      'note': instance.note,
    };
