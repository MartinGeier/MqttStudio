import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/discover_viewmodel.dart';
import 'package:mqttstudio/documentation/discovery_service.dart';
import 'package:mqttstudio/documentation/doc_node_editor_model.dart';
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/documentation/engine/discovery_merger.dart';
import 'package:mqttstudio/documentation/engine/documentation_analyzer.dart';
import 'package:mqttstudio/documentation/engine/schema_paths.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/message_viewer/message_viewer.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:typed_data/typed_buffers.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_setup.dart';

final DateTime start = DateTime.utc(2026, 10, 24, 9);

RecordedMessage at(double seconds, String topic, String payload,
        {MqttQos qos = MqttQos.atLeastOnce, bool retain = false}) =>
    RecordedMessage(
        offsetMicros: (seconds * 1000000).round(),
        topic: topic,
        payload: Uint8List.fromList(utf8.encode(payload)),
        qos: qos,
        retain: retain);

DocumentationAnalyzer analyzed(List<RecordedMessage> messages) {
  var analyzer = DocumentationAnalyzer();
  for (var message in messages) {
    analyzer.add(message, start.add(message.offset));
  }
  return analyzer;
}

void main() {
  group('DiscoveryMerger', () {
    late TopicDocumentation documentation;
    late DocNode status;
    late DocNode old;

    setUp(() {
      status = DocNode(
          path: 'f/m{machine}/status',
          parameters: [DocParameter(name: 'machine')],
          topic: TopicSpec(
              qos: MqttQos.atLeastOnce,
              interval: IntervalSpec(kind: IntervalKind.periodic, nominalMs: 10000),
              payload: PayloadSpec(
                  format: PayloadFormat.json,
                  schema: SchemaNode(properties: {'temp': SchemaNode(type: SchemaType.number, maximum: 120)}))));
      old = DocNode(path: 'f/legacy', topic: TopicSpec());
      documentation = TopicDocumentation(nodes: [status, old]);
    });

    List<RecordedMessage> traffic() => [
          for (var i = 0; i < 6; i++) ...[
            at(i * 1.0, 'f/m12/status', '{"temp":${100 + i * 5},"tool":"T1"}', qos: MqttQos.atMostOnce),
            at(i * 1.0 + 0.1, 'f/m51/status', '{"temp":90}', qos: MqttQos.atMostOnce),
          ],
          for (var meter in [1, 2, 3])
            for (var i = 0; i < 3; i++) at(i * 2.0, 'energy/meter$meter/power', '${meter * 10 + i}'),
          at(1, 'f/alarm', 'on'),
        ];

    test('compares documented values with what was seen', () {
      var result = DiscoveryMerger.build(documentation, analyzed(traffic()),
          DiscoverySettings(filters: [RecorderFilter('f/#'), RecorderFilter('energy/#')]));
      expect(result.matched.keys, [status]);
      var differences = result.changed.single.differences;
      expect(
          differences.map((difference) => difference.kind),
          containsAll([
            DifferenceKind.qos,
            DifferenceKind.interval,
            DifferenceKind.schemaFieldAdded,
            DifferenceKind.schemaRange
          ]));
      expect(differences.firstWhere((difference) => difference.kind == DifferenceKind.schemaFieldAdded).subject,
          r'$.tool');
      expect(result.notSeen, [old]);
      expect(result.added.map((item) => item.path), ['energy/meter{meter}/power', 'f/alarm']);
      expect(result.templates.single.observed.instanceCount, 3);
    });

    test('apply adds, adopts, marks and ignores; edited fields are never prefilled', () {
      var settings = DiscoverySettings(filters: [RecorderFilter('#')]);
      var result = DiscoveryMerger.build(documentation, analyzed(traffic()), settings);
      result.changed.single.differences.firstWhere((difference) => difference.kind == DifferenceKind.qos).adopt = true;
      var template = result.templates.single..names['meter'] = 'meterNo';
      var alarm = result.added.firstWhere((item) => item.path == 'f/alarm')
        ..accept = false
        ..ignore = true;
      expect(template.path, 'energy/meter{meterNo}/power');

      DiscoveryMerger.apply(documentation, result, settings, isMqtt5: true);

      expect(status.topic!.qos, MqttQos.atMostOnce);
      expect(status.review, DocReviewState.changed);
      expect(status.observed!.instanceCount, 2);
      expect(old.review, DocReviewState.notSeen);
      var power = documentation.nodeAt('energy/meter{meterNo}/power')!;
      expect(power.review, DocReviewState.added);
      expect(power.status, DocStatus.draft);
      expect(power.parameters.single.pattern, r'\d+');
      expect(power.parameters.single.examples, ['1', '2', '3']);
      expect(power.topic!.payload.format, PayloadFormat.number);
      expect(power.topic!.qos, MqttQos.atLeastOnce);
      expect(power.topic!.payload.examples, hasLength(1));
      expect(documentation.nodeAt(alarm.path), isNull);
      expect(documentation.ignoreFilters, ['f/alarm']);
      expect(documentation.revision, 1);
      expect(documentation.lastDiscoveryAt, isNotNull);
    });

    test('prefill fills empty fields and leaves edited ones alone', () {
      var node = DocNode(path: 'a', topic: TopicSpec(), editedFields: {DocNodeEditorModel.qos});
      var observed = analyzed([for (var i = 0; i < 6; i++) at(i * 2.0, 'a', '{"v":$i}', retain: true)]).observe(['a']);
      DiscoveryMerger.prefill(node, observed, isMqtt5: true);
      expect(node.topic!.qos, isNull);
      expect(node.topic!.retain, RetainMode.always);
      expect(node.topic!.payload.format, PayloadFormat.json);
      expect(SchemaPaths.find(node.topic!.payload.schema, r'$.v')!.maximum, isNull);
      expect(node.topic!.interval.kind, IntervalKind.periodic);
      expect(node.topic!.interval.nominalMs, 2000);
      expect(node.topic!.interval.staleAfterMs, 6000);
    });

    test('documented single topics collapse into a template with new siblings', () {
      var m1 = DocNode(path: 'p/m1/temp', title: 'Machine 1', topic: TopicSpec());
      var m2 = DocNode(path: 'p/m2/temp', topic: TopicSpec());
      var docs = TopicDocumentation(nodes: [m1, m2]);
      var analyzer = analyzed([at(0, 'p/m1/temp', '1'), at(0, 'p/m2/temp', '2'), at(0, 'p/m3/temp', '3')]);
      var result = DiscoveryMerger.build(docs, analyzer, DiscoverySettings());
      var item = result.added.single;
      expect(item.path, 'p/m{id}/temp');
      expect(item.collapses, [m1, m2]);
      DiscoveryMerger.apply(docs, result, DiscoverySettings(), isMqtt5: true);
      expect(docs.nodes.map((node) => node.path), ['p/m{id}/temp']);
      expect(docs.nodes.single.title, 'Machine 1');
    });

    test('a template can be added as single topics instead', () {
      var docs = TopicDocumentation();
      var result = DiscoveryMerger.build(
          docs, analyzed([for (var i = 1; i <= 3; i++) at(0, 'm/$i', '$i')]), DiscoverySettings());
      result.added.single.asTemplate = false;
      DiscoveryMerger.apply(docs, result, DiscoverySettings(), isMqtt5: true);
      expect(docs.nodes.map((node) => node.path), ['m/1', 'm/2', 'm/3']);
    });

    test('helpers for filters', () {
      expect(DiscoveryMerger.ignoreFilterOf('p/m{id}/temp'), 'p/+/temp');
      expect(DiscoveryMerger.sampleTopic('p/m{id}/temp'), 'p/mx/temp');
    });
  });

  group('DiscoveryService', () {
    late List<FakeMqttAdapter> connections;
    late DiscoveryService discovery;

    setUp(() async {
      setUpServices();
      GetIt.I.unregister<DiscoveryService>();
      connections = [];
      discovery = DiscoveryService(connectionFactory: () {
        var connection = FakeMqttAdapter();
        connections.add(connection);
        return connection;
      });
      GetIt.I.registerSingleton(discovery);
      await openNewProject();
    });

    tearDown(() async {
      discovery.dispose();
      await tearDownServices();
    });

    ReceivedMqttMessage received(String topic, String payload, {bool retain = false}) => ReceivedMqttMessage(
        1, topic, Uint8Buffer()..addAll(utf8.encode(payload)), MqttQos.atLeastOnce, DateTime.now(), retain);

    test('live discovery has its own connection and subscribes with QoS 2 and Retain As Published', () async {
      GetIt.I.get<ProjectManager>().currentProject!.mqttSettings.protocolVersion = MqttProtocolVersion.v5;
      await discovery.start(
          DiscoverySettings(filters: [RecorderFilter('plant/#'), RecorderFilter('plant/debug/#', exclude: true)]));
      expect(discovery.state, DiscoveryState.running);
      var connection = connections.single;
      expect(connection.connectedWith!.clientId, contains('-doc-'));
      var subscription = connection.subscriptions.single;
      expect(subscription.topic, 'plant/#');
      expect(subscription.qos, MqttQos.exactlyOnce);
      expect(subscription.retainAsPublished, isTrue);
      expect(subscription.retainHandling, SubscriptionRetainHandling.sendOnSubscribe);

      connection.messageReceivedEvent.broadcast(received('plant/config', '{"a":1}', retain: true));
      connection.messageReceivedEvent.broadcast(received('plant/temp', '20'));
      connection.messageReceivedEvent.broadcast(received('plant/debug/x', '1'));
      connection.messageReceivedEvent.broadcast(received(r'$SYS/broker/uptime', '1'));
      expect(discovery.messages, 2);
      expect(discovery.newTopicCount, 2);

      var results = 0;
      discovery.resultEvent.subscribe((_) => results++);
      await discovery.stop();
      expect(results, 1);
      expect(discovery.state, DiscoveryState.idle);
      expect(connection.connected, isFalse);
      var result = discovery.lastResult!;
      expect(result.added.map((item) => item.path), ['plant/config', 'plant/temp']);
      expect(result.added.first.observed.retainedSnapshot, 1);
      // nothing changes before the review is applied
      expect(GetIt.I.get<DocumentationService>().nodes, isEmpty);

      discovery.apply(result);
      expect(GetIt.I.get<DocumentationService>().nodes.map((node) => node.path), ['plant/config', 'plant/temp']);
      expect(discovery.lastResult, isNull);
      expect(GetIt.I.get<ProjectManager>().hasProjectChanged(), isTrue);
    });

    test('a lost connection is a gap and the discovery goes on after the reconnect', () async {
      await discovery.start(DiscoverySettings(filters: [RecorderFilter('#')], stop: DiscoveryStop.manual));
      var connection = connections.single;
      connection.disconnect();
      expect(discovery.state, DiscoveryState.reconnecting);
      await discovery.stop();
      expect(discovery.state, DiscoveryState.idle);
    });

    test('discovers from the topic viewer messages', () async {
      var buffer = GetIt.I.get<MessageViewer>().messageBuffer;
      for (var i = 0; i < 4; i++) {
        buffer.storeMessage(ReceivedMqttMessage(1, 'a/temp', Uint8Buffer()..addAll(utf8.encode('$i')),
            MqttQos.atMostOnce, start.add(Duration(seconds: i)), false));
      }
      var results = 0;
      discovery.resultEvent.subscribe((_) => results++);
      await discovery.start(DiscoverySettings(filters: [RecorderFilter('#')]), source: DiscoverySource.buffer);
      await pumpEventQueue();
      expect(results, 1);
      var item = discovery.lastResult!.added.single;
      expect(item.path, 'a/temp');
      expect(item.observed.interval.medianMs, 1000);
      expect(item.observed.source, DiscoverySource.buffer);
      expect(connections, isEmpty);
    });

    test('discovers from a recording', () async {
      var info = await recordInLibrary('Line 1', ['plant/a', 'plant/b', 'plant/a']);
      await discovery.start(DiscoverySettings(filters: [RecorderFilter('#')]),
          source: DiscoverySource.recording, recording: info);
      await pumpEventQueue();
      var result = discovery.lastResult!;
      expect(result.sourceName, 'Line 1');
      expect(result.messages, 3);
      expect(result.added.map((item) => item.path), ['plant/a', 'plant/b']);
    });

    test('a discovery after another one can be stopped', () async {
      var info = await recordInLibrary('Line 1', ['plant/a', 'plant/b']);
      await discovery.start(DiscoverySettings(filters: [RecorderFilter('#')]),
          source: DiscoverySource.recording, recording: info);
      await pumpEventQueue();
      expect(discovery.state, DiscoveryState.idle);

      for (var run = 0; run < 2; run++) {
        await discovery.start(DiscoverySettings(filters: [RecorderFilter('#')], stop: DiscoveryStop.manual));
        connections.last.messageReceivedEvent.broadcast(received('plant/run$run', '1'));
        await discovery.stop();
        expect(discovery.state, DiscoveryState.idle, reason: 'run $run');
        expect(connections.last.connected, isFalse);
        expect(discovery.lastResult!.added.single.path, 'plant/run$run');
      }
    });

    test('the message limit stops a live discovery', () async {
      await discovery
          .start(DiscoverySettings(filters: [RecorderFilter('#')], stop: DiscoveryStop.messages, maxMessages: 2));
      for (var i = 0; i < 3; i++) {
        connections.single.messageReceivedEvent.broadcast(received('plant/t$i', '1'));
      }
      await pumpEventQueue();
      expect(discovery.state, DiscoveryState.idle);
      expect(discovery.lastResult!.messages, 2);
    });

    test('a result that can not be built ends the discovery with an error', () async {
      await discovery.start(DiscoverySettings(filters: [RecorderFilter('#')], stop: DiscoveryStop.manual));
      var errors = <String>[];
      discovery.errorEvent.subscribe((args) => errors.add(args.message));
      // anything that throws while the result is built
      GetIt.I.get<ProjectManager>().currentProject!.documentation.nodes.add(_BrokenNode());
      connections.single.messageReceivedEvent.broadcast(received('plant/x', '1'));
      await discovery.stop();
      expect(discovery.state, DiscoveryState.idle);
      expect(errors, isNotEmpty);
      GetIt.I.get<ProjectManager>().currentProject!.documentation.nodes.removeLast();
      await discovery.start(DiscoverySettings(filters: [RecorderFilter('#')], stop: DiscoveryStop.manual));
      expect(discovery.state, DiscoveryState.running);
      await discovery.stop();
    });

    test('the dialog starts with an empty filter and remembers the filters of an applied discovery', () async {
      String firstFilter() => (DiscoverViewmodel().filters.value!.first!)[DiscoverViewmodel.filterField] as String;
      var documentation = GetIt.I.get<ProjectManager>().currentProject!.documentation;
      expect(firstFilter(), '');
      // settings that were never applied don't count
      documentation.discoverySettings.filters = [RecorderFilter('#')];
      expect(firstFilter(), '');
      await discovery.start(DiscoverySettings(filters: [RecorderFilter('plant/#')]));
      connections.single.messageReceivedEvent.broadcast(received('plant/a', '1'));
      await discovery.stop();
      discovery.apply(discovery.lastResult!);
      expect(firstFilter(), 'plant/#');
    });

    test('a discovery needs an include filter', () async {
      expect(DiscoverySettings().filters, isEmpty);
      expect(() => discovery.start(DiscoverySettings()), throwsArgumentError);
      expect(() => discovery.start(DiscoverySettings(filters: [RecorderFilter('a/#', exclude: true)])),
          throwsArgumentError);
      expect(discovery.state, DiscoveryState.idle);
      expect(connections, isEmpty);
    });

    test('closing the project cancels a discovery without a result', () async {
      await discovery.start(DiscoverySettings(filters: [RecorderFilter('#')]));
      closingNotSavedAnswer = false;
      await GetIt.I.get<ProjectManager>().closeProject();
      expect(discovery.state, DiscoveryState.idle);
      expect(discovery.lastResult, isNull);
    });
  });
}

class _BrokenNode extends DocNode {
  _BrokenNode() : super(path: 'broken');

  @override
  bool get isTopic => throw StateError('broken node');
}
