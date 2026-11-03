import 'dart:math';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_commands.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_profile.dart';
import 'package:mqttstudio/simulator/model/sparkplug_source.dart';
import 'package:mqttstudio/simulator/sparkplug/simulated_edge_node.dart';
import 'package:typed_data/typed_buffers.dart';
import '../helpers/fake_broker.dart';

void main() {
  const topics = [
    'spBv1.0/Plant1/NBIRTH/Edge1',
    'spBv1.0/Plant1/DDATA/Edge1/Pump',
    'spBv1.0/Plant1/NDATA/Edge2',
    'spBv1.0/Plant2/NDATA/Edge1',
    'spBv1.0/STATE/scada',
    'plant/temp',
  ];

  test('the edge node of a topic', () {
    expect(SparkplugCommands.edgeNodeOf('spBv1.0/Plant1/DDATA/Edge1/Pump'), SparkplugEdgeNode('Plant1', 'Edge1'));
    expect(SparkplugCommands.edgeNodeOf('spBv1.0/Plant1/NCMD/Edge3'), SparkplugEdgeNode('Plant1', 'Edge3'));
    expect(SparkplugCommands.edgeNodeOf('spBv1.0/STATE/scada'), isNull);
    expect(SparkplugCommands.edgeNodeOf('plant/temp'), isNull);
  });

  test('the edge nodes of a branch', () {
    expect(SparkplugCommands.edgeNodesIn('spBv1.0/Plant1', topics), [
      SparkplugEdgeNode('Plant1', 'Edge1'),
      SparkplugEdgeNode('Plant1', 'Edge2'),
    ]);
    expect(SparkplugCommands.edgeNodesIn('spBv1.0', topics), hasLength(3));
    expect(SparkplugCommands.edgeNodesIn('spBv1.0/Plant1/DDATA', topics), [SparkplugEdgeNode('Plant1', 'Edge1')]);
    expect(SparkplugCommands.edgeNodesIn('spBv1.0/Plant1/NDATA/Edge2', topics), [SparkplugEdgeNode('Plant1', 'Edge2')]);
    expect(SparkplugCommands.edgeNodesIn('spBv1.0/Plant', topics), isEmpty);
    expect(SparkplugCommands.edgeNodesIn('plant', topics), isEmpty);
  });

  test('a rebirth request is an NCMD with Node Control/Rebirth = true by name', () {
    var (topic, payload) = SparkplugCommands.rebirth(SparkplugEdgeNode('Plant1', 'Edge1'));
    expect(topic, 'spBv1.0/Plant1/NCMD/Edge1');
    var read = SparkplugReader.read(payload);
    expect(read.timestamp, isNotNull);
    expect(read.seq, isNull);
    var metric = read.metrics.single;
    expect(metric.name, SparkplugProfile.rebirthMetric);
    expect(metric.type, SpbDataType.boolean);
    expect(metric.value, true);
  });

  test('a simulated edge node answers the request with its births', () {
    fakeAsync((async) {
      var broker = FakeBroker();
      var node = SimulatedEdgeNode(
        SparkplugSource.example()..seed = 1,
        instance: 1,
        settings: MqttSettings('broker', 'edge-1', 1883),
        connectionFactory: broker.newConnection,
        random: Random(1),
        startedAt: DateTime.now(),
      );
      node.start();
      async.elapse(const Duration(seconds: 3));
      var studio = broker.newConnection()..connect(MqttSettings('broker', 'studio', 1883));
      async.flushMicrotasks();
      var (topic, payload) = SparkplugCommands.rebirth(SparkplugEdgeNode('Plant1', 'Edge1'));
      studio.publish(topic, Uint8Buffer()..addAll(payload), MqttPayloadType.binary, false, MqttQos.atMostOnce);
      async.flushMicrotasks();
      expect(broker.messagesOn('spBv1.0/Plant1/NBIRTH/Edge1'), hasLength(2));
      expect(broker.messagesOn('spBv1.0/Plant1/DBIRTH/Edge1/Pump'), hasLength(2));
      node.stop();
    });
  });
}
