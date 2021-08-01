// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'topic_subscription.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TopicSubscription _$TopicSubscriptionFromJson(Map<String, dynamic> json) {
  return TopicSubscription(
    json['topic'] as String,
    _$enumDecode(_$MqttQosEnumMap, json['qos']),
    color: json['color'] == null
        ? null
        : TopicColor.fromJson(json['color'] as Map<String, dynamic>),
  );
}

Map<String, dynamic> _$TopicSubscriptionToJson(TopicSubscription instance) =>
    <String, dynamic>{
      'topic': instance.topic,
      'qos': _$MqttQosEnumMap[instance.qos],
      'color': instance.color.toJson(),
    };

K _$enumDecode<K, V>(
  Map<K, V> enumValues,
  Object? source, {
  K? unknownValue,
}) {
  if (source == null) {
    throw ArgumentError(
      'A value must be provided. Supported values: '
      '${enumValues.values.join(', ')}',
    );
  }

  return enumValues.entries.singleWhere(
    (e) => e.value == source,
    orElse: () {
      if (unknownValue == null) {
        throw ArgumentError(
          '`$source` is not one of the supported values: '
          '${enumValues.values.join(', ')}',
        );
      }
      return MapEntry(unknownValue, enumValues.values.first);
    },
  ).key;
}

const _$MqttQosEnumMap = {
  MqttQos.atMostOnce: 'atMostOnce',
  MqttQos.atLeastOnce: 'atLeastOnce',
  MqttQos.exactlyOnce: 'exactlyOnce',
  MqttQos.reserved1: 'reserved1',
  MqttQos.failure: 'failure',
};
