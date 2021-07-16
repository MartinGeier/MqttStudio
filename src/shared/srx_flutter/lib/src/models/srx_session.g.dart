// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'srx_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SrxSession _$SrxSessionFromJson(Map<String, dynamic> json) {
  return SrxSession(
    json['accessToken'] as String,
    json['refreshToken'] as String,
    DateTime.parse(json['accessTokenExpirationDateTime'] as String),
  )..customData = json['customData'] as Map<String, dynamic>;
}

Map<String, dynamic> _$SrxSessionToJson(SrxSession instance) =>
    <String, dynamic>{
      'accessToken': instance.accessToken,
      'refreshToken': instance.refreshToken,
      'accessTokenExpirationDateTime':
          instance.accessTokenExpirationDateTime.toIso8601String(),
      'customData': instance.customData,
    };
