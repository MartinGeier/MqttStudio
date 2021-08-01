import 'package:json_annotation/json_annotation.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/topic_color.dart';

// use 'flutter pub run build_runner build' to run the code generator
part 'topic_subscription.g.dart';

@JsonSerializable(explicitToJson: true)
class TopicSubscription {
  String topic;
  MqttQos qos;
  late TopicColor color;

  TopicSubscription(this.topic, this.qos, {TopicColor? color}) {
    if (color != null) {
      this..color = color;
    } else {
      this.color = TopicColor.random();
    }
  }

  factory TopicSubscription.fromJson(Map<String, dynamic> json) => _$TopicSubscriptionFromJson(json);
  Map<String, dynamic> toJson() => _$TopicSubscriptionToJson(this);
}
