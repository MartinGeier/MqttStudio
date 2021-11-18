import 'package:json_annotation/json_annotation.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:srx_flutter/srx_flutter.dart';

import 'mqtt_settings.dart';
import 'topic_color.dart';

// use 'flutter pub run build_runner build' to run the code generator
part 'project.g.dart';

@JsonSerializable(explicitToJson: true)
class Project extends SrxBaseModel {
  String name;
  MqttSettings mqttSettings;
  List<TopicSubscription> topicSubscriptions = [];
  Map<String, TopicColor> topicColors = Map();
  List<String> recentTopics = [];
  DateTime? lastUsed;

  Project(this.mqttSettings, {this.name = 'New Project'});

  factory Project.fromJson(Map<String, dynamic> json) => _$ProjectFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$ProjectToJson(this);
}
