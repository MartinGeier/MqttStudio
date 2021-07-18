// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Project _$ProjectFromJson(Map<String, dynamic> json) {
  return Project(
    json['mqttHostname'] as String,
    json['clientId'] as String,
    json['port'] as int,
    name: json['name'] as String,
    username: json['username'] as String?,
    password: json['password'] as String?,
  )
    ..id = json['id'] as String?
    ..createdOn = json['createdOn'] == null
        ? null
        : DateTime.parse(json['createdOn'] as String)
    ..lastModifiedOn = json['lastModifiedOn'] == null
        ? null
        : DateTime.parse(json['lastModifiedOn'] as String);
}

Map<String, dynamic> _$ProjectToJson(Project instance) => <String, dynamic>{
      'id': instance.id,
      'createdOn': instance.createdOn?.toIso8601String(),
      'lastModifiedOn': instance.lastModifiedOn?.toIso8601String(),
      'name': instance.name,
      'mqttHostname': instance.mqttHostname,
      'clientId': instance.clientId,
      'port': instance.port,
      'username': instance.username,
      'password': instance.password,
    };
