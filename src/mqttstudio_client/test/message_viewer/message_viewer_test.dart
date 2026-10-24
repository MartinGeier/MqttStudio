import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/message_viewer/message_viewer.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_setup.dart';

void main() {
  late FakeMqttAdapter adapter;
  late MessageViewer viewer;
  late Project project;

  setUp(() async {
    adapter = setUpServices();
    viewer = GetIt.I.get<MessageViewer>();
    project = await openNewProject();
  });

  tearDown(tearDownServices);

  TopicSubscription subscription(String topic, {bool paused = false}) =>
      TopicSubscription(topic, MqttQos.atLeastOnce, color: TopicColor(Colors.teal), paused: paused);

  group('MessageViewer subscriptions', () {
    test('adding a subscription stores it in the project and subscribes when connected', () async {
      await adapter.connect(project.mqttSettings);
      var changes = 0;
      viewer.topicSubscriptionsChangedEvent.subscribe((_) => changes++);

      viewer.addTopicSubscription(subscription('home/#'));

      expect(project.topicSubscriptions.single.topic, 'home/#');
      expect(project.topicColors['home/#']!.color, Colors.teal);
      expect(project.recentTopics, ['home/#']);
      expect(adapter.subscribed, ['home/#']);
      expect(changes, 1);
    });

    test('adding a subscription while disconnected only stores it', () {
      viewer.addTopicSubscription(subscription('home/#'));

      expect(project.topicSubscriptions, hasLength(1));
      expect(adapter.subscribed, isEmpty);
    });

    test('adding a subscription while all topics are paused does not subscribe', () async {
      await adapter.connect(project.mqttSettings);
      viewer.pauseAllTopics();

      viewer.addTopicSubscription(subscription('home/#'));

      expect(adapter.subscribed, isEmpty);
    });

    test('rejects a duplicate subscription', () {
      viewer.addTopicSubscription(subscription('home/#'));

      expect(
          () => viewer.addTopicSubscription(subscription('home/#')),
          throwsA(
              isA<SrxServiceException>().having((x) => x.serviceError, 'serviceError', ServiceError.DuplicateTopic)));
      expect(project.topicSubscriptions, hasLength(1));
    });

    test('removing a subscription unsubscribes and removes it from the project', () async {
      await adapter.connect(project.mqttSettings);
      viewer.addTopicSubscription(subscription('home/#'));

      viewer.removeTopicSubscription('home/#');

      expect(project.topicSubscriptions, isEmpty);
      expect(adapter.unsubscribed, ['home/#']);
    });

    test('pausing a single topic unsubscribes it, resuming subscribes again', () async {
      await adapter.connect(project.mqttSettings);
      viewer.addTopicSubscription(subscription('home/#'));

      viewer.tooglePauseTopicSubscription('home/#');
      expect(project.topicSubscriptions.single.paused, isTrue);
      expect(adapter.unsubscribed, ['home/#']);

      viewer.tooglePauseTopicSubscription('home/#');
      expect(project.topicSubscriptions.single.paused, isFalse);
      expect(adapter.subscribed, ['home/#', 'home/#']);
    });

    test('playing all topics resubscribes only the topics that are not paused', () async {
      await adapter.connect(project.mqttSettings);
      viewer.addTopicSubscription(subscription('a/#'));
      viewer.addTopicSubscription(subscription('b/#'));
      viewer.tooglePauseTopicSubscription('b/#');
      adapter.subscribed.clear();

      viewer.pauseAllTopics();
      expect(viewer.paused, isTrue);
      expect(adapter.unsubscribed, containsAll(['a/#', 'b/#']));

      viewer.playAllTopics();
      expect(viewer.paused, isFalse);
      expect(adapter.subscribed, ['a/#']);
    });

    test('subscribes to all topics that are not paused when the connection is established', () async {
      project.topicSubscriptions.addAll([subscription('a/#'), subscription('b/#', paused: true)]);

      await adapter.connect(project.mqttSettings);

      expect(adapter.subscribed, ['a/#']);
    });
  });

  group('MessageViewer messages', () {
    test('stores received messages and forwards them', () {
      var forwarded = [];
      viewer.messageReceivedEvent.subscribe((msg) => forwarded.add(msg));

      adapter.receive(message('home/temp', '21.5'));

      expect(viewer.messageBuffer.length, 1);
      expect(forwarded, hasLength(1));
    });

    test('gives a received message the color of the best matching subscription', () {
      viewer.addTopicSubscription(TopicSubscription('#', MqttQos.atLeastOnce, color: TopicColor(Colors.red)));
      viewer.addTopicSubscription(TopicSubscription('home/+', MqttQos.atLeastOnce, color: TopicColor(Colors.blue)));

      adapter.receive(message('home/temp', '1'));
      adapter.receive(message('office/printer', '2'));

      expect(viewer.getTopicColor('home/temp').color, Colors.blue);
      expect(viewer.getTopicColor('office/printer').color, Colors.red);
    });

    test('gives a message without a matching subscription black', () {
      adapter.receive(message('home/temp', '1'));

      expect(viewer.getTopicColor('home/temp').color, Colors.black);
    });

    test('clears the messages when the project is closed', () async {
      var cleared = 0;
      viewer.messagesClearedEvent.subscribe((_) => cleared++);
      adapter.receive(message('home/temp', '1'));

      await GetIt.I.get<ProjectManager>().closeProject(true);

      expect(viewer.messageBuffer.length, 0);
      expect(cleared, greaterThan(0));
    });
  });

  group('MessageViewer publishing', () {
    test('publishes when connected and remembers the topic', () async {
      await adapter.connect(project.mqttSettings);

      viewer.publishTopic('home/light', 'on', MqttPayloadType.string, true);

      var published = adapter.published.single;
      expect(published.topic, 'home/light');
      expect(published.payload, 'on');
      expect(published.retain, isTrue);
      expect(published.qos, MqttQos.atLeastOnce);
      expect(project.recentTopics, ['home/light']);
    });

    test('does not publish while disconnected but still remembers the topic', () {
      viewer.publishTopic('home/light', 'on', MqttPayloadType.string, false);

      expect(adapter.published, isEmpty);
      expect(project.recentTopics, ['home/light']);
    });

    test('keeps the 20 most recent topics without duplicates', () {
      for (var i = 0; i < 25; i++) {
        viewer.publishTopic('topic/$i', '', MqttPayloadType.string, false);
      }
      viewer.publishTopic('topic/24', '', MqttPayloadType.string, false);

      expect(project.recentTopics, hasLength(20));
      expect(project.recentTopics.first, 'topic/24');
      expect(project.recentTopics.last, 'topic/5');
    });
  });
}
