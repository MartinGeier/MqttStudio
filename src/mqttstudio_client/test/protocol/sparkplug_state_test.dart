import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_profile.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_state.dart';
import 'package:mqttstudio/simulator/model/sparkplug_source.dart';
import 'package:mqttstudio/simulator/sparkplug/simulated_edge_node.dart';
import 'package:mqttstudio/simulator/sparkplug/simulated_host.dart';
import '../helpers/fake_broker.dart';

final _profile = SparkplugProfile();
final _start = DateTime.utc(2026, 10, 27, 12);

Uint8List _payload({int? seq, List<SpbMetric> metrics = const []}) =>
    SparkplugWriter.write(SpbPayload(timestamp: 1761566400000, seq: seq, metrics: metrics));

SpbMetric _defined(String name, int alias, SpbDataType type, Object value, {String? unit}) => SpbMetric(
  name: name,
  alias: alias,
  datatype: type.code,
  value: value,
  properties: SpbPropertySet({
    if (unit != null) 'engUnit': SpbPropertyValue(type: SpbDataType.string.code, value: unit),
    'Quality': SpbPropertyValue(type: SpbDataType.int32.code, value: 192),
  }),
);

void main() {
  late SparkplugState<String> state;
  var second = 0;

  bool add(String topic, Object? data) {
    second++;
    return state.add(_profile.matchTopic(topic)!, data, _start.add(Duration(seconds: second)), topic);
  }

  setUp(() {
    state = SparkplugState<String>();
    second = 0;
  });

  test('a birth defines the metrics, data updates them by alias with the type of the birth', () {
    add(
      'spBv1.0/Plant1/NBIRTH/Edge1',
      _payload(
        seq: 0,
        metrics: [
          SpbMetric(name: 'bdSeq', datatype: SpbDataType.int64.code, value: 3),
          _defined('Temperature', 2, SpbDataType.double, 20.0, unit: '°C'),
          _defined('Offset', 3, SpbDataType.int32, 0),
        ],
      ),
    );
    var node = state.node('Plant1', 'Edge1')!;
    expect(node.status, SparkplugStatus.online);
    expect(node.bdSeq, 3);
    expect(node.metrics.keys, ['bdSeq', 'Temperature', 'Offset']);
    var temperature = node.metrics['Temperature']!;
    expect(temperature.unit, '°C');
    expect(temperature.properties, {'Quality': '192'});

    add(
      'spBv1.0/Plant1/NDATA/Edge1',
      _payload(
        seq: 1,
        metrics: [
          SpbMetric(alias: 2, value: 21.5, encodeAs: SpbDataType.double),
          SpbMetric(alias: 3, value: -5, encodeAs: SpbDataType.int32),
        ],
      ),
    );
    add(
      'spBv1.0/Plant1/NDATA/Edge1',
      _payload(seq: 2, metrics: [SpbMetric(alias: 2, value: 21.5, encodeAs: SpbDataType.double)]),
    );
    expect(temperature.value, 21.5);
    expect(temperature.formattedValue, '21.5');
    expect(temperature.changes, 1);
    expect(temperature.message, 'spBv1.0/Plant1/NDATA/Edge1');
    expect(node.metrics['Offset']!.value, -5);
    expect(node.lastSeq, 2);
    expect(node.seqGaps, 0);
    expect(node.messages, 3);
  });

  test('devices, deaths, seq gaps and a rebirth that replaces the metrics', () {
    add('spBv1.0/Plant1/NBIRTH/Edge1', _payload(seq: 0, metrics: [_defined('Uptime', 1, SpbDataType.uInt64, 1)]));
    add(
      'spBv1.0/Plant1/DBIRTH/Edge1/Pump',
      _payload(seq: 1, metrics: [_defined('Pressure', 10, SpbDataType.float, 2.5)]),
    );
    add(
      'spBv1.0/Plant1/DDATA/Edge1/Pump',
      _payload(seq: 3, metrics: [SpbMetric(alias: 10, value: 2.75, encodeAs: SpbDataType.float)]),
    );
    var node = state.node('Plant1', 'Edge1')!;
    var pump = state.entry('Plant1/Edge1/Pump')!;
    expect(pump.status, SparkplugStatus.online);
    expect(pump.metrics['Pressure']!.value, 2.75);
    expect(node.seqGaps, 1);

    add('spBv1.0/Plant1/DDEATH/Edge1/Pump', _payload(seq: 4));
    expect(pump.status, SparkplugStatus.offline);
    add(
      'spBv1.0/Plant1/DBIRTH/Edge1/Pump',
      _payload(seq: 5, metrics: [_defined('Pressure', 10, SpbDataType.float, 2.5)]),
    );
    add(
      'spBv1.0/Plant1/NDEATH/Edge1',
      _payload(
        metrics: [SpbMetric(name: 'bdSeq', datatype: SpbDataType.int64.code, value: 0)],
      ),
    );
    expect(node.status, SparkplugStatus.offline);
    expect(pump.status, SparkplugStatus.offline);

    add('spBv1.0/Plant1/NBIRTH/Edge1', _payload(seq: 0, metrics: [_defined('Version', 1, SpbDataType.string, 'v2')]));
    expect(node.status, SparkplugStatus.online);
    expect(node.metrics.keys, ['Version']);
  });

  test('data without a birth leaves the edge node unknown and its metrics by alias', () {
    add(
      'spBv1.0/Plant1/NDATA/Edge2',
      _payload(seq: 7, metrics: [SpbMetric(alias: 4, value: 1.5, encodeAs: SpbDataType.double)]),
    );
    add(
      'spBv1.0/Plant1/DDATA/Edge2/Valve',
      _payload(
        seq: 8,
        metrics: [SpbMetric(name: 'Open', datatype: SpbDataType.boolean.code, value: true)],
      ),
    );
    var node = state.node('Plant1', 'Edge2')!;
    expect(node.status, SparkplugStatus.unknown);
    expect(node.metrics['alias 4']!.unknown, isTrue);
    var valve = state.entry('Plant1/Edge2/Valve')!;
    expect(valve.status, SparkplugStatus.unknown);
    expect(valve.metrics['Open']!.unknown, isFalse);
  });

  test('host applications, commands and payloads that are not Sparkplug', () {
    add('spBv1.0/STATE/scada', {'online': true, 'timestamp': 1});
    add('STATE/old', Uint8List.fromList(utf8.encode('OFFLINE')));
    expect(state.hosts.map((host) => (host.hostId, host.online)), [('old', false), ('scada', true)]);
    expect(add('spBv1.0/Plant1/NCMD/Edge1', _payload()), isFalse);
    expect(add('spBv1.0/Plant1/NDATA/Edge1', {'json': true}), isFalse);
    expect(state.node('Plant1', 'Edge1')?.messages ?? 0, 0);
    expect(state.groups, ['Plant1']);
  });

  test('simulated edge nodes and their host fold into the state', () {
    fakeAsync((async) {
      var broker = FakeBroker();
      var host = SimulatedHost(
        'scada',
        settings: MqttSettings('b', 'host', 1883),
        connectionFactory: broker.newConnection,
      )..start();
      var nodes = [
        for (var n = 1; n <= 2; n++)
          SimulatedEdgeNode(
            SparkplugSource.example()
              ..seed = n
              ..primaryHostId = 'scada',
            instance: n,
            settings: MqttSettings('b', 'edge-$n', 1883),
            connectionFactory: broker.newConnection,
            random: Random(n),
            startedAt: DateTime.now(),
          )..start(),
      ];
      async.elapse(const Duration(seconds: 30));
      for (var message in broker.log) {
        var match = _profile.matchTopic(message.topic);
        if (match != null) {
          var data = match.messageType == SpbMessageType.state ? jsonDecode(message.text) : message.payload;
          state.add(match, data, DateTime.now(), message.topic);
        }
      }
      expect(state.hosts.single.online, isTrue);
      expect(state.nodes.map((node) => node.edgeNode), ['Edge1', 'Edge2']);
      for (var node in state.nodes) {
        expect(node.status, SparkplugStatus.online);
        expect(node.seqGaps, 0);
        var pump = node.devices['Pump']!;
        expect(pump.status, SparkplugStatus.online);
        expect(pump.metrics.keys, containsAll(['Temperature', 'Pressure', 'Running', 'Speed', 'Mode']));
        expect(pump.metrics['Temperature']!.changes, greaterThan(0));
        expect(pump.metrics.values.every((metric) => !metric.unknown), isTrue);
      }
      for (var node in nodes) {
        node.stop();
      }
      host.stop();
    });
  });
}
