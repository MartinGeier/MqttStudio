import 'package:flutter/services.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/documentation/export/asyncapi_importer.dart';
import 'package:mqttstudio/documentation/export/schema_json.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_schemas.dart';

// The description of one VDA 5050 topic in the preset
class _TopicPreset {
  final String title;
  final String description;
  final bool fromRobot;
  final MqttQos qos;
  final RetainMode retain;
  final IntervalSpec Function() interval;
  final bool lastWill;

  const _TopicPreset(this.title, this.description,
      {required this.fromRobot,
      this.qos = MqttQos.atMostOnce,
      this.retain = RetainMode.never,
      this.interval = _event,
      this.lastWill = false});

  static IntervalSpec _event() => IntervalSpec(kind: IntervalKind.event);
}

// A ready-made documentation of the VDA 5050 topics of one major version (doc/vda5050-design.md §9.1): a namespace
// for the interface and one for a robot, and the topics with the official JSON schemas, QoS, retain, producers and
// consumers and the state heartbeat. It goes through the same review as an AsyncAPI import.
class Vda5050Preset {
  static const String fleetControl = 'Fleet control';
  static const String mobileRobot = 'Mobile robot';
  static const String specificationUrl = 'https://github.com/VDA5050/VDA5050';
  // state comes at least every 30 s; a little more before it counts as stale
  static const int stateHeartbeatMs = 30000;
  static const int stateStaleAfterMs = 35000;

  static final Map<String, _TopicPreset> _topics = {
    VdaTopic.order: _TopicPreset(
        'Order',
        'The route the fleet control gives the robot: nodes and edges with their actions. Released nodes and edges '
            'form the base the robot may drive, the others the horizon. Updates keep the order id and raise '
            'orderUpdateId, starting at the last base node.',
        fromRobot: false),
    VdaTopic.instantActions: _TopicPreset(
        'Instant actions',
        'Actions the robot carries out at once, independent of its order: pause and resume, cancel the order, '
            'request the factsheet and others.',
        fromRobot: false),
    VdaTopic.state: _TopicPreset(
        'State',
        'Everything the robot reports about itself: position, battery, operating mode, order progress, action '
            'states, loads, errors and the safety state. Sent on every relevant change and at least every 30 s.',
        fromRobot: true,
        interval: () => IntervalSpec(
            kind: IntervalKind.periodicAndOnChange, nominalMs: stateHeartbeatMs, staleAfterMs: stateStaleAfterMs)),
    VdaTopic.visualization: _TopicPreset(
        'Visualization',
        'Position and velocity at a higher rate than state, for displays and traffic control.',
        fromRobot: true,
        interval: () => IntervalSpec(kind: IntervalKind.periodic)),
    VdaTopic.connection: _TopicPreset(
        'Connection',
        'Whether the robot is connected to the broker. Sent retained with QoS 1; the broken connection is the last '
            'will the broker publishes when the robot disappears.',
        fromRobot: true,
        qos: MqttQos.atLeastOnce,
        retain: RetainMode.always,
        lastWill: true),
    VdaTopic.factsheet: _TopicPreset(
        'Factsheet',
        'What the robot is and can do: type, physical parameters, protocol limits and features, geometry and loads.',
        fromRobot: true,
        retain: RetainMode.unknown),
    VdaTopic.zoneSet: _TopicPreset(
        'Zone set',
        'Zones on a map that change how the robot drives: blocked areas, speed limits, areas that need a release, '
            'one-way and priority rules.',
        fromRobot: false),
    VdaTopic.responses: _TopicPreset(
        'Responses',
        'The fleet control\'s answers to the zone and edge requests in the robot\'s state: granted, queued, revoked '
            'or rejected.',
        fromRobot: false),
  };

  static String defaultInterfaceName(VdaVersion version) => version.isV3 ? 'vda5050' : 'uagv';

  static String nameOf(VdaVersion version) => 'VDA 5050 ${version.isV3 ? '3.0' : '2.x'}';

  // the namespace of the interface, e.g. uagv/v2; null when the name can't be a topic level
  static String? validInterfaceName(String name) {
    var trimmed = name.trim();
    return trimmed.isEmpty || trimmed.contains(RegExp(r'[/+#{}]')) ? null : trimmed;
  }

  static Future<ImportedDocumentation> build(VdaVersion version, {required String interfaceName, AssetBundle? bundle}) async {
    var schemas = await Vda5050Schemas.load(version, bundle: bundle);
    var warnings = <String>[];
    var interfacePath = '$interfaceName/${version.topicLevel}';
    var robotPath = '$interfacePath/{manufacturer}/{serialNumber}';
    var documentation = TopicDocumentation(
      title: '${nameOf(version)} on $interfaceName',
      description: 'The topics between a fleet control and mobile robots that follow VDA 5050 '
          '${version.protocolVersion}. Schemas: the official JSON schemas of $specificationUrl (MIT licence).',
    );
    documentation.nodes.add(_namespace(
        interfacePath,
        nameOf(version),
        'Mobile robots and their fleet control, VDA 5050 ${version.protocolVersion}. The interface name '
            '"$interfaceName" is chosen by the plant.'));
    var robot = _namespace(robotPath, 'Mobile robot', 'The topics of one mobile robot.');
    for (var parameter in robot.parameters) {
      parameter.description = parameter.name == 'manufacturer'
          ? 'Manufacturer of the robot, as in the header of its messages'
          : 'Serial number of the robot, as in the header of its messages';
    }
    documentation.nodes.add(robot);
    for (var entry in schemas.entries) {
      var preset = _topics[entry.key]!;
      var schemaWarnings = <String>[];
      var schema = SchemaJson.fromJsonSchema(Vda5050Schemas.flatten(entry.value), warnings: schemaWarnings);
      warnings.addAll(schemaWarnings.map((warning) => '${entry.key}: $warning'));
      var node = _namespace('$robotPath/${entry.key}', preset.title, preset.description)
        ..topic = TopicSpec(
          payload: PayloadSpec(format: PayloadFormat.json, schema: schema),
          qos: preset.qos,
          retain: preset.retain,
          interval: preset.interval(),
          mqtt5: Mqtt5Spec(contentType: 'application/json', utf8Payload: true),
          producers: [preset.fromRobot ? mobileRobot : fleetControl],
          consumers: [preset.fromRobot ? fleetControl : mobileRobot],
          lastWill: preset.lastWill,
        );
      for (var parameter in node.parameters) {
        parameter.description = robot.parameters.firstWhere((p) => p.name == parameter.name).description;
      }
      documentation.nodes.add(node);
    }
    documentation.sortNodes();
    return ImportedDocumentation(documentation, nameOf(version), warnings);
  }

  static DocNode _namespace(String path, String title, String description) {
    var node = DocNode(
      path: path,
      title: title,
      description: description,
      status: DocStatus.stable,
      tags: ['VDA 5050'],
      links: [DocLink(label: 'VDA 5050 specification', url: specificationUrl)],
    );
    DocumentationService.syncParameters(node);
    return node;
  }
}
