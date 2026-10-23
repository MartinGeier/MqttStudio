import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';

void main() {
  group('MqttSettings protocol version', () {
    test('projects saved before the version could be chosen use MQTT 3.1.1', () {
      var settings = MqttSettings.fromJson({'hostname': 'broker.local', 'clientId': 'client', 'port': 1883});

      expect(settings.protocolVersion, MqttProtocolVersion.v311);
      expect(settings.isMqtt5, isFalse);
      expect(settings.cleanStart, isTrue);
      expect(settings.sessionExpiryInterval, 0);
    });

    test('survives a JSON round trip with the MQTT 5 session settings', () {
      var settings = MqttSettings('broker.local', 'client', 1883)
        ..protocolVersion = MqttProtocolVersion.v5
        ..cleanStart = false
        ..sessionExpiryInterval = 3600;

      var copy = MqttSettings.fromJson(settings.toJson());

      expect(copy.protocolVersion, MqttProtocolVersion.v5);
      expect(copy.isMqtt5, isTrue);
      expect(copy.cleanStart, isFalse);
      expect(copy.sessionExpiryInterval, 3600);
    });

    test('connectionSettingsChanged detects changed protocol and session settings', () {
      MqttSettings settings() => MqttSettings('broker.local', 'client', 1883);

      expect(settings().connectionSettingsChanged(settings()..protocolVersion = MqttProtocolVersion.v5), isTrue);
      expect(settings().connectionSettingsChanged(settings()..cleanStart = false), isTrue);
      expect(settings().connectionSettingsChanged(settings()..sessionExpiryInterval = 60), isTrue);
    });
  });

  group('TopicSubscription MQTT 5 options', () {
    test('subscriptions saved before the options existed get the protocol defaults', () {
      var sub = TopicSubscription.fromJson({
        'topic': 'home/#',
        'qos': 'atLeastOnce',
        'color': TopicColor(Colors.pink).toJson(),
        'paused': false,
      });

      expect(sub.noLocal, isFalse);
      expect(sub.retainAsPublished, isFalse);
      expect(sub.retainHandling, SubscriptionRetainHandling.sendOnSubscribe);
    });

    test('survives a JSON round trip with the options', () {
      var sub = TopicSubscription('home/#', MqttQos.atLeastOnce,
          noLocal: true, retainAsPublished: true, retainHandling: SubscriptionRetainHandling.doNotSend);

      var copy = TopicSubscription.fromJson(sub.toJson());

      expect(copy.noLocal, isTrue);
      expect(copy.retainAsPublished, isTrue);
      expect(copy.retainHandling, SubscriptionRetainHandling.doNotSend);
    });

    test('retain handling is declared in the order of the protocol values', () {
      // Mqtt5ProtocolClient maps it to the client package by index
      expect(SubscriptionRetainHandling.values.map((handling) => handling.index), [0, 1, 2]);
      expect(MqttRetainHandling.values.length, SubscriptionRetainHandling.values.length);
    });
  });

  group('TopicSubscription shared subscriptions', () {
    test('topicFilterOf removes the share prefix and group', () {
      expect(TopicSubscription.topicFilterOf('\$share/group/home/+/temp'), 'home/+/temp');
      expect(TopicSubscription.topicFilterOf('\$share/group/#'), '#');
      expect(TopicSubscription.topicFilterOf('home/+/temp'), 'home/+/temp');
    });

    test('messages of a shared subscription match its filter', () {
      expect(TopicSubscription.isTopicSubscriptionMatch('home/kitchen/temp', '\$share/g/home/+/temp'), 1);
      expect(TopicSubscription.isTopicSubscriptionMatch('home/kitchen/temp', '\$share/g/home/kitchen/temp'), 2);
      expect(TopicSubscription.isTopicSubscriptionMatch('home/kitchen/temp', '\$share/g/#'), 0);
      expect(TopicSubscription.isTopicSubscriptionMatch('office/printer', '\$share/g/home/#'), -1);
    });

    test('getTopicSubscriptionMatch finds the shared subscription', () {
      var shared = TopicSubscription('\$share/g/home/#', MqttQos.atMostOnce, color: TopicColor(Colors.teal));

      expect(TopicSubscription.getTopicSubscriptionMatch('home/kitchen/temp', [shared]), shared);
    });
  });

  group('MqttMessageProperties', () {
    test('is empty without any property', () {
      expect(MqttMessageProperties().isEmpty, isTrue);
      expect(MqttMessageProperties(contentType: '', responseTopic: '', correlationData: Uint8List(0)).isEmpty, isTrue);
    });

    test('is not empty with any property', () {
      expect(MqttMessageProperties(contentType: 'application/json').isEmpty, isFalse);
      expect(MqttMessageProperties(responseTopic: 'reply').isEmpty, isFalse);
      expect(MqttMessageProperties(correlationData: Uint8List.fromList([1])).isEmpty, isFalse);
      expect(MqttMessageProperties(messageExpiryInterval: 0).isEmpty, isFalse);
      expect(MqttMessageProperties(payloadFormatUtf8: true).isEmpty, isFalse);
      expect(MqttMessageProperties(userProperties: [MqttUserPropertyEntry('k', 'v')]).isEmpty, isFalse);
      expect(MqttMessageProperties(subscriptionIdentifiers: [1]).isEmpty, isFalse);
    });
  });
}
