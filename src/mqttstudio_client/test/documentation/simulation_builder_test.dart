import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/engine/simulation_builder.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';

DocNode topic(String path, PayloadSpec payload,
        {List<DocParameter> parameters = const [], IntervalSpec? interval, MqttQos? qos, RetainMode? retain}) =>
    DocNode(
        path: path,
        parameters: parameters,
        topic: TopicSpec(
            qos: qos, retain: retain ?? RetainMode.never, interval: interval ?? IntervalSpec(), payload: payload));

void main() {
  test('the first parameter becomes {n}, the others take their first example', () {
    var node = topic('plant/{line}/m{machine}/temp', PayloadSpec(format: PayloadFormat.number, min: 0, max: 120),
        parameters: [
          DocParameter(name: 'line', examples: ['3', '4', '5']),
          DocParameter(name: 'machine', examples: ['7', '8']),
        ],
        interval: IntervalSpec(kind: IntervalKind.periodic, nominalMs: 10000),
        qos: MqttQos.atLeastOnce,
        retain: RetainMode.always);
    var device = SimulationBuilder.deviceOf(node, 'Temp');
    expect(device.name, 'Temp');
    expect(device.instanceCount, 3);
    expect(device.firstInstance, 3);
    var simulated = device.topics.single;
    expect(simulated.topic, 'plant/{n}/m7/temp');
    expect(simulated.qos, MqttQos.atLeastOnce);
    expect(simulated.retain, isTrue);
    expect(simulated.interval.minMs, 10000);
    expect(simulated.interval.isRandom, isFalse);
    var generator = simulated.generator as RandomWalkGenerator;
    expect([generator.min, generator.max, generator.decimals], [0, 120, 0]);
    expect(SimulationRules.validateSimulation(Simulation(devices: [device])), isEmpty);
  });

  test('allowed values, booleans and event intervals', () {
    var mode = topic('plant/mode', PayloadSpec(format: PayloadFormat.string, allowedValues: ['auto', 'manual']),
        interval: IntervalSpec(kind: IntervalKind.event, nominalMs: 20));
    var device = SimulationBuilder.deviceOf(mode, 'Mode');
    expect(device.instanceCount, 1);
    expect((device.topics.single.generator as ValueListGenerator).values, ['auto', 'manual']);
    // at least the simulator's minimum, up to three times the nominal interval
    expect(device.topics.single.interval.minMs, SimulationRules.minIntervalMs);
    expect(device.topics.single.interval.maxMs, 60);
    expect(SimulationBuilder.generatorOf(topic('plant/on', PayloadSpec(format: PayloadFormat.boolean))),
        isA<BoolGenerator>());
  });

  test('a JSON schema becomes a template with a field per value', () {
    var node = topic(
        'plant/state',
        PayloadSpec(
            format: PayloadFormat.json,
            schema: SchemaNode(properties: {
              'state': SchemaNode(type: SchemaType.string, enumValues: ['idle', 'running']),
              'temp': SchemaNode(type: SchemaType.number, minimum: 10, maximum: 90.5),
              'at': SchemaNode(type: SchemaType.string, format: 'date-time'),
              'alarm': SchemaNode(type: SchemaType.boolean),
              'axis': SchemaNode(properties: {'x': SchemaNode(type: SchemaType.integer)}),
            })));
    var generator = SimulationBuilder.generatorOf(node) as TemplateGenerator;
    expect(generator.fields.keys, unorderedEquals(['state', 'temp', 'at', 'alarm', 'axis_x']));
    expect(generator.fields['state'], isA<ValueListGenerator>());
    expect(generator.fields['temp'], isA<RandomWalkGenerator>());
    expect(generator.fields['at'], isA<TimestampGenerator>());
    // with every field filled in, the template is valid JSON
    var filled = generator.template.replaceAll(RegExp(r'\{\{\w+\}\}'), '1');
    expect((jsonDecode(filled) as Map)['axis'], {'x': 1});
  });
}
