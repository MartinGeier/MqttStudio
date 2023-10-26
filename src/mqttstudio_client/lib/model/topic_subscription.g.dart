// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'topic_subscription.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TopicSubscription _$TopicSubscriptionFromJson(Map<String, dynamic> json) =>
    TopicSubscription(
      json['topic'] as String,
      $enumDecode(_$MqttQosEnumMap, json['qos']),
      color: json['color'] == null
          ? null
          : TopicColor.fromJson(json['color'] as Map<String, dynamic>),
      paused: json['paused'] as bool? ?? false,
    );

Map<String, dynamic> _$TopicSubscriptionToJson(TopicSubscription instance) =>
    <String, dynamic>{
      'topic': instance.topic,
      'qos': _$MqttQosEnumMap[instance.qos]!,
      'color': instance.color.toJson(),
      'paused': instance.paused,
    };

const _$MqttQosEnumMap = {
  MqttQos.atMostOnce: 'atMostOnce',
  MqttQos.atLeastOnce: 'atLeastOnce',
  MqttQos.exactlyOnce: 'exactlyOnce',
  MqttQos.reserved1: 'reserved1',
  MqttQos.failure: 'failure',
};
