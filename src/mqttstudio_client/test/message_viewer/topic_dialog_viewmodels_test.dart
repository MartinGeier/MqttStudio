import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/message_viewer/add_topic_viewmodel.dart';
import 'package:mqttstudio/message_viewer/publish_topic_viewmodel.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:reactive_forms/reactive_forms.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_setup.dart';

void main() {
  late FakeMqttAdapter adapter;
  late Project project;

  setUp(() async {
    adapter = setUpServices();
    project = await openNewProject();
    await adapter.connect(project.mqttSettings);
  });

  tearDown(tearDownServices);

  group('TopicNameValidator', () {
    Map<String, dynamic>? validate(String? value) => TopicNameValidator().validate(FormControl<String>(value: value));

    test('accepts topics with and without wildcards', () {
      expect(validate('home/kitchen/temp'), isNull);
      expect(validate('home/+/temp'), isNull);
      expect(validate('home/#'), isNull);
      expect(validate('#'), isNull);
    });

    test('rejects an empty value and more than one multi level wildcard', () {
      expect(validate(null), isNotNull);
      expect(validate('home/#/#'), isNotNull);
    });

    test('rejects a multi level wildcard that is not the last level', () {
      // MQTT spec: "#" must be the last character of the topic filter
      expect(validate('home/#/temp'), isNotNull);
      expect(validate('home#'), isNotNull);
    });
  });

  group('AddTopicViewmodel', () {
    test('starts with QoS 1 and a default color', () {
      var viewmodel = AddTopicViewmodel();
      expect(viewmodel.form.control(AddTopicViewmodel.qosField).value, MqttQos.atLeastOnce);
      expect(viewmodel.form.control(AddTopicViewmodel.colorField).value, isNotNull);
    });

    test('does not add an invalid topic', () {
      var viewmodel = AddTopicViewmodel();

      expect(viewmodel.addTopic(), isFalse);
      expect(viewmodel.form.control(AddTopicViewmodel.topicNameField).touched, isTrue);
      expect(project.topicSubscriptions, isEmpty);
    });

    test('adds and subscribes a valid topic', () {
      var viewmodel = AddTopicViewmodel();
      viewmodel.form.control(AddTopicViewmodel.topicNameField).value = 'home/#';
      viewmodel.form.control(AddTopicViewmodel.qosField).value = MqttQos.exactlyOnce;
      viewmodel.form.control(AddTopicViewmodel.colorField).value = Colors.pink;

      expect(viewmodel.addTopic(), isTrue);

      var sub = project.topicSubscriptions.single;
      expect(sub.topic, 'home/#');
      expect(sub.qos, MqttQos.exactlyOnce);
      expect(sub.color.color, Colors.pink);
      expect(adapter.subscribed, ['home/#']);
    });

    test('rejects a topic longer than 200 characters', () {
      var viewmodel = AddTopicViewmodel();
      viewmodel.form.control(AddTopicViewmodel.topicNameField).value = 'a' * 201;

      expect(viewmodel.addTopic(), isFalse);
    });
  });

  group('PublishTopicViewmodel', () {
    PublishTopicViewmodel viewmodelFor(String? topic, {String? payload, bool? retain}) {
      var viewmodel = PublishTopicViewmodel();
      viewmodel.form.control(PublishTopicViewmodel.topicNameField).value = topic;
      viewmodel.form.control(PublishTopicViewmodel.payloadField).value = payload;
      viewmodel.form.control(PublishTopicViewmodel.retainField).value = retain;
      return viewmodel;
    }

    test('publishes text with the retain flag', () async {
      expect(await viewmodelFor('home/light', payload: 'on', retain: true).publishTopic(), isTrue);

      var published = adapter.published.single;
      expect(published.topic, 'home/light');
      expect(published.payload, 'on');
      expect(published.payloadType, MqttPayloadType.string);
      expect(published.retain, isTrue);
    });

    test('publishes an empty payload when none is entered', () async {
      expect(await viewmodelFor('home/light').publishTopic(), isTrue);

      expect(adapter.published.single.payload, '');
      expect(adapter.published.single.retain, isFalse);
    });

    test('requires a topic', () async {
      expect(await viewmodelFor(null, payload: 'on').publishTopic(), isFalse);
      expect(adapter.published, isEmpty);
    });

    test('rejects wildcards in the topic', () async {
      expect(await viewmodelFor('home/+/light').publishTopic(), isFalse);
      expect(await viewmodelFor('home/#').publishTopic(), isFalse);
      expect(adapter.published, isEmpty);
    });

    test('publishes a file as binary payload', () async {
      var dir = await Directory.systemTemp.createTemp('mqttstudio_test');
      addTearDown(() => dir.delete(recursive: true));
      var file = File('${dir.path}/payload.bin')..writeAsBytesSync([1, 2, 3]);

      expect(await viewmodelFor('home/file').publishTopicFromFile(file.path), isTrue);

      var published = adapter.published.single;
      expect(published.payloadType, MqttPayloadType.binary);
      expect(published.payload, [1, 2, 3]);
    });

    test('refuses files larger than 500 kB', () async {
      var dir = await Directory.systemTemp.createTemp('mqttstudio_test');
      addTearDown(() => dir.delete(recursive: true));
      var file = File('${dir.path}/big.bin')..writeAsBytesSync(List.filled(500001, 0));

      await expectLater(viewmodelFor('home/file').publishTopicFromFile(file.path), throwsException);
      expect(adapter.published, isEmpty);
    });
  });
}
