// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mqtt_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MqttSettings _$MqttSettingsFromJson(Map<String, dynamic> json) => MqttSettings(
      json['hostname'] as String,
      json['clientId'] as String,
      json['port'] as int,
      username: json['username'] as String?,
      password: json['password'] as String?,
      useSsl: json['useSsl'] as bool? ?? false,
    )..useWebSockets = json['useWebSockets'] as bool? ?? false;

Map<String, dynamic> _$MqttSettingsToJson(MqttSettings instance) =>
    <String, dynamic>{
      'hostname': instance.hostname,
      'clientId': instance.clientId,
      'port': instance.port,
      'username': instance.username,
      'password': instance.password,
      'useSsl': instance.useSsl,
      'useWebSockets': instance.useWebSockets,
    };
