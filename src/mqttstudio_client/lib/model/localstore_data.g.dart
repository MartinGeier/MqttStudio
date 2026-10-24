// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'localstore_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LocalStoreData _$LocalStoreDataFromJson(
  Map<String, dynamic> json,
) => LocalStoreData()
  ..projects = (json['projects'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, Project.fromJson(e as Map<String, dynamic>)),
  )
  ..browserPerformanceWarningDoNotShow =
      json['browserPerformanceWarningDoNotShow'] as bool?
  ..newsletterSignpDoNotShow = json['newsletterSignpDoNotShow'] as bool?
  ..coachingCompleted = json['coachingCompleted'] as bool?
  ..recordingsFolder = json['recordingsFolder'] as String?
  ..lastRecorderConfig = json['lastRecorderConfig'] == null
      ? null
      : RecorderConfig.fromJson(
          json['lastRecorderConfig'] as Map<String, dynamic>,
        )
  ..playbackOptions = (json['playbackOptions'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, PlaybackOptions.fromJson(e as Map<String, dynamic>)),
  );

Map<String, dynamic> _$LocalStoreDataToJson(LocalStoreData instance) =>
    <String, dynamic>{
      'projects': instance.projects?.map((k, e) => MapEntry(k, e.toJson())),
      'browserPerformanceWarningDoNotShow':
          instance.browserPerformanceWarningDoNotShow,
      'newsletterSignpDoNotShow': instance.newsletterSignpDoNotShow,
      'coachingCompleted': instance.coachingCompleted,
      'recordingsFolder': instance.recordingsFolder,
      'lastRecorderConfig': instance.lastRecorderConfig?.toJson(),
      'playbackOptions': instance.playbackOptions?.map(
        (k, e) => MapEntry(k, e.toJson()),
      ),
    };
