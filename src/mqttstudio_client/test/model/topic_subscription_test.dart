import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';

void main() {
  group('TopicSubscription.isTopicSubscriptionMatch', () {
    test('returns 2 for an identical topic', () {
      expect(TopicSubscription.isTopicSubscriptionMatch('home/kitchen/temp', 'home/kitchen/temp'), 2);
    });

    test('returns -1 for a different topic without wildcards', () {
      expect(TopicSubscription.isTopicSubscriptionMatch('home/kitchen/temp', 'home/kitchen/humidity'), -1);
      expect(TopicSubscription.isTopicSubscriptionMatch('home/kitchen', 'home/kitchen/temp'), -1);
    });

    test('returns 1 for a match with single level wildcards', () {
      expect(TopicSubscription.isTopicSubscriptionMatch('home/kitchen/temp', 'home/+/temp'), 1);
      expect(TopicSubscription.isTopicSubscriptionMatch('home/kitchen/temp', '+/+/+'), 1);
    });

    test('single level wildcard matches exactly one level', () {
      expect(TopicSubscription.isTopicSubscriptionMatch('home/kitchen/oven/temp', 'home/+/temp'), -1);
      expect(TopicSubscription.isTopicSubscriptionMatch('home/temp', 'home/+/temp'), -1);
      expect(TopicSubscription.isTopicSubscriptionMatch('home/kitchen/humidity', 'home/+/temp'), -1);
    });

    test('returns 0 for a match with the multi level wildcard', () {
      expect(TopicSubscription.isTopicSubscriptionMatch('home/kitchen/temp', '#'), 0);
      expect(TopicSubscription.isTopicSubscriptionMatch('home/kitchen/temp', 'home/#'), 0);
      expect(TopicSubscription.isTopicSubscriptionMatch('home/kitchen/temp', 'home/+/#'), 0);
    });

    test('multi level wildcard also matches the parent level', () {
      // MQTT spec: "sport/#" also matches "sport"
      expect(TopicSubscription.isTopicSubscriptionMatch('home', 'home/#'), 0);
    });

    test('multi level wildcard does not match another branch', () {
      expect(TopicSubscription.isTopicSubscriptionMatch('office/kitchen/temp', 'home/#'), -1);
    });
  });

  group('TopicSubscription.getTopicSubscriptionMatch', () {
    var all = TopicSubscription('#', MqttQos.atMostOnce, color: TopicColor(Colors.red));
    var plus = TopicSubscription('home/+/temp', MqttQos.atMostOnce, color: TopicColor(Colors.green));
    var exact = TopicSubscription('home/kitchen/temp', MqttQos.atMostOnce, color: TopicColor(Colors.blue));

    test('prefers the exact subscription over wildcards', () {
      expect(TopicSubscription.getTopicSubscriptionMatch('home/kitchen/temp', [all, plus, exact]), exact);
    });

    test('prefers a single level wildcard over the multi level wildcard', () {
      expect(TopicSubscription.getTopicSubscriptionMatch('home/garage/temp', [all, plus, exact]), plus);
    });

    test('falls back to the multi level wildcard', () {
      expect(TopicSubscription.getTopicSubscriptionMatch('office/printer', [all, plus, exact]), all);
    });

    test('returns null if no subscription matches', () {
      expect(TopicSubscription.getTopicSubscriptionMatch('office/printer', [plus, exact]), isNull);
      expect(TopicSubscription.getTopicSubscriptionMatch('office/printer', []), isNull);
    });
  });

  group('TopicSubscription', () {
    test('gets a random default color', () {
      var sub = TopicSubscription('a/b', MqttQos.atLeastOnce);
      expect(TopicColor.defaultColors, contains(sub.color.color));
    });

    test('rejects a topic with more than one multi level wildcard', () {
      expect(() => TopicSubscription('a/#/#', MqttQos.atLeastOnce), throwsException);
    });

    test('survives a JSON round trip', () {
      var sub = TopicSubscription('home/+/temp', MqttQos.exactlyOnce, color: TopicColor(Colors.teal), paused: true);

      var copy = TopicSubscription.fromJson(sub.toJson());

      expect(copy.topic, 'home/+/temp');
      expect(copy.qos, MqttQos.exactlyOnce);
      expect(copy.color.color.toARGB32(), Colors.teal.toARGB32());
      expect(copy.paused, isTrue);
    });
  });
}
