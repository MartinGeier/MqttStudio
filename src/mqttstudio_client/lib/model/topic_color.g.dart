// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'topic_color.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TopicColor _$TopicColorFromJson(Map<String, dynamic> json) {
  return TopicColor(
    const _ColorConverter().fromJson(json['color'] as int),
  );
}

Map<String, dynamic> _$TopicColorToJson(TopicColor instance) =>
    <String, dynamic>{
      'color': const _ColorConverter().toJson(instance.color),
    };
