import 'dart:convert';
import 'dart:math';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_profile.dart';
import 'package:mqttstudio/simulator/engine/generator_instances.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/sparkplug_source.dart';
import 'package:mqttstudio/simulator/sparkplug/metric_values.dart';
import 'package:mqttstudio/simulator/sparkplug/simulated_edge_node.dart';
import 'package:mqttstudio/simulator/sparkplug/simulated_host.dart';
import 'package:typed_data/typed_buffers.dart';
import '../../helpers/fake_broker.dart';

final _profile = SparkplugProfile();

// the rules of the documentation check over everything the broker routed
List<String> rulesOf(FakeBroker broker) {
  var checker = _profile.createChecker();
  var at = DateTime.utc(2026, 10, 27);
  return [
    for (var message in broker.log)
      if (_profile.matchTopic(message.topic) case var match?)
        for (var finding in checker.check(
          message.topic,
          match,
          match.messageType == SpbMessageType.state ? jsonDecode(message.text) : message.payload,
          at,
        ))
          '${finding.rule} ${message.topic}: ${finding.detail}',
  ];
}

SpbPayload payloadOf(BrokerMessage message) => SparkplugProfile.payloadOf(message.payload)!;

List<BrokerMessage> edgeMessages(FakeBroker broker) =>
    broker.messagesOn('spBv1.0/#').where((message) => !message.topic.contains('/STATE/')).toList();

class _Run {
  final FakeBroker broker = FakeBroker();
  final FakeAsync async;
  late SimulatedEdgeNode node;
  SimulatedHost? host;

  _Run(this.async, SparkplugSource source) {
    node = SimulatedEdgeNode(
      source,
      instance: 1,
      settings: MqttSettings('broker', 'edge-1', 1883),
      connectionFactory: broker.newConnection,
      random: Random(1),
      startedAt: DateTime.now(),
    );
  }

  void start() {
    node.start();
    async.flushMicrotasks();
  }

  void startHost(String id) {
    host = SimulatedHost(
      id,
      settings: MqttSettings('broker', 'host-$id', 1883),
      connectionFactory: broker.newConnection,
    );
    host!.start();
    async.flushMicrotasks();
  }

  void elapse(Duration duration) => async.elapse(duration);

  // a command as a host application or the publish dialog sends it
  void command(String topic, List<SpbMetric> metrics) {
    var sender = broker.newConnection();
    sender.connect(MqttSettings('broker', 'commander', 1883));
    async.flushMicrotasks();
    sender.publish(
      topic,
      Uint8Buffer()..addAll(SparkplugWriter.write(SpbPayload(timestamp: 1, metrics: metrics))),
      MqttPayloadType.binary,
      false,
      MqttQos.atLeastOnce,
    );
    async.flushMicrotasks();
  }

  List<BrokerMessage> on(String filter) => broker.messagesOn(filter);
}

SparkplugSource example({bool aliases = true, int scanMs = 1000}) => SparkplugSource.example()
  ..aliases = aliases
  ..scanMs = scanMs
  ..seed = 1;

void main() {
  group('connect and births', () {
    test('the will is the NDEATH with bdSeq 0, then NBIRTH and DBIRTH define every metric', () {
      fakeAsync((async) {
        var run = _Run(async, example())..start();
        var connection = run.broker.connectionOf('edge-1')!;
        var will = connection.will!;
        expect(will.topic, 'spBv1.0/Plant1/NDEATH/Edge1');
        expect(will.qos, MqttQos.atLeastOnce);
        expect(will.retain, isFalse);
        expect(SparkplugReader.read(will.payload).metric('bdSeq')!.value, 0);
        expect(connection.subscriptions, ['spBv1.0/Plant1/NCMD/Edge1', 'spBv1.0/Plant1/DCMD/Edge1/+']);

        var messages = edgeMessages(run.broker);
        expect(messages.map((message) => message.topic).take(2), [
          'spBv1.0/Plant1/NBIRTH/Edge1',
          'spBv1.0/Plant1/DBIRTH/Edge1/Pump',
        ]);
        var birth = payloadOf(messages[0]);
        expect(birth.seq, 0);
        expect(birth.timestamp, isNotNull);
        expect(birth.metric('bdSeq')!.value, 0);
        expect(birth.metric('Node Control/Rebirth')!.value, false);
        expect(birth.metrics.map((metric) => metric.name), ['bdSeq', 'Node Control/Rebirth', 'Uptime', 'Firmware']);
        expect(birth.metrics.every((metric) => metric.datatype != null), isTrue);
        var pump = payloadOf(messages[1]);
        expect(pump.seq, 1);
        var temperature = pump.metric('Temperature')!;
        expect(temperature.type, SpbDataType.double);
        expect(temperature.properties!.values['engUnit']!.value, '°C');
        expect(temperature.alias, isNotNull);
        expect(run.node.state, EdgeNodeState.online);
        run.node.stop();
      });
    });

    test('a clean run gives no findings; data is by alias, by exception, QoS 0 and not retained', () {
      fakeAsync((async) {
        var run = _Run(async, example())..start();
        run.elapse(const Duration(minutes: 2));
        run.node.stop();
        async.flushMicrotasks();
        expect(rulesOf(run.broker), isEmpty);

        var data = run.on('spBv1.0/Plant1/+/Edge1/#').where((message) => message.topic.contains('DATA')).toList();
        expect(data, isNotEmpty);
        for (var message in data) {
          expect(message.qos, MqttQos.atMostOnce);
          expect(message.retain, isFalse);
          for (var metric in payloadOf(message).metrics) {
            expect(metric.name, isNull);
            expect(metric.alias, isNotNull);
            expect(metric.datatype, isNull);
            expect(metric.value, isNotNull);
          }
        }
        // the firmware never changes, so it is only in the birth
        var nodeData = run.on('spBv1.0/Plant1/NDATA/Edge1').map(payloadOf);
        var firmwareAlias = payloadOf(run.on('spBv1.0/Plant1/NBIRTH/Edge1').single).metric('Firmware')!.alias;
        expect(nodeData.expand((payload) => payload.metrics).where((metric) => metric.alias == firmwareAlias), isEmpty);
      });
    });

    test('without aliases data carries names and data types', () {
      fakeAsync((async) {
        var run = _Run(async, example(aliases: false))..start();
        run.elapse(const Duration(seconds: 30));
        var data = run.on('spBv1.0/Plant1/DDATA/Edge1/Pump').map(payloadOf).expand((payload) => payload.metrics);
        expect(data, isNotEmpty);
        expect(data.every((metric) => metric.name != null && metric.alias == null && metric.datatype != null), isTrue);
        expect(rulesOf(run.broker), isEmpty);
        run.node.stop();
      });
    });

    test('seq counts over all messages of the edge node and wraps after 255', () {
      fakeAsync((async) {
        var run = _Run(async, example(scanMs: 100))..start();
        run.elapse(const Duration(minutes: 1));
        var seqs = edgeMessages(run.broker).map((message) => payloadOf(message).seq!).toList();
        expect(seqs.length, greaterThan(300));
        for (var i = 1; i < seqs.length; i++) {
          expect(seqs[i], (seqs[i - 1] + 1) % 256);
        }
        expect(rulesOf(run.broker), isEmpty);
        run.node.stop();
      });
    });

    test('compressed payloads are read like the others', () {
      fakeAsync((async) {
        var run = _Run(async, example()..compress = true)..start();
        run.elapse(const Duration(seconds: 20));
        var raw = SparkplugReader.read(run.on('spBv1.0/Plant1/NBIRTH/Edge1').single.payload);
        expect(raw.uuid, SparkplugProfile.compressedUuid);
        expect(payloadOf(run.on('spBv1.0/Plant1/NBIRTH/Edge1').single).metric('bdSeq')!.value, 0);
        expect(rulesOf(run.broker), isEmpty);
        run.node.stop();
      });
    });
  });

  group('session', () {
    test('a dropped connection makes the broker send the will, the next connection counts bdSeq up', () {
      fakeAsync((async) {
        var run = _Run(async, example())..start();
        run.elapse(const Duration(seconds: 5));
        run.broker.connectionOf('edge-1')!.drop();
        async.flushMicrotasks();
        expect(run.node.state, EdgeNodeState.reconnecting);
        var death = run.on('spBv1.0/Plant1/NDEATH/Edge1').single;
        expect(death.isWill, isTrue);
        expect(payloadOf(death).metric('bdSeq')!.value, 0);

        run.elapse(const Duration(seconds: 2));
        expect(run.node.state, EdgeNodeState.online);
        var births = run.on('spBv1.0/Plant1/NBIRTH/Edge1').map(payloadOf).toList();
        expect(births.map((birth) => birth.metric('bdSeq')!.value), [0, 1]);
        expect(births.last.seq, 0);
        expect(SparkplugReader.read(run.broker.connectionOf('edge-1')!.will!.payload).metric('bdSeq')!.value, 1);
        run.elapse(const Duration(seconds: 10));
        expect(rulesOf(run.broker), isEmpty);
        run.node.stop();
      });
    });

    test('a stop publishes the NDEATH itself and disconnects cleanly', () {
      fakeAsync((async) {
        var run = _Run(async, example())..start();
        run.elapse(const Duration(seconds: 3));
        run.node.stop();
        async.flushMicrotasks();
        var death = run.on('spBv1.0/Plant1/NDEATH/Edge1').single;
        expect(death.isWill, isFalse);
        expect(death.from, 'edge-1');
        expect(payloadOf(death).metric('bdSeq')!.value, 0);
        expect(run.broker.online, isEmpty);
        expect(run.node.state, EdgeNodeState.stopped);
        run.elapse(const Duration(seconds: 10));
        expect(edgeMessages(run.broker).last.topic, 'spBv1.0/Plant1/NDEATH/Edge1');
      });
    });

    test('with a primary host the birth waits for its STATE, a lost host means NDEATH and a new connection', () {
      fakeAsync((async) {
        var run = _Run(async, example()..primaryHostId = 'scada')..start();
        run.elapse(const Duration(seconds: 5));
        expect(run.node.state, EdgeNodeState.waitingForHost);
        expect(run.on('spBv1.0/Plant1/NBIRTH/Edge1'), isEmpty);
        expect(run.broker.connectionOf('edge-1')!.subscriptions, contains('spBv1.0/STATE/scada'));

        run.startHost('scada');
        expect(run.node.state, EdgeNodeState.online);
        expect(run.on('spBv1.0/Plant1/NBIRTH/Edge1'), hasLength(1));
        run.elapse(const Duration(seconds: 5));

        // the host shuts down: the edge node leaves and waits for it on a new connection
        run.host!.stop();
        async.flushMicrotasks();
        expect(run.on('spBv1.0/Plant1/NDEATH/Edge1').single.isWill, isFalse);
        run.elapse(const Duration(seconds: 2));
        expect(run.node.state, EdgeNodeState.waitingForHost);
        expect(run.node.bdSeq, 1);

        run.startHost('scada');
        expect(run.node.state, EdgeNodeState.online);
        var births = run.on('spBv1.0/Plant1/NBIRTH/Edge1').map(payloadOf).toList();
        expect(births.map((birth) => birth.metric('bdSeq')!.value), [0, 1]);
        run.elapse(const Duration(seconds: 5));
        expect(rulesOf(run.broker), isEmpty);
        run.node.stop();
      });
    });

    test('an older STATE than the last one is ignored', () {
      fakeAsync((async) {
        var run = _Run(async, example()..primaryHostId = 'scada')..start();
        run.startHost('scada');
        var host = run.broker.newConnection()..connect(MqttSettings('broker', 'old-host', 1883));
        async.flushMicrotasks();
        host.publish(
          'spBv1.0/STATE/scada',
          Uint8Buffer()..addAll(utf8.encode('{"online": false, "timestamp": 1}')),
          MqttPayloadType.binary,
          false,
          MqttQos.atLeastOnce,
        );
        async.flushMicrotasks();
        expect(run.node.state, EdgeNodeState.online);
        run.node.stop();
      });
    });
  });

  group('commands and devices', () {
    test('a rebirth request gives a new NBIRTH with seq 0 and the same bdSeq, then the DBIRTHs', () {
      fakeAsync((async) {
        var run = _Run(async, example())..start();
        run.elapse(const Duration(seconds: 5));
        run.command('spBv1.0/Plant1/NCMD/Edge1', [
          SpbMetric(name: 'Node Control/Rebirth', datatype: SpbDataType.boolean.code, value: true),
        ]);
        var births = run.on('spBv1.0/Plant1/NBIRTH/Edge1').map(payloadOf).toList();
        expect(births, hasLength(2));
        expect(births.last.seq, 0);
        expect(births.last.metric('bdSeq')!.value, 0);
        expect(run.on('spBv1.0/Plant1/DBIRTH/Edge1/Pump'), hasLength(2));
        // by alias 0 as well
        run.command('spBv1.0/Plant1/NCMD/Edge1', [SpbMetric(alias: 0, value: true)]);
        expect(run.on('spBv1.0/Plant1/NBIRTH/Edge1'), hasLength(3));
        run.elapse(const Duration(seconds: 5));
        expect(rulesOf(run.broker), isEmpty);
        run.node.stop();
      });
    });

    test('a write sets a writable metric and holds it, other metrics ignore writes', () {
      fakeAsync((async) {
        var run = _Run(async, example())..start();
        run.elapse(const Duration(seconds: 2));
        var pumpBirth = payloadOf(run.on('spBv1.0/Plant1/DBIRTH/Edge1/Pump').single);
        var running = pumpBirth.metric('Running')!.alias;
        var temperature = pumpBirth.metric('Temperature')!.alias;
        var before = run.on('spBv1.0/Plant1/DDATA/Edge1/Pump').length;
        run.command('spBv1.0/Plant1/DCMD/Edge1/Pump', [
          SpbMetric(name: 'Running', datatype: SpbDataType.boolean.code, value: false),
          SpbMetric(name: 'Temperature', datatype: SpbDataType.double.code, value: 99.0),
        ]);
        var answer = payloadOf(run.on('spBv1.0/Plant1/DDATA/Edge1/Pump')[before]);
        expect(answer.metrics.map((metric) => (metric.alias, metric.value)), [(running, false)]);

        run.elapse(const Duration(minutes: 2));
        var later = run.on('spBv1.0/Plant1/DDATA/Edge1/Pump').skip(before + 1).map(payloadOf);
        expect(later.expand((payload) => payload.metrics).where((metric) => metric.alias == running), isEmpty);
        expect(later.expand((payload) => payload.metrics).where((metric) => metric.alias == temperature), isNotEmpty);
        expect(rulesOf(run.broker), isEmpty);
        run.node.stop();
      });
    });

    test('a device goes offline with DDEATH and comes back with DBIRTH', () {
      fakeAsync((async) {
        var run = _Run(async, example())..start();
        run.elapse(const Duration(seconds: 3));
        run.node.setDeviceOnline('Pump', false);
        run.elapse(const Duration(seconds: 10));
        expect(run.on('spBv1.0/Plant1/DDEATH/Edge1/Pump'), hasLength(1));
        var afterDeath = run
            .on('spBv1.0/Plant1/+/Edge1/Pump')
            .skipWhile((message) => !message.topic.contains('DDEATH'));
        expect(afterDeath.skip(1), isEmpty);
        run.node.setDeviceOnline('Pump', true);
        run.elapse(const Duration(seconds: 10));
        expect(run.on('spBv1.0/Plant1/DBIRTH/Edge1/Pump'), hasLength(2));
        expect(rulesOf(run.broker), isEmpty);
        run.node.stop();
      });
    });

    test('several devices from one spec with {d}', () {
      fakeAsync((async) {
        var source = example()..devices.first.id = 'Pump{d}';
        source.devices.first.count = 3;
        var run = _Run(async, source)..start();
        expect(run.node.deviceIds, ['Pump1', 'Pump2', 'Pump3']);
        expect(run.on('spBv1.0/Plant1/DBIRTH/Edge1/+'), hasLength(3));
        run.elapse(const Duration(seconds: 10));
        expect(rulesOf(run.broker), isEmpty);
        run.node.stop();
      });
    });
  });

  group('the simulated host', () {
    test('publishes a retained STATE and leaves the offline STATE as retained will', () {
      fakeAsync((async) {
        var broker = FakeBroker();
        var host = SimulatedHost(
          'scada',
          settings: MqttSettings('b', 'host', 1883),
          connectionFactory: broker.newConnection,
        );
        host.start();
        async.flushMicrotasks();
        var online = jsonDecode(broker.retained['spBv1.0/STATE/scada']!.text) as Map;
        expect(online['online'], isTrue);
        var will = broker.connectionOf('host')!.will!;
        expect(will.retain, isTrue);
        var offline = jsonDecode(utf8.decode(will.payload)) as Map;
        expect(offline, {'online': false, 'timestamp': online['timestamp']});
        broker.connectionOf('host')!.drop();
        expect(jsonDecode(broker.retained['spBv1.0/STATE/scada']!.text)['online'], isFalse);
      });
    });
  });

  group('values', () {
    var now = DateTime.utc(2026, 10, 27);
    Object? convert(String text, SpbDataType type, [PayloadGenerator generator = const RandomNumberGenerator()]) =>
        SparkplugValues.fromGenerated(
          GeneratedValue.text(text),
          SparkplugMetricSpec(name: 'm', type: type, generator: generator),
          now,
        );

    test('generated texts become typed values', () {
      expect(convert('21.46', SpbDataType.double), 21.46);
      expect(convert('300', SpbDataType.int8), 127);
      expect(convert('-5.6', SpbDataType.uInt16), 0);
      expect(convert('41.5', SpbDataType.int32), 42);
      expect(convert('abc', SpbDataType.int32), isNull);
      expect(convert('t°12 C', SpbDataType.float, const RandomNumberGenerator(prefix: 't°', postfix: ' C')), 12.0);
      expect(convert('an', SpbDataType.boolean, const BoolGenerator(trueText: 'an', falseText: 'aus')), true);
      expect(convert('AUTO', SpbDataType.string, const ValueListGenerator()), 'AUTO');
      expect(convert('x', SpbDataType.dateTime, const TimestampGenerator()), now);
    });

    test('writes are coerced to the type, changes respect the deadband', () {
      expect(SparkplugValues.coerce(1, SpbDataType.boolean), true);
      expect(SparkplugValues.coerce(1500.4, SpbDataType.int32), 1500);
      expect(SparkplugValues.coerce('2.5', SpbDataType.float), 2.5);
      expect(SparkplugValues.coerce('x', SpbDataType.int32), isNull);
      var spec = SparkplugMetricSpec(
        name: 'm',
        type: SpbDataType.double,
        generator: const RandomNumberGenerator(),
        deadband: 0.5,
      );
      expect(SparkplugValues.changed(20.0, 20.4, spec), isFalse);
      expect(SparkplugValues.changed(20.0, 20.6, spec), isTrue);
      expect(SparkplugValues.changed('A', 'B', spec), isTrue);
    });

    test('the example survives the JSON round trip', () {
      var copy = SparkplugSource.example().copy();
      expect(copy.devices.single.metrics.map((metric) => metric.name), [
        'Temperature',
        'Pressure',
        'Running',
        'Speed',
        'Mode',
      ]);
      expect(copy.devices.single.metrics.first.generator, isA<WaveGenerator>());
      expect(copy.nodeMetrics.first.type, SpbDataType.uInt64);
      expect(copy.devices.single.metrics[2].writable, isTrue);
    });
  });
}
