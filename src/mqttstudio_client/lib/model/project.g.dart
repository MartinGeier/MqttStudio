// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Project _$ProjectFromJson(Map<String, dynamic> json) => Project(
      MqttSettings.fromJson(json['mqttSettings'] as Map<String, dynamic>),
      name: json['name'] as String? ?? 'New Project',
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
          .toList()
      ..lastUsed = json['lastUsed'] == null
          ? null
          : DateTime.parse(json['lastUsed'] as String);

Map<String, dynamic> _$ProjectToJson(Project instance) {
  final val = <String, dynamic>{
    'id': SrxBaseModel.setIdIfNull(instance.id),
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('createdOn', instance.createdOn?.toIso8601String());
  writeNotNull('lastModifiedOn', instance.lastModifiedOn?.toIso8601String());
  writeNotNull('createdBy', instance.createdBy);
  writeNotNull('lastModifiedBy', instance.lastModifiedBy);
  val['name'] = instance.name;
  val['mqttSettings'] = instance.mqttSettings.toJson();
  val['topicSubscriptions'] =
      instance.topicSubscriptions.map((e) => e.toJson()).toList();
  val['topicColors'] =
      instance.topicColors.map((k, e) => MapEntry(k, e.toJson()));
  val['recentTopics'] = instance.recentTopics;
  val['lastUsed'] = instance.lastUsed?.toIso8601String();
  return val;
}
