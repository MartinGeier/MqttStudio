// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Project _$ProjectFromJson(Map<String, dynamic> json) {
  return Project(
    MqttSettings.fromJson(json['mqttSettings'] as Map<String, dynamic>),
    name: json['name'] as String,
  )
    ..id = json['id'] as String?
    ..createdOn = parseDateTime(json['createdOn'] as String?)
    ..lastModifiedOn = parseDateTime(json['lastModifiedOn'] as String?)
    ..createdBy = json['createdBy'] as String?
    ..lastModifiedBy = json['lastModifiedBy'] as String?
    ..topicSubscriptions = (json['topicSubscriptions'] as List<dynamic>)
        .map((e) => TopicSubscription.fromJson(e as Map<String, dynamic>))
        .toList()
    ..topicColors = (json['topicColors'] as Map<String, dynamic>).map(
      (k, e) => MapEntry(k, TopicColor.fromJson(e as Map<String, dynamic>)),
    )
    ..recentTopics = (json['recentTopics'] as List<dynamic>)
        .map((e) => e as String)
        .toList();
}

Map<String, dynamic> _$ProjectToJson(Project instance) => <String, dynamic>{
      'id': instance.id,
      'createdOn': instance.createdOn?.toIso8601String(),
      'lastModifiedOn': instance.lastModifiedOn?.toIso8601String(),
      'createdBy': instance.createdBy,
      'lastModifiedBy': instance.lastModifiedBy,
      'name': instance.name,
      'mqttSettings': instance.mqttSettings.toJson(),
      'topicSubscriptions':
          instance.topicSubscriptions.map((e) => e.toJson()).toList(),
      'topicColors':
          instance.topicColors.map((k, e) => MapEntry(k, e.toJson())),
      'recentTopics': instance.recentTopics,
    };
