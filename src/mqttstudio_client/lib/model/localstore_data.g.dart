// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'localstore_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LocalStoreData _$LocalStoreDataFromJson(Map<String, dynamic> json) =>
    LocalStoreData()
      ..projects = (json['projects'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, Project.fromJson(e as Map<String, dynamic>)),
      )
      ..browserPerformanceWarningDoNotShow =
          json['browserPerformanceWarningDoNotShow'] as bool?
      ..coachingCompleted = json['coachingCompleted'] as bool?;

Map<String, dynamic> _$LocalStoreDataToJson(LocalStoreData instance) =>
    <String, dynamic>{
      'projects': instance.projects?.map((k, e) => MapEntry(k, e.toJson())),
      'browserPerformanceWarningDoNotShow':
          instance.browserPerformanceWarningDoNotShow,
      'coachingCompleted': instance.coachingCompleted,
    };
