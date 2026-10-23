import 'package:json_annotation/json_annotation.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/topic_color.dart';

// use 'flutter pub run build_runner build' to run the code generator
part 'topic_subscription.g.dart';

// MQTT 5 retain handling subscription option, in the order of the protocol values 0, 1 and 2
enum SubscriptionRetainHandling {
  sendOnSubscribe,
  sendIfNew,
  doNotSend,
}

@JsonSerializable(explicitToJson: true)
class TopicSubscription {
  static const String sharePrefix = '\$share/';

  String topic;
  MqttQos qos;
  late TopicColor color;
  bool paused;

  // MQTT 5 subscription options, ignored for MQTT 3.1.1 connections
  @JsonKey(defaultValue: false)
  bool noLocal;
  @JsonKey(defaultValue: false)
  bool retainAsPublished;
  @JsonKey(defaultValue: SubscriptionRetainHandling.sendOnSubscribe)
  SubscriptionRetainHandling retainHandling;

  TopicSubscription(this.topic, this.qos,
      {TopicColor? color,
      this.paused = false,
      this.noLocal = false,
      this.retainAsPublished = false,
      this.retainHandling = SubscriptionRetainHandling.sendOnSubscribe}) {
    if ('#'.allMatches(topic).length > 1) {
      throw new Exception('Invalid topic \'$topic\'');
    }

    if (color != null) {
      this..color = color;
    } else {
      this.color = TopicColor.random();
    }
  }

  // Returns wether topicName matches the given subscription.
  // -1: if no match
  // 0: for a # match
  // 1: for a + match
  // 2: for a full match without wildcards
  static int isTopicSubscriptionMatch(String topicName, String subscriptionName) {
    subscriptionName = topicFilterOf(subscriptionName);
    if (topicName == subscriptionName) {
      return 2;
    }

    if (!subscriptionName.contains('+') && !subscriptionName.contains('#')) {
      return -1;
    }

    var topicNameLevels = topicName.split('/');
    var subscriptionLevels = subscriptionName.split('/');
    for (int i = 0; i < subscriptionLevels.length; i++) {
      var subsLevel = subscriptionLevels[i];
      if (subsLevel == '#') {
        return 0;
      }
      if (i > topicNameLevels.length - 1) {
        return -1;
      }
      if (subsLevel == '+' || subsLevel == topicNameLevels[i]) {
        continue;
      }
      if (subsLevel != topicNameLevels[i]) {
        return -1;
      }

      if (topicNameLevels.length == subscriptionLevels.length) {
        return 1;
      }

      return -1;
    }

    if (topicNameLevels.length != subscriptionLevels.length) {
      return -1;
    }

    // at this point we have a full match or a + match
    return subscriptionName.contains('+') ? 1 : 2;
  }

  // Messages of a shared subscription ('$share/<group>/<filter>') arrive with their real topic name, so they have to
  // be matched against the filter part only.
  static String topicFilterOf(String subscriptionName) {
    if (!subscriptionName.startsWith(sharePrefix)) {
      return subscriptionName;
    }
    var filterStart = subscriptionName.indexOf('/', sharePrefix.length);
    return filterStart < 0 ? subscriptionName : subscriptionName.substring(filterStart + 1);
  }

  static TopicSubscription? getTopicSubscriptionMatch(String topicName, List<TopicSubscription> subscriptions) {
    int bestMatch = -1;
    TopicSubscription? bestMatchSub;
    for (var sub in subscriptions) {
      int match = isTopicSubscriptionMatch(topicName, sub.topic);
      if (match == 2) {
        return sub;
      }
      if (match > bestMatch) {
        bestMatch = match;
        bestMatchSub = sub;
      }
    }
    return bestMatchSub;
  }

  factory TopicSubscription.fromJson(Map<String, dynamic> json) => _$TopicSubscriptionFromJson(json);
  Map<String, dynamic> toJson() => _$TopicSubscriptionToJson(this);
}
