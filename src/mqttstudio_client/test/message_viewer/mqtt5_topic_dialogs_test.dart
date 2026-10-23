import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/message_viewer/add_topic_viewmodel.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/message_viewer/publish_topic_viewmodel.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:reactive_forms/reactive_forms.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_setup.dart';

void main() {
  late FakeMqttAdapter adapter;
  late Project project;

  Future openProject(MqttProtocolVersion version) async {
    project = await openNewProject();
    project.mqttSettings.protocolVersion = version;
    await adapter.connect(project.mqttSettings);
  }

  setUp(() => adapter = setUpServices());
  tearDown(tearDownServices);

  group('TopicNameValidator shared subscriptions', () {
    Map<String, dynamic>? validate(String value) => TopicNameValidator().validate(FormControl<String>(value: value));

    test('accepts a group and a filter', () {
      expect(validate('\$share/group/home/+/temp'), isNull);
      expect(validate('\$share/group/#'), isNull);
    });

    test('rejects a missing group or filter', () {
      expect(validate('\$share//home/temp'), isNotNull);
      expect(validate('\$share/group'), isNotNull);
      expect(validate('\$share/group/'), isNotNull);
    });

    test('rejects wildcards in the group', () {
      expect(validate('\$share/gr+oup/home'), isNotNull);
      expect(validate('\$share/#/home'), isNotNull);
    });
  });

  group('AddTopicViewmodel MQTT 5 options', () {
    test('knows whether the project uses MQTT 5', () async {
      await openProject(MqttProtocolVersion.v311);
      expect(AddTopicViewmodel().isMqtt5, isFalse);

      project.mqttSettings.protocolVersion = MqttProtocolVersion.v5;
      expect(AddTopicViewmodel().isMqtt5, isTrue);
    });

    test('subscribes with the chosen options', () async {
      await openProject(MqttProtocolVersion.v5);
      var viewmodel = AddTopicViewmodel();
      viewmodel.form.control(AddTopicViewmodel.topicNameField).value = 'home/#';
      viewmodel.form.control(AddTopicViewmodel.noLocalField).value = true;
      viewmodel.form.control(AddTopicViewmodel.retainAsPublishedField).value = true;
      viewmodel.form.control(AddTopicViewmodel.retainHandlingField).value = SubscriptionRetainHandling.sendIfNew;

      expect(viewmodel.addTopic(), isTrue);

      var sub = adapter.subscriptions.single;
      expect(sub.noLocal, isTrue);
      expect(sub.retainAsPublished, isTrue);
      expect(sub.retainHandling, SubscriptionRetainHandling.sendIfNew);
      expect(project.topicSubscriptions.single, same(sub));
    });
  });

  group('PublishTopicViewmodel MQTT 5 properties', () {
    PublishTopicViewmodel viewmodelFor(String topic) {
      var viewmodel = PublishTopicViewmodel();
      viewmodel.form.control(PublishTopicViewmodel.topicNameField).value = topic;
      return viewmodel;
    }

    test('sends no properties for MQTT 3.1.1 projects', () async {
      await openProject(MqttProtocolVersion.v311);
      var viewmodel = viewmodelFor('home/light');
      viewmodel.form.control(PublishTopicViewmodel.contentTypeField).value = 'text/plain';

      expect(await viewmodel.publishTopic(), isTrue);
      expect(adapter.published.single.properties, isNull);
    });

    test('sends the entered properties for MQTT 5 projects', () async {
      await openProject(MqttProtocolVersion.v5);
      var viewmodel = viewmodelFor('home/light');
      viewmodel.form.control(PublishTopicViewmodel.contentTypeField).value = 'application/json';
      viewmodel.form.control(PublishTopicViewmodel.responseTopicField).value = 'home/light/reply';
      viewmodel.form.control(PublishTopicViewmodel.correlationDataField).value = 'request-1';
      viewmodel.form.control(PublishTopicViewmodel.messageExpiryIntervalField).value = 30;
      viewmodel.form.control(PublishTopicViewmodel.payloadFormatUtf8Field).value = true;
      viewmodel.addUserProperty();
      var row = viewmodel.userProperties.controls.single as FormGroup;
      row.control(PublishTopicViewmodel.userPropertyKeyField).value = 'source';
      row.control(PublishTopicViewmodel.userPropertyValueField).value = 'mqttstudio';

      expect(await viewmodel.publishTopic(), isTrue);

      var properties = adapter.published.single.properties!;
      expect(properties.contentType, 'application/json');
      expect(properties.responseTopic, 'home/light/reply');
      expect(utf8.decode(properties.correlationData!), 'request-1');
      expect(properties.messageExpiryInterval, 30);
      expect(properties.payloadFormatUtf8, isTrue);
      expect(properties.userProperties.single.key, 'source');
      expect(properties.userProperties.single.value, 'mqttstudio');
    });

    test('leaves empty fields out', () async {
      await openProject(MqttProtocolVersion.v5);

      expect(await viewmodelFor('home/light').publishTopic(), isTrue);
      expect(adapter.published.single.properties!.isEmpty, isTrue);
    });

    test('requires a key for every user property', () async {
      await openProject(MqttProtocolVersion.v5);
      var viewmodel = viewmodelFor('home/light')..addUserProperty();

      expect(await viewmodel.publishTopic(), isFalse);

      viewmodel.removeUserProperty(0);
      expect(await viewmodel.publishTopic(), isTrue);
    });

    test('rejects wildcards in the response topic and a negative expiry', () async {
      await openProject(MqttProtocolVersion.v5);
      var viewmodel = viewmodelFor('home/light');

      viewmodel.form.control(PublishTopicViewmodel.responseTopicField).value = 'reply/#';
      expect(await viewmodel.publishTopic(), isFalse);

      viewmodel.form.control(PublishTopicViewmodel.responseTopicField).value = 'reply';
      viewmodel.form.control(PublishTopicViewmodel.messageExpiryIntervalField).value = -1;
      expect(await viewmodel.publishTopic(), isFalse);
    });
  });

  group('MessageViewerViewmodel.rePublish', () {
    test('sends the properties of the received message again', () async {
      await openProject(MqttProtocolVersion.v5);
      var viewmodel = MessageViewerViewmodel();
      var properties = MqttMessageProperties(contentType: 'text/plain');
      adapter.receive(message('home/light', 'on')..properties = properties);
      viewmodel.selectedMessage = viewmodel.messageBuffer.getLastMessage();

      viewmodel.rePublish();

      expect(adapter.published.single.properties, same(properties));
    });
  });
}
