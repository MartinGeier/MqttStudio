import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/engine/conformance_checker.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_profile.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:mqttstudio/simulator/engine/simulator_runner.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/model/sparkplug_source.dart';
import 'package:mqttstudio/simulator/sparkplug/simulated_edge_node.dart';
import 'package:mqttstudio/simulator/sparkplug/sparkplug_fault.dart';
import 'package:typed_data/typed_buffers.dart';
import '../../helpers/fake_broker.dart';

class _MainConnection implements SimulatorPublisher {
  final List<String> published = [];
  @override
  bool isConnected = true;
  @override
  bool supportsProperties = true;

  @override
  void publish(String topic, Uint8Buffer payload, MqttQos qos, bool retain, MqttMessageProperties? properties) =>
      published.add(topic);
}

SimulatedDevice sparkplugDevice({int edgeNodes = 2, String? host}) => SimulatedDevice(
  name: 'Line 1',
  kind: DeviceKind.sparkplug,
  instanceCount: edgeNodes,
  sparkplug: SparkplugSource.example()
    ..seed = 3
    ..primaryHostId = host,
);

// the protocol rules the documentation check reports for everything the broker routed
Set<String> protocolRules(FakeBroker broker) {
  var checker = ConformanceChecker(TopicDocumentation());
  var at = DateTime.utc(2026, 10, 27, 8);
  for (var message in broker.log) {
    checker.check(
      RecordedMessage(offsetMicros: 0, topic: message.topic, payload: message.payload, retain: message.retain),
      at,
    );
  }
  return {
    for (var finding in checker.findings)
      if (finding.protocolRule != null) finding.protocolRule!,
  };
}

void main() {
  late FakeBroker broker;
  late _MainConnection main;
  late SimulatorRunner runner;

  void setUpRunner() {
    broker = FakeBroker();
    main = _MainConnection();
    runner = SimulatorRunner(
      main,
      seed: 1,
      connections: SimulatorConnections(
        settings: () => MqttSettings('broker', 'studio', 1883),
        factory: broker.newConnection,
      ),
    );
  }

  test('the runner starts an edge node per instance on its own connection and stops them with NDEATH', () {
    fakeAsync((async) {
      setUpRunner();
      var device = sparkplugDevice();
      runner.startDevice(device);
      async.elapse(const Duration(seconds: 10));
      expect(runner.isDeviceRunning(device.id), isTrue);
      var run = runner.sparkplugOf(device.id)!;
      expect(run.nodes.map((node) => node.edgeNodeId), ['Edge1', 'Edge2']);
      expect(run.nodes.every((node) => node.state == EdgeNodeState.online), isTrue);
      expect(broker.online, hasLength(2));
      expect(broker.online.every((connection) => connection.clientId!.startsWith('studio-spb-Edge')), isTrue);
      expect(runner.totalSent, run.sent);
      expect(run.sent, greaterThan(10));
      // nothing on the main connection
      expect(main.published, isEmpty);

      runner.stopDevice(device);
      async.flushMicrotasks();
      expect(runner.isDeviceRunning(device.id), isFalse);
      expect(broker.online, isEmpty);
      expect(broker.messagesOn('spBv1.0/Plant1/NDEATH/+').where((message) => !message.isWill), hasLength(2));
      // the edge nodes stay listed with their last state
      expect(runner.sparkplugOf(device.id), same(run));
      expect(protocolRules(broker), isEmpty);
    });
  });

  test('a simulated primary host goes online first, its STATE is cleared with the retained topics', () {
    fakeAsync((async) {
      setUpRunner();
      var device = sparkplugDevice(edgeNodes: 1, host: 'scada');
      runner.startDevice(device);
      async.elapse(const Duration(seconds: 5));
      expect(runner.sparkplugOf(device.id)!.nodes.single.state, EdgeNodeState.online);
      expect(broker.retained.keys, contains('spBv1.0/STATE/scada'));
      runner.stopAll();
      async.flushMicrotasks();
      expect(runner.clearRetainedConnections([device]), 1);
      expect(main.published, ['spBv1.0/STATE/scada']);
    });
  });

  test('without connections a Sparkplug device reports why it cannot run', () {
    fakeAsync((async) {
      var runner = SimulatorRunner(_MainConnection());
      var device = sparkplugDevice();
      runner.startDevice(device);
      expect(runner.isDeviceRunning(device.id), isFalse);
      expect(runner.deviceStatsOf(device.id).issue, SimulationIssueKind.sparkplugNoConnections);
    });
  });

  group('faults', () {
    // runs one edge node, injects the fault after 5 s and returns the protocol rules of the whole run
    Set<String> run(SparkplugFault fault) {
      late Set<String> rules;
      fakeAsync((async) {
        setUpRunner();
        var device = sparkplugDevice(edgeNodes: 1);
        runner.startDevice(device);
        async.elapse(const Duration(seconds: 5));
        var simulated = runner.sparkplugOf(device.id)!;
        var node = simulated.nodes.single;
        expect(node.isFaultAvailable(fault), isTrue, reason: fault.name);
        simulated.inject(node, fault);
        async.elapse(const Duration(seconds: 15));
        if (fault == SparkplugFault.devicesOffline) {
          expect(node.isFaultActive(fault), isTrue);
          simulated.inject(node, fault);
          async.elapse(const Duration(seconds: 5));
        }
        runner.stopAll();
        async.flushMicrotasks();
        rules = protocolRules(broker);
      });
      return rules;
    }

    for (var fault in SparkplugFault.values) {
      test('${fault.name} gives ${fault.rule ?? 'no finding'}', () {
        expect(run(fault), fault.rule == null ? isEmpty : {fault.rule});
      });
    }

    test('a dropped connection makes the broker send the will, the edge node comes back with the next bdSeq', () {
      fakeAsync((async) {
        setUpRunner();
        var device = sparkplugDevice(edgeNodes: 1);
        runner.startDevice(device);
        async.elapse(const Duration(seconds: 3));
        var simulated = runner.sparkplugOf(device.id)!;
        simulated.inject(simulated.nodes.single, SparkplugFault.dropConnection);
        async.flushMicrotasks();
        expect(broker.messagesOn('spBv1.0/Plant1/NDEATH/Edge1').single.isWill, isTrue);
        async.elapse(const Duration(seconds: 3));
        var births = broker.messagesOn('spBv1.0/Plant1/NBIRTH/Edge1');
        expect(births.map((message) => SparkplugProfile.payloadOf(message.payload)!.metric('bdSeq')!.value), [0, 1]);
        runner.stopAll();
      });
    });
  });

  group('rules', () {
    test('the example is valid and the limits of Q9 hold', () {
      expect(SimulationRules.validateSparkplug(sparkplugDevice()), isEmpty);
      List<SimulationIssueKind> kinds(SimulatedDevice device) =>
          SimulationRules.validateSparkplug(device).map((issue) => issue.kind).toList();

      expect(kinds(sparkplugDevice(edgeNodes: 21)), contains(SimulationIssueKind.sparkplugTooManyNodes));
      expect(
        kinds(sparkplugDevice()..sparkplug!.edgeNodeId = 'Edge'),
        contains(SimulationIssueKind.sparkplugNodeNeedsInstance),
      );
      expect(
        kinds(sparkplugDevice()..sparkplug!.devices.first.count = 2),
        contains(SimulationIssueKind.sparkplugDeviceNeedsNumber),
      );
      expect(kinds(sparkplugDevice()..sparkplug!.groupId = 'a/b'), contains(SimulationIssueKind.sparkplugNameInvalid));
      var reserved = sparkplugDevice()
        ..sparkplug!.nodeMetrics.add(
          SparkplugMetricSpec(name: 'bdSeq', type: SpbDataType.int64, generator: const CounterGenerator()),
        );
      expect(kinds(reserved), contains(SimulationIssueKind.sparkplugMetricNameInvalid));
      var mismatch = sparkplugDevice()
        ..sparkplug!.nodeMetrics.add(
          SparkplugMetricSpec(name: 'Level', type: SpbDataType.double, generator: const RandomStringGenerator()),
        );
      expect(kinds(mismatch), contains(SimulationIssueKind.sparkplugGeneratorType));
      // 20 edge nodes with 12 metrics each, 10 scans a second
      var fast = sparkplugDevice(edgeNodes: 20)..sparkplug!.scanMs = 100;
      fast.sparkplug!.devices.first
        ..id = 'Pump{d}'
        ..count = 2;
      expect(kinds(fast), contains(SimulationIssueKind.sparkplugTooManyChanges));
    });
  });
}
