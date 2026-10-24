import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';

// round trip through a JSON string, as the local store does
Simulation roundTrip(Simulation simulation) =>
    Simulation.fromJson(jsonDecode(jsonEncode(simulation.toJson())) as Map<String, dynamic>);

void main() {
  test('every generator type survives a round trip', () {
    var generators = <PayloadGenerator>[
      const RandomStringGenerator(minLength: 1, maxLength: 2, charSet: 'xy', prefix: 'p', postfix: 's'),
      const RandomNumberGenerator(min: -5, max: 5, decimals: 2),
      const CounterGenerator(start: 3, step: 2, resetAfter: 10, prefix: 'ORD-'),
      const BoolGenerator(trueProbability: 0.2, trueText: 'ON', falseText: 'OFF'),
      const ValueListGenerator(values: ['a,b', 'c;d'], order: PickOrder.sequential),
      const RandomWalkGenerator(start: 1, min: -1, max: 2, volatility: 0.1, decimals: 3),
      const WaveGenerator(shape: WaveShape.triangle, offset: 1, amplitude: 2, periodSeconds: 30, phaseDegrees: 90, noise: 0.1),
      const TimestampGenerator(format: TimestampFormat.pattern, pattern: 'HH:mm', utc: false),
      const GpsTrackGenerator(
          mode: GpsMode.route, waypoints: [GpsPoint(1, 2), GpsPoint(3, 4)], speedMps: 5, format: GpsFormat.json),
      const RandomImageGenerator(folderPath: r'D:\images', extensions: ['.png'], order: PickOrder.sequential),
      TemplateGenerator(template: '{{a}}', fields: {'a': const CounterGenerator(start: 7)}, validateJson: false),
    ];
    expect(generators.map((g) => g.type).toSet(), GeneratorType.values.toSet());

    var device = SimulatedDevice(name: 'Dev', instanceCount: 3, firstInstance: 4, topics: [
      for (var g in generators) SimulatedTopic(topic: 't/{n}/${g.type.key}', generator: g),
    ]);
    device.topics.first
      ..qos = MqttQos.exactlyOnce
      ..retain = true
      ..interval = PublishInterval(minMs: 200, maxMs: 900)
      ..mqtt5 = Mqtt5PublishProperties(
          contentType: 'text/plain', messageExpirySeconds: 60, userProperties: [SimulatedUserProperty('k', '{n}')]);

    var copy = roundTrip(Simulation(devices: [device]));
    expect(jsonEncode(copy.toJson()), jsonEncode(Simulation(devices: [device]).toJson()));

    var copied = copy.devices.single;
    expect(copied.id, device.id);
    expect(copied.instanceCount, 3);
    expect(copied.firstInstance, 4);
    expect(copied.topics.first.qos, MqttQos.exactlyOnce);
    expect(copied.topics.first.interval.isRandom, isTrue);
    expect(copied.topics.first.mqtt5.userProperties.single.value, '{n}');
    var template = copied.topics.last.generator as TemplateGenerator;
    expect((template.fields['a'] as CounterGenerator).start, 7);
    var gps = copied.topics[8].generator as GpsTrackGenerator;
    expect(gps.waypoints.last.lon, 4);
  });

  test('missing parameters get their defaults', () {
    var walk = PayloadGenerator.fromJson({'type': 'randomWalk', 'start': 5}) as RandomWalkGenerator;
    expect(walk.start, 5);
    expect(walk.max, 40);
    expect(walk.volatility, 0.5);
    var topic = SimulatedTopic.fromJson(jsonDecode('{"id": "x", "topic": "a", "qos": "atMostOnce", "retain": false, '
        '"interval": {"minMs": 500}, "mqtt5": {}, "generator": {"type": "bool"}}') as Map<String, dynamic>);
    expect(topic.interval.maxMs, 500);
    expect(topic.generator, isA<BoolGenerator>());
  });

  test('an unknown generator type is a FormatException', () {
    expect(() => PayloadGenerator.fromJson({'type': 'nope'}), throwsFormatException);
  });

  test('a project saved before the simulator existed loads with a Default device', () {
    var project = Project(MqttSettings('h', 'c', 1883), name: 'Old');
    var json = jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>;
    json.remove('simulation');

    var loaded = Project.fromJson(json);
    expect(loaded.simulation.devices.single.name, SimulatedDevice.defaultName);
    expect(loaded.simulation.devices.single.topics, isEmpty);
  });

  test('the simulation is saved with the project', () {
    var project = Project(MqttSettings('h', 'c', 1883));
    project.simulation.devices.first.topics.add(SimulatedTopic(topic: 'a', generator: const CounterGenerator()));
    var loaded = Project.fromJson(jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>);
    expect(loaded.simulation.devices.first.topics.single.topic, 'a');
    expect(loaded.getHash(), project.getHash());
  });

  test('copies get new ids only when asked', () {
    var device = SimulatedDevice(name: 'd', topics: [SimulatedTopic(topic: 'a', generator: const CounterGenerator())]);
    expect(device.copy().topics.single.id, device.topics.single.id);
    var duplicate = device.copy(newIds: true);
    expect(duplicate.id, isNot(device.id));
    expect(duplicate.topics.single.id, isNot(device.topics.single.id));
    expect(duplicate.topics.single.topic, 'a');
  });
}
