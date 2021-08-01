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
    };
