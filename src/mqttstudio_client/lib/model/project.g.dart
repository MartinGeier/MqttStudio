// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Project _$ProjectFromJson(Map<String, dynamic> json) =>
    Project(
        MqttSettings.fromJson(json['mqttSettings'] as Map<String, dynamic>),
        name: json['name'] as String? ?? 'New Project',
      )
      ..id = json['id'] as String?
      ..createdOn = dateTimeFromUtcJson(json['createdOn'] as String?)
      ..lastModifiedOn = dateTimeFromUtcJson(json['lastModifiedOn'] as String?)
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
          .toList()
      ..lastUsed = json['lastUsed'] == null
          ? null
          : DateTime.parse(json['lastUsed'] as String)
      ..simulation = Simulation.fromJsonOrEmpty(
        json['simulation'] as Map<String, dynamic>?,
      );

Map<String, dynamic> _$ProjectToJson(Project instance) => <String, dynamic>{
  'id': SrxBaseModel.setIdIfNull(instance.id),
  'createdOn': ?dateTimeToUtcJson(instance.createdOn),
  'lastModifiedOn': ?dateTimeToUtcJson(instance.lastModifiedOn),
  'createdBy': ?instance.createdBy,
  'lastModifiedBy': ?instance.lastModifiedBy,
  'name': instance.name,
  'mqttSettings': instance.mqttSettings.toJson(),
  'topicSubscriptions': instance.topicSubscriptions
      .map((e) => e.toJson())
      .toList(),
  'topicColors': instance.topicColors.map((k, e) => MapEntry(k, e.toJson())),
  'recentTopics': instance.recentTopics,
  'lastUsed': instance.lastUsed?.toIso8601String(),
  'simulation': instance.simulation.toJson(),
};
