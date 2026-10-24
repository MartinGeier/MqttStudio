import 'package:mqttstudio/simulator/engine/generator_instances.dart';
import 'package:mqttstudio/simulator/engine/placeholders.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';

enum SimulationIssueKind {
  topicEmpty,
  topicWildcard,
  topicNeedsInstance,
  intervalTooShort,
  intervalRange,
  instanceCount,
  deviceNameEmpty,
  deviceNameDuplicate,
  templateUnknownField,
  templateFieldNotAllowed,
  routeTooShort,
}

// A rule a simulation breaks. The CLI prints describe(), the app shows a localized text per kind.
class SimulationIssue {
  final SimulationIssueKind kind;
  final String device;
  final String topic;
  final String detail;

  const SimulationIssue(this.kind, {this.device = '', this.topic = '', this.detail = ''});

  String describe() {
    var where = topic.isEmpty ? device : '$device / $topic';
    switch (kind) {
      case SimulationIssueKind.topicEmpty:
        return '$where: the topic is empty';
      case SimulationIssueKind.topicWildcard:
        return '$where: a topic must not contain + or #';
      case SimulationIssueKind.topicNeedsInstance:
        return '$where: with more than one instance the topic must contain {n}';
      case SimulationIssueKind.intervalTooShort:
        return '$where: the interval must be at least ${SimulationRules.minIntervalMs} ms';
      case SimulationIssueKind.intervalRange:
        return '$where: "up to" must not be smaller than the interval';
      case SimulationIssueKind.instanceCount:
        return '$where: the number of instances must be between 1 and ${SimulationRules.maxInstances}';
      case SimulationIssueKind.deviceNameEmpty:
        return 'A device has no name';
      case SimulationIssueKind.deviceNameDuplicate:
        return 'The device name "$device" is used more than once';
      case SimulationIssueKind.templateUnknownField:
        return '$where: the template refers to the unknown field $detail';
      case SimulationIssueKind.templateFieldNotAllowed:
        return '$where: the template field $detail cannot use this generator';
      case SimulationIssueKind.routeTooShort:
        return '$where: a GPS route needs at least 2 waypoints';
    }
  }

  @override
  String toString() => describe();
}

// Limits, validation and rate estimation shared by the simulator tab, its dialogs and the CLI.
class SimulationRules {
  static const int maxInstances = 1000;
  static const int minIntervalMs = 50;
  // msg/s above which the toolbar warns
  static const double warningRate = 100;
  static const double webWarningRate = 50;
  // msg/s above which a start is refused in the app
  static const double maxRate = 1000;
  // the most the CLI allows with --max-rate
  static const double maxCliRate = 20000;

  static double topicRate(SimulatedDevice device, SimulatedTopic topic) =>
      device.instanceCount * 1000 / topic.interval.averageMs;

  static double estimateRate(Iterable<(SimulatedDevice, SimulatedTopic)> topics) =>
      topics.fold(0.0, (sum, entry) => sum + topicRate(entry.$1, entry.$2));

  static List<SimulationIssue> validateTopic(SimulatedDevice device, SimulatedTopic topic) {
    var issues = <SimulationIssue>[];
    void add(SimulationIssueKind kind, [String detail = '']) =>
        issues.add(SimulationIssue(kind, device: device.name, topic: topic.topic, detail: detail));

    if (topic.topic.trim().isEmpty) {
      add(SimulationIssueKind.topicEmpty);
    } else if (topicHasWildcard(topic.topic)) {
      add(SimulationIssueKind.topicWildcard);
    }
    if (device.instanceCount > 1 && !Placeholders.containsInstance(topic.topic)) {
      add(SimulationIssueKind.topicNeedsInstance);
    }
    if (topic.interval.minMs < minIntervalMs) {
      add(SimulationIssueKind.intervalTooShort);
    }
    if (topic.interval.maxMs < topic.interval.minMs) {
      add(SimulationIssueKind.intervalRange);
    }
    for (var issue in validateGenerator(topic.generator)) {
      add(issue.$1, issue.$2);
    }
    return issues;
  }

  static List<(SimulationIssueKind, String)> validateGenerator(PayloadGenerator generator) {
    var issues = <(SimulationIssueKind, String)>[];
    if (generator is GpsTrackGenerator && generator.mode == GpsMode.route && generator.waypoints.length < 2) {
      issues.add((SimulationIssueKind.routeTooShort, ''));
    }
    if (generator is TemplateGenerator) {
      for (var name in unknownTemplateFields(generator)) {
        issues.add((SimulationIssueKind.templateUnknownField, name));
      }
      for (var entry in generator.fields.entries) {
        if (!entry.value.type.allowedInTemplate) {
          issues.add((SimulationIssueKind.templateFieldNotAllowed, entry.key));
        }
        for (var issue in validateGenerator(entry.value)) {
          issues.add(issue);
        }
      }
    }
    return issues;
  }

  static List<SimulationIssue> validateDevice(SimulatedDevice device, Simulation simulation) {
    var issues = <SimulationIssue>[];
    if (device.name.trim().isEmpty) {
      issues.add(SimulationIssue(SimulationIssueKind.deviceNameEmpty));
    } else if (isDuplicateDeviceName(device.name, simulation, exceptId: device.id)) {
      issues.add(SimulationIssue(SimulationIssueKind.deviceNameDuplicate, device: device.name));
    }
    if (device.instanceCount < 1 || device.instanceCount > maxInstances) {
      issues.add(SimulationIssue(SimulationIssueKind.instanceCount, device: device.name));
    }
    for (var topic in device.topics) {
      issues.addAll(validateTopic(device, topic));
    }
    return issues;
  }

  static List<SimulationIssue> validateSimulation(Simulation simulation, [Iterable<SimulatedDevice>? devices]) =>
      (devices ?? simulation.devices).expand((device) => validateDevice(device, simulation)).toList();

  static bool isDuplicateDeviceName(String name, Simulation simulation, {String? exceptId}) => simulation.devices
      .any((device) => device.id != exceptId && device.name.trim().toLowerCase() == name.trim().toLowerCase());

  static bool topicHasWildcard(String topic) => topic.contains('+') || topic.contains('#');

  // names referenced with {{name}} or {{name.part}} in the template
  static Set<String> templateReferences(String template) =>
      templateFieldPattern.allMatches(template).map((match) => match.group(1)!).toSet();

  static Set<String> unknownTemplateFields(TemplateGenerator generator) =>
      templateReferences(generator.template).difference(generator.fields.keys.toSet());

  // all topics a device publishes to, e.g. for the device dialog and the CLI plan
  static List<String> resolvedTopics(SimulatedDevice device, SimulatedTopic topic) => device.instanceNumbers
      .map((n) => Placeholders.resolve(topic.topic, instance: n, deviceName: device.name))
      .toList();
}
