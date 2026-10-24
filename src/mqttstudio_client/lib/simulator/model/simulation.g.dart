// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'simulation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Simulation _$SimulationFromJson(Map<String, dynamic> json) => Simulation(
  schemaVersion:
      (json['schemaVersion'] as num?)?.toInt() ??
      Simulation.currentSchemaVersion,
  devices: (json['devices'] as List<dynamic>?)
      ?.map((e) => SimulatedDevice.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$SimulationToJson(Simulation instance) =>
    <String, dynamic>{
      'schemaVersion': instance.schemaVersion,
      'devices': instance.devices.map((e) => e.toJson()).toList(),
    };

SimulatedDevice _$SimulatedDeviceFromJson(Map<String, dynamic> json) =>
    SimulatedDevice(
      id: json['id'] as String?,
      name: json['name'] as String,
      instanceCount: (json['instanceCount'] as num?)?.toInt() ?? 1,
      firstInstance: (json['firstInstance'] as num?)?.toInt() ?? 1,
      topics: (json['topics'] as List<dynamic>?)
          ?.map((e) => SimulatedTopic.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$SimulatedDeviceToJson(SimulatedDevice instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'instanceCount': instance.instanceCount,
      'firstInstance': instance.firstInstance,
      'topics': instance.topics.map((e) => e.toJson()).toList(),
    };

SimulatedTopic _$SimulatedTopicFromJson(
  Map<String, dynamic> json,
) => SimulatedTopic(
  id: json['id'] as String?,
  topic: json['topic'] as String,
  generator: PayloadGenerator.fromJson(
    json['generator'] as Map<String, dynamic>,
  ),
  qos: $enumDecodeNullable(_$MqttQosEnumMap, json['qos']) ?? MqttQos.atMostOnce,
  retain: json['retain'] as bool? ?? false,
  interval: json['interval'] == null
      ? null
      : PublishInterval.fromJson(json['interval'] as Map<String, dynamic>),
  mqtt5: json['mqtt5'] == null
      ? null
      : Mqtt5PublishProperties.fromJson(json['mqtt5'] as Map<String, dynamic>),
);

Map<String, dynamic> _$SimulatedTopicToJson(SimulatedTopic instance) =>
    <String, dynamic>{
      'id': instance.id,
      'topic': instance.topic,
      'qos': _$MqttQosEnumMap[instance.qos]!,
      'retain': instance.retain,
      'interval': instance.interval.toJson(),
      'mqtt5': instance.mqtt5.toJson(),
      'generator': PayloadGenerator.toJsonStatic(instance.generator),
    };

const _$MqttQosEnumMap = {
  MqttQos.atMostOnce: 'atMostOnce',
  MqttQos.atLeastOnce: 'atLeastOnce',
  MqttQos.exactlyOnce: 'exactlyOnce',
  MqttQos.reserved1: 'reserved1',
  MqttQos.failure: 'failure',
};

PublishInterval _$PublishIntervalFromJson(Map<String, dynamic> json) =>
    PublishInterval(
      minMs: (json['minMs'] as num?)?.toInt() ?? 1000,
      maxMs: (json['maxMs'] as num?)?.toInt(),
    );

Map<String, dynamic> _$PublishIntervalToJson(PublishInterval instance) =>
    <String, dynamic>{'minMs': instance.minMs, 'maxMs': instance.maxMs};

SimulatedUserProperty _$SimulatedUserPropertyFromJson(
  Map<String, dynamic> json,
) => SimulatedUserProperty(json['key'] as String, json['value'] as String);

Map<String, dynamic> _$SimulatedUserPropertyToJson(
  SimulatedUserProperty instance,
) => <String, dynamic>{'key': instance.key, 'value': instance.value};

Mqtt5PublishProperties _$Mqtt5PublishPropertiesFromJson(
  Map<String, dynamic> json,
) => Mqtt5PublishProperties(
  contentType: json['contentType'] as String?,
  messageExpirySeconds: (json['messageExpirySeconds'] as num?)?.toInt(),
  userProperties: (json['userProperties'] as List<dynamic>?)
      ?.map((e) => SimulatedUserProperty.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$Mqtt5PublishPropertiesToJson(
  Mqtt5PublishProperties instance,
) => <String, dynamic>{
  'contentType': instance.contentType,
  'messageExpirySeconds': instance.messageExpirySeconds,
  'userProperties': instance.userProperties.map((e) => e.toJson()).toList(),
};
