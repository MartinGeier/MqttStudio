import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/simulator/engine/placeholders.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';

void main() {
  group('Placeholders', () {
    test('resolves {n}, {n:3} and {device}', () {
      expect(Placeholders.resolve('weather/{n}/temp', instance: 7, deviceName: 'x'), 'weather/7/temp');
      expect(Placeholders.resolve('ws-{n:3}', instance: 7, deviceName: 'x'), 'ws-007');
      expect(Placeholders.resolve('ws-{n:2}', instance: 123, deviceName: 'x'), 'ws-123');
      expect(Placeholders.resolve('{device}/{n}', instance: 1, deviceName: 'Line 1/a+b#'), 'Line 1_a_b_/1');
      expect(Placeholders.resolve('no placeholders', instance: 1, deviceName: 'x'), 'no placeholders');
    });

    test('containsInstance', () {
      expect(Placeholders.containsInstance('a/{n}'), isTrue);
      expect(Placeholders.containsInstance('a/{n:4}'), isTrue);
      expect(Placeholders.containsInstance('a/{device}'), isFalse);
    });

    test('toSubscription replaces levels with an instance number by +', () {
      expect(Placeholders.toSubscription('weather/{n}/temp', deviceName: 'x'), 'weather/+/temp');
      expect(Placeholders.toSubscription('weather/ws-{n:3}/temp', deviceName: 'x'), 'weather/+/temp');
      expect(Placeholders.toSubscription('{device}/state', deviceName: 'Line 1'), 'Line 1/state');
      expect(Placeholders.toSubscription('plain/topic', deviceName: 'x'), 'plain/topic');
    });
  });

  group('SimulationRules', () {
    SimulatedTopic topic(String name, {int min = 1000, int? max, PayloadGenerator? generator}) => SimulatedTopic(
        topic: name, generator: generator ?? const CounterGenerator(), interval: PublishInterval(minMs: min, maxMs: max));

    test('a valid topic has no issues', () {
      var device = SimulatedDevice(name: 'd', instanceCount: 10);
      expect(SimulationRules.validateTopic(device, topic('a/{n}/b')), isEmpty);
    });

    test('topic rules', () {
      var single = SimulatedDevice(name: 'd');
      var many = SimulatedDevice(name: 'd', instanceCount: 2);
      List<SimulationIssueKind> kinds(SimulatedDevice device, SimulatedTopic topic) =>
          SimulationRules.validateTopic(device, topic).map((issue) => issue.kind).toList();

      expect(kinds(single, topic(' ')), [SimulationIssueKind.topicEmpty]);
      expect(kinds(single, topic('a/+/b')), [SimulationIssueKind.topicWildcard]);
      expect(kinds(single, topic('a/#')), [SimulationIssueKind.topicWildcard]);
      expect(kinds(many, topic('a/b')), [SimulationIssueKind.topicNeedsInstance]);
      expect(kinds(single, topic('a', min: 10)), [SimulationIssueKind.intervalTooShort]);
      expect(kinds(single, topic('a', min: 1000, max: 500)), [SimulationIssueKind.intervalRange]);
      expect(
          kinds(single, topic('a', generator: const GpsTrackGenerator(mode: GpsMode.route))), [SimulationIssueKind.routeTooShort]);
    });

    test('template rules', () {
      var device = SimulatedDevice(name: 'd');
      var issues = SimulationRules.validateTopic(
          device,
          topic('a',
              generator: TemplateGenerator(
                  template: '{{a}} {{b.c}} {{img}}', fields: {'a': const CounterGenerator(), 'img': const RandomImageGenerator()})));
      expect(issues.map((issue) => (issue.kind, issue.detail)), [
        (SimulationIssueKind.templateUnknownField, 'b'),
        (SimulationIssueKind.templateFieldNotAllowed, 'img'),
      ]);
    });

    test('device rules: name, duplicates ignoring case, instance count', () {
      var a = SimulatedDevice(name: 'Line');
      var b = SimulatedDevice(name: 'line ');
      var simulation = Simulation(devices: [a, b]);
      expect(SimulationRules.validateDevice(b, simulation).map((issue) => issue.kind),
          [SimulationIssueKind.deviceNameDuplicate]);
      expect(SimulationRules.validateDevice(SimulatedDevice(name: ''), simulation).map((issue) => issue.kind),
          [SimulationIssueKind.deviceNameEmpty]);
      expect(
          SimulationRules.validateDevice(SimulatedDevice(name: 'x', instanceCount: 1001), simulation)
              .map((issue) => issue.kind),
          [SimulationIssueKind.instanceCount]);
    });

    test('rate estimate: instances × 1000 / average interval', () {
      var device = SimulatedDevice(name: 'd', instanceCount: 10);
      var fixed = topic('a/{n}', min: 1000);
      var random = topic('b/{n}', min: 2000, max: 4000);
      expect(SimulationRules.estimateRate([(device, fixed), (device, random)]), closeTo(10 + 10 / 3, 1e-9));
    });

    test('resolvedTopics lists every instance', () {
      var device = SimulatedDevice(name: 'd', instanceCount: 3, firstInstance: 5);
      expect(SimulationRules.resolvedTopics(device, topic('t/{n}')), ['t/5', 't/6', 't/7']);
    });

    test('the description names device and topic', () {
      var issue = SimulationRules.validateTopic(SimulatedDevice(name: 'Dev', instanceCount: 2), topic('a/b')).single;
      expect(issue.describe(), 'Dev / a/b: with more than one instance the topic must contain {n}');
    });
  });
}
