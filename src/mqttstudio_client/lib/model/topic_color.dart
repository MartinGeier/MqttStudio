import 'dart:math';

import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

// use 'flutter pub run build_runner build' to run the code generator
part 'topic_color.g.dart';

@JsonSerializable(explicitToJson: true)
class TopicColor {
  static List<Color> defaultColors = [Colors.pink, Colors.green, Colors.blue, Colors.orange, Colors.brown, Colors.teal, Colors.deepPurple];

  @_ColorConverter()
  final Color color;

  const TopicColor(this.color);

  factory TopicColor.random() {
    return TopicColor(defaultColors[Random().nextInt(defaultColors.length)]);
  }

  factory TopicColor.fromJson(Map<String, dynamic> json) => _$TopicColorFromJson(json);
  Map<String, dynamic> toJson() => _$TopicColorToJson(this);
}

class _ColorConverter implements JsonConverter<Color, int> {
  const _ColorConverter();

  @override
  Color fromJson(int jsonValue) => Color(jsonValue);

  @override
  int toJson(Color color) => color.value;
}
