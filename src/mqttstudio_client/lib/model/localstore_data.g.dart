// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'localstore_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LocalStoreData _$LocalStoreDataFromJson(Map<String, dynamic> json) {
  return LocalStoreData()
    ..projects = (json['projects'] as Map<String, dynamic>?)?.map(
      (k, e) => MapEntry(k, Project.fromJson(e as Map<String, dynamic>)),
    );
}

Map<String, dynamic> _$LocalStoreDataToJson(LocalStoreData instance) =>
    <String, dynamic>{
      'projects': instance.projects?.map((k, e) => MapEntry(k, e.toJson())),
    };
