import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/check_service.dart';
import 'package:mqttstudio/documentation/discovery_service.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/mqtt/mqtt_will.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:typed_data/typed_buffers.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_setup.dart';

// A broker that answers the connect only when the test says so
class _SlowMqttAdapter extends FakeMqttAdapter {
  final Completer<void> answer = Completer();

  @override
  Future connect(MqttSettings mqttSettings, {MqttWill? will}) async {
    await answer.future;
    await super.connect(mqttSettings, will: will);
  }
}

void main() {
  late List<_SlowMqttAdapter> connections;
  var broker = MqttSettings('test.mosquitto.org', 'client-1', 1883);

  _SlowMqttAdapter connection() {
    var adapter = _SlowMqttAdapter();
    connections.add(adapter);
    return adapter;
  }

  ReceivedMqttMessage received(String topic, String payload) => ReceivedMqttMessage(
      1, topic, Uint8Buffer()..addAll(utf8.encode(payload)), MqttQos.atLeastOnce, DateTime.now(), false);

  TopicDocumentation documentation() =>
      TopicDocumentation(nodes: [DocNode(path: 'plant/temp', topic: TopicSpec())]);

  setUp(() => connections = []);

  group('DiscoveryService', () {
    DiscoverySettings settings() => DiscoverySettings(filters: [RecorderFilter('plant/#')]);

    test('a stop while connecting closes the new connection and ends without a result', () async {
      var discovery = DiscoveryService(connectionFactory: connection, withProjects: false);
      var results = 0;
      discovery.resultEvent.subscribe((_) => results++);
      var starting = discovery.start(settings(), documentation: documentation(), broker: broker);
      expect(discovery.state, DiscoveryState.connecting);
      await discovery.stop();
      expect(discovery.state, DiscoveryState.idle);

      connections.single.answer.complete();
      await starting;
      expect(discovery.state, DiscoveryState.idle);
      expect(connections.single.connected, isFalse);
      expect(connections.single.subscribed, isEmpty);
      connections.single.receive(received('plant/temp', '20'));
      expect(discovery.messages, 0);
      expect(results, 0);
      discovery.dispose();
    });

    test('a failed connect after a stop is no error', () async {
      var discovery = DiscoveryService(connectionFactory: connection, withProjects: false);
      var starting = discovery.start(settings(), documentation: documentation(), broker: broker);
      await discovery.stop();
      connections.single.answer.completeError(Exception('unreachable'));
      await expectLater(starting, completes);
      expect(discovery.state, DiscoveryState.idle);
      discovery.dispose();
    });

    test('a discovery started again while the first one connects keeps only its own connection', () async {
      var discovery = DiscoveryService(connectionFactory: connection, withProjects: false);
      var first = discovery.start(settings(), documentation: documentation(), broker: broker);
      await discovery.stop();
      var second = discovery.start(settings(), documentation: documentation(), broker: broker);
      connections[0].answer.complete();
      await first;
      expect(discovery.state, DiscoveryState.connecting);
      connections[1].answer.complete();
      await second;
      expect(discovery.state, DiscoveryState.running);
      expect(connections[0].connected, isFalse);
      connections[1].receive(received('plant/temp', '20'));
      expect(discovery.messages, 1);
      await discovery.stop();
      discovery.dispose();
    });

    test('closing the project while connecting closes the new connection', () async {
      setUpServices();
      addTearDown(tearDownServices);
      await openNewProject();
      var discovery = DiscoveryService(connectionFactory: connection);
      addTearDown(discovery.dispose);
      var starting = discovery.start(settings());
      await GetIt.I.get<ProjectManager>().closeProject(true);
      connections.single.answer.complete();
      await starting;
      expect(discovery.state, DiscoveryState.idle);
      expect(connections.single.connected, isFalse);
    });
  });

  group('CheckService', () {
    test('a stop while connecting closes the new connection and checks nothing', () async {
      var check = CheckService(connectionFactory: connection, withProjects: false);
      var starting = check.start(documentation: documentation(), settings: broker);
      expect(check.state, CheckState.connecting);
      check.stop();
      expect(check.state, CheckState.idle);

      connections.single.answer.complete();
      await starting;
      expect(check.state, CheckState.idle);
      expect(connections.single.connected, isFalse);
      expect(connections.single.subscribed, isEmpty);
      connections.single.receive(received('plant/temp', '20'));
      expect(check.messages, 0);
      check.dispose();
    });

    test('a failed connect after a stop is no error', () async {
      var check = CheckService(connectionFactory: connection, withProjects: false);
      var starting = check.start(documentation: documentation(), settings: broker);
      check.stop();
      connections.single.answer.completeError(Exception('unreachable'));
      await expectLater(starting, completes);
      expect(check.state, CheckState.idle);
      check.dispose();
    });

    test('closing the project while connecting closes the new connection', () async {
      setUpServices();
      addTearDown(tearDownServices);
      await openNewProject();
      GetIt.I.get<ProjectManager>().currentProject!.documentation.nodes.add(DocNode(path: 'a/b', topic: TopicSpec()));
      var check = CheckService(connectionFactory: connection);
      addTearDown(check.dispose);
      var starting = check.start();
      await GetIt.I.get<ProjectManager>().closeProject(true);
      connections.single.answer.complete();
      await starting;
      expect(check.state, CheckState.idle);
      expect(check.checker, isNull);
      expect(connections.single.connected, isFalse);
    });
  });
}
