import 'package:mqttstudio/simulator/engine/generator_instances.dart';
import 'package:mqttstudio/simulator/engine/placeholders.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/model/sparkplug_source.dart';
import 'package:mqttstudio/simulator/sparkplug/metric_values.dart';
import 'package:mqttstudio/simulator/sparkplug/simulated_sparkplug_device.dart';
import 'package:mqttstudio/simulator/vda5050/fleet_layout.dart';

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
  recordingNotChosen,
  recordingMissing,
  recordedNeedsInstance,
  recordedMaxSpeed,
  recordedRandomNeedsLoop,
  vdaNameInvalid,
  vdaSerialNeedsInstance,
  vdaTooManyRobots,
  vdaLayoutTooSmall,
  vdaSettingOutOfRange,
  sparkplugNameInvalid,
  sparkplugNodeNeedsInstance,
  sparkplugDeviceNeedsNumber,
  sparkplugTooManyNodes,
  sparkplugTooManyDevices,
  sparkplugTooManyMetrics,
  sparkplugMetricNameInvalid,
  sparkplugMetricDuplicate,
  sparkplugGeneratorType,
  sparkplugTooManyChanges,
  sparkplugSettingOutOfRange,
  sparkplugNoConnections,
  sparkplugHostFailed,
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
      case SimulationIssueKind.recordingNotChosen:
        return '$where: no recording is chosen';
      case SimulationIssueKind.recordingMissing:
        return '$where: the recording $detail is not in the recordings folder';
      case SimulationIssueKind.recordedNeedsInstance:
        return '$where: with more than one instance a topic remapping must contain {n}';
      case SimulationIssueKind.recordedMaxSpeed:
        return '$where: a recorded device cannot play at Max speed';
      case SimulationIssueKind.recordedRandomNeedsLoop:
        return '$where: instances starting at a random position need loop';
      case SimulationIssueKind.vdaNameInvalid:
        return '$where: the $detail must not be empty or contain /, + or #';
      case SimulationIssueKind.vdaSerialNeedsInstance:
        return '$where: with more than one robot the serial number must contain {n}';
      case SimulationIssueKind.vdaTooManyRobots:
        return '$where: a VDA 5050 device simulates at most ${SimulationRules.maxRobots} robots';
      case SimulationIssueKind.vdaLayoutTooSmall:
        return '$where: the layout needs more free nodes than robots';
      case SimulationIssueKind.vdaSettingOutOfRange:
        return '$where: the setting $detail is out of range';
      case SimulationIssueKind.sparkplugNameInvalid:
        return '$where: the $detail must not be empty or contain /, + or #';
      case SimulationIssueKind.sparkplugNodeNeedsInstance:
        return '$where: with more than one edge node the edge node id must contain {n}';
      case SimulationIssueKind.sparkplugDeviceNeedsNumber:
        return '$where: the device $detail is there more than once, its id must contain {d}';
      case SimulationIssueKind.sparkplugTooManyNodes:
        return '$where: a Sparkplug device simulates at most ${SimulationRules.maxEdgeNodes} edge nodes';
      case SimulationIssueKind.sparkplugTooManyDevices:
        return '$where: an edge node has at most ${SimulationRules.maxSparkplugDevices} devices';
      case SimulationIssueKind.sparkplugTooManyMetrics:
        return '$where: $detail has more than ${SimulationRules.maxSparkplugMetrics} metrics';
      case SimulationIssueKind.sparkplugMetricNameInvalid:
        return '$where: the metric name "$detail" is empty or reserved';
      case SimulationIssueKind.sparkplugMetricDuplicate:
        return '$where: the metric $detail is there more than once';
      case SimulationIssueKind.sparkplugGeneratorType:
        return '$where: the generator of metric $detail does not fit its data type';
      case SimulationIssueKind.sparkplugTooManyChanges:
        return '$where: more than ${SimulationRules.maxMetricChanges.round()} metric changes per second';
      case SimulationIssueKind.sparkplugSettingOutOfRange:
        return '$where: the setting $detail is out of range';
      case SimulationIssueKind.sparkplugNoConnections:
        return '$where: Sparkplug edge nodes need connections of their own, which are not available here';
      case SimulationIssueKind.sparkplugHostFailed:
        return '$where: the simulated primary host could not connect: $detail';
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
  // robots of one VDA 5050 device (D27)
  static const int maxRobots = 200;
  // Sparkplug (doc/sparkplug-design.md Q9): edge nodes are connections, metric changes are the load
  static const int maxEdgeNodes = 20;
  static const int maxSparkplugDevices = 20;
  static const int maxSparkplugMetrics = 200;
  static const double maxMetricChanges = 2000;
  static const int minScanMs = 100;

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
    if (device.isRecorded) {
      issues.addAll(validateRecorded(device));
    }
    if (device.isSparkplug) {
      issues.addAll(validateSparkplug(device));
    }
    if (device.isVda5050) {
      issues.addAll(validateVda5050(device));
    }
    for (var topic in device.topics) {
      issues.addAll(validateTopic(device, topic));
    }
    return issues;
  }

  // D24, D25: instances need {n} in a remapping so they don't publish to the same topics
  static List<SimulationIssue> validateRecorded(SimulatedDevice device) {
    var source = device.recorded;
    if (source == null || source.recordingId.isEmpty) {
      return [SimulationIssue(SimulationIssueKind.recordingNotChosen, device: device.name)];
    }
    var issues = <SimulationIssue>[];
    if (device.instanceCount > 1 && !source.playback.remaps.any((remap) => Placeholders.containsInstance(remap.to))) {
      issues.add(SimulationIssue(SimulationIssueKind.recordedNeedsInstance, device: device.name));
    }
    if (source.playback.isMaxSpeed) {
      issues.add(SimulationIssue(SimulationIssueKind.recordedMaxSpeed, device: device.name));
    }
    if (source.instanceStart == InstanceStart.randomPosition && !source.playback.loop) {
      issues.add(SimulationIssue(SimulationIssueKind.recordedRandomNeedsLoop, device: device.name));
    }
    return issues;
  }

  // D27: names that become topic levels, {n} in the serial number, enough room on the layout
  static List<SimulationIssue> validateVda5050(SimulatedDevice device) {
    var source = device.vda5050;
    var issues = <SimulationIssue>[];
    void add(SimulationIssueKind kind, [String detail = '']) =>
        issues.add(SimulationIssue(kind, device: device.name, detail: detail));
    if (source == null) {
      add(SimulationIssueKind.vdaSettingOutOfRange, 'vda5050');
      return issues;
    }
    for (var (name, value) in [
      ('interface name', source.interfaceName),
      ('manufacturer', source.manufacturer),
      ('serial number', source.serialNumber),
      ('map id', source.mapId),
    ]) {
      if (value.trim().isEmpty || topicHasWildcard(value) || value.contains('/')) {
        add(SimulationIssueKind.vdaNameInvalid, name);
      }
    }
    if (device.instanceCount > 1 && !Placeholders.containsInstance(source.serialNumber)) {
      add(SimulationIssueKind.vdaSerialNeedsInstance);
    }
    if (device.instanceCount > maxRobots) {
      add(SimulationIssueKind.vdaTooManyRobots);
    }
    if (FleetLayout.freeNodeCount(source) <= device.instanceCount) {
      add(SimulationIssueKind.vdaLayoutTooSmall);
    }
    for (var (name, ok) in [
      ('columns', source.columns >= 2 && source.columns <= 50),
      ('rows', source.rows >= 1 && source.rows <= 50),
      ('spacing', source.spacing > 0),
      ('speed', source.speed > 0),
      ('heartbeat', source.stateHeartbeatSec >= 1 && source.stateHeartbeatSec <= 30),
      ('visualization', source.visualizationMs == 0 || source.visualizationMs >= 100),
      ('order nodes', source.minOrderNodes >= 2 && source.maxOrderNodes >= source.minOrderNodes),
      ('action duration', source.minActionSec >= 0 && source.maxActionSec >= source.minActionSec),
      ('idle time', source.minIdleSec >= 0 && source.maxIdleSec >= source.minIdleSec),
      ('action probability', source.actionProbability >= 0 && source.actionProbability <= 1),
    ]) {
      if (!ok) {
        add(SimulationIssueKind.vdaSettingOutOfRange, name);
      }
    }
    return issues;
  }

  // names that become topic levels, {n} and {d}, metric names, generators that fit the types and the limits of Q9
  static List<SimulationIssue> validateSparkplug(SimulatedDevice device) {
    var source = device.sparkplug;
    var issues = <SimulationIssue>[];
    void add(SimulationIssueKind kind, [String detail = '']) =>
        issues.add(SimulationIssue(kind, device: device.name, detail: detail));
    if (source == null) {
      add(SimulationIssueKind.sparkplugSettingOutOfRange, 'sparkplug');
      return issues;
    }
    bool invalidLevel(String value) => value.trim().isEmpty || topicHasWildcard(value) || value.contains('/');
    for (var (name, value) in [('group id', source.groupId), ('edge node id', source.edgeNodeId)]) {
      if (invalidLevel(value)) {
        add(SimulationIssueKind.sparkplugNameInvalid, name);
      }
    }
    var host = source.primaryHostId;
    if (host != null && host.isNotEmpty && invalidLevel(host)) {
      add(SimulationIssueKind.sparkplugNameInvalid, 'primary host id');
    }
    if (device.instanceCount > 1 && !Placeholders.containsInstance(source.edgeNodeId)) {
      add(SimulationIssueKind.sparkplugNodeNeedsInstance);
    }
    if (device.instanceCount > maxEdgeNodes) {
      add(SimulationIssueKind.sparkplugTooManyNodes);
    }
    if (source.devices.fold(0, (sum, spec) => sum + spec.count) > maxSparkplugDevices) {
      add(SimulationIssueKind.sparkplugTooManyDevices);
    }
    if (source.scanMs < minScanMs) {
      add(SimulationIssueKind.sparkplugSettingOutOfRange, 'scan');
    }
    var deviceIds = <String>{};
    for (var spec in source.devices) {
      if (invalidLevel(spec.id.replaceAll('{d}', '1'))) {
        add(SimulationIssueKind.sparkplugNameInvalid, 'device id');
      }
      if (spec.count < 1) {
        add(SimulationIssueKind.sparkplugSettingOutOfRange, 'device count');
      }
      if (spec.count > 1 && !spec.id.contains('{d}')) {
        add(SimulationIssueKind.sparkplugDeviceNeedsNumber, spec.id);
      } else {
        for (var d = 1; d <= spec.count; d++) {
          if (!deviceIds.add(spec.id.replaceAll('{d}', '$d'))) {
            add(SimulationIssueKind.sparkplugDeviceNeedsNumber, spec.id);
            break;
          }
        }
      }
      _validateMetrics(spec.metrics, 'device ${spec.id}', add);
    }
    _validateMetrics(source.nodeMetrics, 'the edge node', add);
    if (SimulatedSparkplugDevice.changesOf(device) > maxMetricChanges) {
      add(SimulationIssueKind.sparkplugTooManyChanges);
    }
    return issues;
  }

  static const List<String> _reservedMetrics = ['bdSeq', 'Node Control/Rebirth'];

  static void _validateMetrics(List<SparkplugMetricSpec> metrics, String where,
      void Function(SimulationIssueKind kind, [String detail]) add) {
    if (metrics.length > maxSparkplugMetrics) {
      add(SimulationIssueKind.sparkplugTooManyMetrics, where);
    }
    var names = <String>{};
    for (var metric in metrics) {
      var name = metric.name.trim();
      if (name.isEmpty || _reservedMetrics.contains(name)) {
        add(SimulationIssueKind.sparkplugMetricNameInvalid, name);
      } else if (!names.add(name)) {
        add(SimulationIssueKind.sparkplugMetricDuplicate, name);
      }
      if (!SparkplugValues.scalarTypes.contains(metric.type) ||
          !SparkplugValues.generatorFits(metric.type, metric.generator)) {
        add(SimulationIssueKind.sparkplugGeneratorType, name);
      }
      if (metric.deadband < 0) {
        add(SimulationIssueKind.sparkplugSettingOutOfRange, 'deadband');
      }
    }
  }

  // the topic a recorded topic is published to, with the placeholders of the remapping still in it
  static String recordedTarget(SimulatedDevice device, String recordedTopic) =>
      device.recorded?.playback.remap(recordedTopic) ?? recordedTopic;

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
