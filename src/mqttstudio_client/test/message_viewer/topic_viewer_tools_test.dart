import 'dart:convert';
import 'dart:typed_data';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/common/utils/payload_decoder.dart';
import 'package:mqttstudio/message_viewer/message_filter.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/message_viewer/publish_topic_viewmodel.dart';
import 'package:mqttstudio/message_viewer/retained_messages_viewmodel.dart';
import 'package:mqttstudio/message_viewer/retained_scanner.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/broker_stats_viewmodel.dart';
import 'package:mqttstudio/mqtt/sys_monitor.dart';
import 'package:typed_data/typed_buffers.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_setup.dart';

void main() {
  late FakeMqttAdapter adapter;
  late Project project;
  late MessageViewerViewmodel viewmodel;
  var start = DateTime(2026, 10, 25, 12);

  setUp(() async {
    adapter = setUpServices();
    project = await openNewProject();
    await adapter.connect(project.mqttSettings);
    viewmodel = MessageViewerViewmodel();
  });

  tearDown(() async {
    viewmodel.dispose();
    await tearDownServices();
  });

  group('MessageViewerViewmodel filter', () {
    test('builds the filter of the chosen mode', () {
      viewmodel.setFilter(r'$.temp > 80', mode: MessageFilterMode.condition);

      expect(viewmodel.filter!.mode, MessageFilterMode.condition);
      expect(viewmodel.filterError, isNull);
      expect(viewmodel.filter!.matches(message('a', '{"temp": 90}')), isTrue);
    });

    test('keeps the mode and regex for a new text', () {
      viewmodel.setFilter('', mode: MessageFilterMode.payload, regex: true);
      viewmodel.setFilter('err.r');

      expect(viewmodel.filterMode, MessageFilterMode.payload);
      expect(viewmodel.filter!.matches(message('a', 'an error')), isTrue);
    });

    test('shows all messages and reports an invalid filter', () {
      viewmodel.setFilter('plant/#/temp');

      expect(viewmodel.filter, isNull);
      expect(viewmodel.filterError, isNotNull);

      viewmodel.setFilter('plant/#');
      expect(viewmodel.filterError, isNull);
    });
  });

  group('MessageViewerViewmodel payloads', () {
    test('decodes with the decoder chosen for the topic', () {
      adapter.receive(message('a', 'eyJ2IjoxfQ=='));
      var received = viewmodel.messageBuffer.getLastMessage()!;
      expect(viewmodel.decoderOf('a'), PayloadDecoder.auto);

      viewmodel.setDecoder('a', PayloadDecoder.base64);

      expect(viewmodel.decode(received).value, {'v': 1});
      expect(viewmodel.decoderOf('b'), PayloadDecoder.auto);
    });

    test('finds the previous message of the selected one', () {
      adapter.receive(message('a', '{"v":1}', receivedOn: start));
      adapter.receive(message('b', '{"v":2}', receivedOn: start.add(Duration(seconds: 1))));
      adapter.receive(message('a', '{"v":3}', receivedOn: start.add(Duration(seconds: 2))));
      viewmodel.selectedMessage = viewmodel.messageBuffer.getLastMessageForTopic('a');

      expect(viewmodel.previousOfSelected!.receivedOn, start);
    });

    test('marks a message for comparing until the messages are cleared', () {
      adapter.receive(message('a', '1'));
      viewmodel.selectedMessage = viewmodel.messageBuffer.getLastMessage();

      viewmodel.markForCompare();
      expect(viewmodel.markedMessage, same(viewmodel.selectedMessage));

      viewmodel.clearMessages();
      expect(viewmodel.markedMessage, isNull);
    });

    test('edits only UTF-8 payloads', () {
      var binary = ReceivedMqttMessage(1, 'a', Uint8Buffer()..addAll([0xff, 0x00]), MqttQos.atMostOnce, start, false);

      expect(viewmodel.canEditPayload(message('a', 'text')), isTrue);
      expect(viewmodel.canEditPayload(binary), isFalse);
    });
  });

  group('MessageViewerViewmodel branches', () {
    test('subscribes to a branch', () {
      viewmodel.subscribeToBranch('plant/line1');

      expect(project.topicSubscriptions.single.topic, 'plant/line1/#');
      expect(adapter.subscribed, ['plant/line1/#']);
      expect(viewmodel.isSubscribed('plant/line1/#'), isTrue);
    });

    test('unsubscribes the subscriptions within a branch only', () {
      viewmodel.addTopicSubscription(TopicSubscription('plant/#', MqttQos.atLeastOnce));
      viewmodel.addTopicSubscription(TopicSubscription('plant/line1/temp', MqttQos.atLeastOnce));
      viewmodel.addTopicSubscription(TopicSubscription('plant/line1/+/state', MqttQos.atLeastOnce));
      viewmodel.addTopicSubscription(TopicSubscription('plant/line1', MqttQos.atLeastOnce));

      expect(viewmodel.subscriptionsInBranch('plant/line1').map((s) => s.topic),
          ['plant/line1/temp', 'plant/line1/+/state', 'plant/line1']);

      viewmodel.unsubscribeFromBranch('plant/line1');
      expect(project.topicSubscriptions.map((s) => s.topic), ['plant/#']);
    });

    test('expands and collapses a branch below a topic level', () {
      adapter.receive(message('plant/line1/temp', '1'));
      viewmodel.collapseAll();
      expect(viewmodel.treeController.isNodeExpanded(MessageViewerViewmodel.treeKeyOf('plant')), isFalse);

      viewmodel.expandBranch('plant');

      expect(viewmodel.treeController.isNodeExpanded(MessageViewerViewmodel.treeKeyOf('plant')), isTrue);
      expect(viewmodel.treeController.isNodeExpanded(MessageViewerViewmodel.treeKeyOf('plant/line1')), isTrue);

      viewmodel.collapseBranch('plant/line1');
      expect(viewmodel.treeController.isNodeExpanded(MessageViewerViewmodel.treeKeyOf('plant/line1')), isFalse);
      expect(viewmodel.treeController.isNodeExpanded(MessageViewerViewmodel.treeKeyOf('plant')), isTrue);
    });

    test('updates the tree every second for the time since the last message', () {
      fakeAsync((async) {
        var ticking = MessageViewerViewmodel();
        adapter.receive(message('a', '1'));
        var notified = 0;
        ticking.addListener(() => notified++);

        ticking.topicViewMode = TopicViewMode.Tree;
        async.elapse(Duration(seconds: 3));
        expect(notified, 4);

        ticking.showTopicStats = false;
        async.elapse(Duration(seconds: 3));
        expect(notified, 5);
        ticking.dispose();
      });
    });
  });

  group('PublishTopicViewmodel prefilled with a message', () {
    test('starts with the topic, payload, retain flag and MQTT 5 properties', () {
      project.mqttSettings.protocolVersion = MqttProtocolVersion.v5;
      var received = ReceivedMqttMessage(1, 'plant/state', toPayload('{"on":true}'), MqttQos.atLeastOnce, start, true,
          properties: MqttMessageProperties(
              contentType: 'application/json',
              responseTopic: 'plant/reply',
              correlationData: Uint8List.fromList(utf8.encode('req-1')),
              messageExpiryInterval: 60,
              userProperties: [MqttUserPropertyEntry('source', 'line1')]));

      var publish = PublishTopicViewmodel(message: received);

      expect(publish.form.control(PublishTopicViewmodel.topicNameField).value, 'plant/state');
      expect(publish.form.control(PublishTopicViewmodel.payloadField).value, '{"on":true}');
      expect(publish.form.control(PublishTopicViewmodel.retainField).value, isTrue);
      var properties = publish.buildProperties()!;
      expect(properties.contentType, 'application/json');
      expect(properties.responseTopic, 'plant/reply');
      expect(utf8.decode(properties.correlationData!), 'req-1');
      expect(properties.messageExpiryInterval, 60);
      expect(properties.userProperties.single.key, 'source');
    });
  });

  group('RetainedScanner', () {
    late FakeMqttAdapter side;
    late RetainedScanner scanner;

    void open(FakeAsync async) {
      scanner = RetainedScanner(connectionFactory: () => side = FakeMqttAdapter());
      scanner.open(project.mqttSettings);
      async.flushMicrotasks();
    }

    test('collects the retained messages below the filter until it gets quiet', () {
      fakeAsync((async) {
        open(async);
        List<ReceivedMqttMessage>? found;
        scanner.scan('plant/#').then((messages) => found = messages);

        expect(side.subscribed, ['plant/#']);
        expect(side.connectedWith!.clientId, startsWith('${project.mqttSettings.clientId}-retained-'));
        side.receive(message('plant/b', '2', retain: true));
        side.receive(message('plant/a', '1', retain: true));
        side.receive(message('plant/c', 'published while scanning'));
        side.receive(message('other', 'x', retain: true));
        async.elapse(Duration(milliseconds: 500));
        expect(found, isNull);

        async.elapse(RetainedScanner.quietPeriod);
        expect(found!.map((m) => m.topicName), ['plant/a', 'plant/b']);
        expect(side.unsubscribed, ['plant/#']);
        scanner.close();
      });
    });

    test('ends without retained messages and clears topics', () {
      fakeAsync((async) {
        open(async);
        List<ReceivedMqttMessage>? found;
        scanner.scan('#').then((messages) => found = messages);
        async.elapse(RetainedScanner.firstMessageWait);
        expect(found, isEmpty);

        scanner.clear(['a', 'b']);

        expect(side.published.map((p) => p.topic), ['a', 'b']);
        expect(side.published.every((p) => p.retain && p.payload == '' && p.payloadType == MqttPayloadType.string), isTrue);
        scanner.close();
        expect(side.disconnectCount, 1);
      });
    });
  });

  group('RetainedMessagesViewmodel', () {
    test('scans, selects all and clears the selected messages', () {
      fakeAsync((async) {
        late FakeMqttAdapter side;
        var retained = RetainedMessagesViewmodel(filter: 'plant/#', connectionFactory: () => side = FakeMqttAdapter());
        retained.scan();
        async.flushMicrotasks();
        expect(retained.state, RetainedScanState.scanning);
        side.receive(message('plant/a', '1', retain: true));
        side.receive(message('plant/b', '2', retain: true));
        async.elapse(Duration(seconds: 1));

        expect(retained.state, RetainedScanState.done);
        expect(retained.allSelected, isTrue);
        retained.toggle('plant/a');
        retained.clearSelected();

        expect(side.published.single.topic, 'plant/b');
        expect(retained.messages.map((m) => m.topicName), ['plant/a']);
        expect(retained.cleared, 1);
        retained.dispose();
      });
    });

    test('rejects an invalid topic filter', () {
      var retained = RetainedMessagesViewmodel(filter: 'plant/#/x');

      retained.scan();

      expect(retained.state, RetainedScanState.idle);
      expect(retained.form.valid, isFalse);
      retained.dispose();
    });
  });

  group('Broker statistics', () {
    test('summarizes the well-known \$SYS topics and lists all of them', () {
      fakeAsync((async) {
        late FakeMqttAdapter side;
        var stats = BrokerStatsViewmodel(connectionFactory: () => side = FakeMqttAdapter());
        stats.start();
        async.flushMicrotasks();
        expect(stats.state, BrokerStatsState.waiting);
        expect(side.subscribed, [r'$SYS/#']);

        side.receive(message(r'$SYS/broker/version', 'mosquitto version 2.0.18'));
        side.receive(message(r'$SYS/broker/clients/connected', '12'));
        side.receive(message(r'$SYS/broker/load/messages/received/1min', '120.5'));
        side.receive(message(r'$SYS/broker/custom', 'x'));
        async.elapse(Duration(seconds: 1));

        expect(stats.state, BrokerStatsState.receiving);
        expect(stats.summary.map((entry) => '${entry.$1.key}=${entry.$2}'),
            ['version=mosquitto version 2.0.18', 'clientsconnected=12', 'messagesreceived=120.5']);
        expect(stats.topicCount, 4);
        stats.topicFilter = 'CLIENTS';
        expect(stats.topics.single.key, r'$SYS/broker/clients/connected');
        stats.dispose();
      });
    });

    test('reports a broker without \$SYS topics', () {
      fakeAsync((async) {
        var stats = BrokerStatsViewmodel(connectionFactory: FakeMqttAdapter.new);
        stats.start();
        async.elapse(BrokerStatsViewmodel.noDataAfter);

        expect(stats.state, BrokerStatsState.noData);
        stats.dispose();
      });
    });

    test('reads EMQX node topics', () {
      var monitor = SysMonitor();
      var item = SysMonitor.summaryItems.firstWhere((item) => item.key == 'version');
      expect(item.topics.any((pattern) => pattern.hasMatch(r'$SYS/brokers/emqx@127.0.0.1/version')), isTrue);
      expect(monitor.valueOf(item), isNull);
    });
  });

}
