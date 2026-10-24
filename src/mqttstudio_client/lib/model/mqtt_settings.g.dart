// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mqtt_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MqttSettings _$MqttSettingsFromJson(Map<String, dynamic> json) =>
    MqttSettings(
        json['hostname'] as String,
        json['clientId'] as String,
        (json['port'] as num).toInt(),
        username: json['username'] as String?,
        password: json['password'] as String?,
        useSsl: json['useSsl'] as bool? ?? false,
      )
      ..useWebSockets = json['useWebSockets'] as bool? ?? false
      ..caCertificatePath = json['caCertificatePath'] as String?
      ..clientCertificatePath = json['clientCertificatePath'] as String?
      ..clientKeyPath = json['clientKeyPath'] as String?
      ..clientKeyPassword = json['clientKeyPassword'] as String?
      ..protocolVersion =
          $enumDecodeNullable(
            _$MqttProtocolVersionEnumMap,
            json['protocolVersion'],
          ) ??
          MqttProtocolVersion.v311
      ..cleanStart = json['cleanStart'] as bool? ?? true
      ..sessionExpiryInterval =
          (json['sessionExpiryInterval'] as num?)?.toInt() ?? 0;

Map<String, dynamic> _$MqttSettingsToJson(
  MqttSettings instance,
) => <String, dynamic>{
  'hostname': instance.hostname,
  'clientId': instance.clientId,
  'port': instance.port,
  'username': instance.username,
  'password': instance.password,
  'useSsl': instance.useSsl,
  'useWebSockets': instance.useWebSockets,
  'caCertificatePath': instance.caCertificatePath,
  'clientCertificatePath': instance.clientCertificatePath,
  'clientKeyPath': instance.clientKeyPath,
  'clientKeyPassword': instance.clientKeyPassword,
  'protocolVersion': _$MqttProtocolVersionEnumMap[instance.protocolVersion]!,
  'cleanStart': instance.cleanStart,
  'sessionExpiryInterval': instance.sessionExpiryInterval,
};

const _$MqttProtocolVersionEnumMap = {
  MqttProtocolVersion.v311: 'v311',
  MqttProtocolVersion.v5: 'v5',
};
