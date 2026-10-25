import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/documentation/engine/schema_validator.dart';
import 'package:mqttstudio/documentation/export/asyncapi_importer.dart';
import 'package:mqttstudio/documentation/export/doc_export.dart';
import 'package:mqttstudio/documentation/export/import_merge.dart';
import 'package:mqttstudio/documentation/export/schema_json.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/documentation/presets/vda5050_preset.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_schemas.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:mqttstudio/simulator/engine/simulator_runner.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/model/vda5050_source.dart';
import 'package:mqttstudio/simulator/vda5050/robot_fault.dart';
import 'package:typed_data/typed_buffers.dart';

class _Publisher implements SimulatorPublisher {
  final List<(String, Map<String, Object?>)> sent = [];
  @override
  bool isConnected = true;
  @override
  bool supportsProperties = false;

  @override
  void publish(String topic, Uint8Buffer payload, MqttQos qos, bool retain, MqttMessageProperties? properties) {
    var text = utf8.decode(payload);
    if (text.isNotEmpty) {
      sent.add((topic, jsonDecode(text) as Map<String, Object?>));
    }
  }
}

// what a simulated fleet of the version publishes in two minutes, with some faults on the way
List<(String, Map<String, Object?>)> _simulate(VdaVersion version) {
  var publisher = _Publisher();
  fakeAsync((async) {
    var runner = SimulatorRunner(publisher, seed: 1);
    var device = SimulatedDevice(
        name: 'fleet',
        kind: DeviceKind.vda5050,
        instanceCount: 3,
        vda5050: Vda5050Source(
            version: version,
            interfaceName: Vda5050Preset.defaultInterfaceName(version),
            maxIdleSec: 2,
            actionProbability: 0.5,
            seed: 3));
    runner.startDevice(device);
    async.elapse(const Duration(seconds: 30));
    var fleet = runner.fleetOf(device.id)!;
    for (var fault in [RobotFault.warning, RobotFault.fatal, RobotFault.pause, RobotFault.cancelOrder]) {
      fleet.inject(fleet.robots.first, fault);
      async.elapse(const Duration(seconds: 5));
    }
    if (version.isV3) {
      fleet.inject(fleet.robots.last, RobotFault.responseWithoutRequest);
      fleet.inject(fleet.robots.last, RobotFault.hibernate);
    }
    async.elapse(const Duration(minutes: 1));
    runner.dispose();
  });
  return publisher.sent;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (var version in VdaVersion.values) {
    group(Vda5050Preset.nameOf(version), () {
      late TopicDocumentation documentation;
      late List<String> warnings;

      setUpAll(() async {
        var imported = await Vda5050Preset.build(version, interfaceName: Vda5050Preset.defaultInterfaceName(version));
        documentation = imported.documentation;
        warnings = imported.warnings;
      });

      DocNode topicNode(String topic) =>
          documentation.nodes.singleWhere((node) => node.path.endsWith('/{serialNumber}/$topic'));

      test('documents every topic of the version from the official schemas', () {
        var prefix = '${Vda5050Preset.defaultInterfaceName(version)}/${version.topicLevel}';
        expect(warnings, isEmpty);
        expect(documentation.nodes.map((node) => node.path), [
          prefix,
          '$prefix/{manufacturer}/{serialNumber}',
          for (var topic in Vda5050Schemas.topicsOf(version).toList()..sort()) '$prefix/{manufacturer}/{serialNumber}/$topic',
        ]);
        var state = topicNode(VdaTopic.state);
        expect(state.topic!.payload.format, PayloadFormat.json);
        expect(state.topic!.payload.schema!.required, containsAll(['headerId', 'orderId', 'driving']));
        expect(state.topic!.interval.staleAfterMs, Vda5050Preset.stateStaleAfterMs);
        expect(state.parameters.map((parameter) => parameter.description), everyElement(isNotEmpty));
        // only the 3.0 schemas carry units
        var velocity = state.topic!.payload.schema!.properties['velocity']!;
        expect(velocity.properties['vx']!.unit, version.isV3 ? 'm/s' : isNull);
        var connection = topicNode(VdaTopic.connection).topic!;
        expect(connection.qos, MqttQos.atLeastOnce);
        expect(connection.retain, RetainMode.always);
        expect(connection.lastWill, isTrue);
        expect(topicNode(VdaTopic.order).topic!.producers, [Vda5050Preset.fleetControl]);
      });

      test('every message of the simulated robots passes the documented schema', () {
        var messages = _simulate(version);
        expect(messages.length, greaterThan(300));
        var checked = <String>{};
        for (var (topic, json) in messages) {
          var type = topic.split('/').last;
          var issues = SchemaValidator.validate(topicNode(type).topic!.payload.schema!, json);
          expect(issues.map((issue) => '${issue.path} ${issue.message}'), isEmpty, reason: '$topic ${jsonEncode(json)}');
          checked.add(type);
        }
        expect(checked, containsAll([VdaTopic.order, VdaTopic.state, VdaTopic.connection, VdaTopic.factsheet]));
      });

      test('imports into an empty documentation and survives an AsyncAPI round trip', () {
        var plan = ImportPlan.of(TopicDocumentation(), documentation);
        expect(plan.countOf(ImportState.added), documentation.nodes.length);
        var exported =
            DocExport.run(documentation, const DocExportOptions(DocExportFormat.asyncapiJson), exportedAt: DateTime(2026));
        var again = AsyncApiImporter.read(exported).documentation;
        expect(again.nodes.map((node) => node.path), documentation.nodes.map((node) => node.path));
        for (var i = 0; i < documentation.nodes.length; i++) {
          var topic = documentation.nodes[i].topic;
          if (topic == null) {
            continue;
          }
          var other = again.nodes[i].topic!;
          // the order of required fields may change, the exporter sorts them
          expect(SchemaJson.toJsonSchema(other.payload.schema!), SchemaJson.toJsonSchema(topic.payload.schema!));
          expect(jsonEncode((other.toJson()..remove('payload'))), jsonEncode(topic.toJson()..remove('payload')));
        }
      });
    });
  }

  test('a broken message is found', () async {
    var preset = await Vda5050Preset.build(VdaVersion.v3, interfaceName: 'vda5050');
    var state = preset.documentation.nodes.singleWhere((node) => node.path.endsWith('/state')).topic!.payload.schema!;
    var issues = SchemaValidator.validate(state, {'headerId': 'one', 'operatingMode': 'TEACHIN'});
    expect(issues.map((issue) => issue.kind), containsAll([SchemaIssueKind.type, SchemaIssueKind.required, SchemaIssueKind.notAllowed]));
  });

  test('interface names must be one topic level', () {
    expect(Vda5050Preset.validInterfaceName(' uagv '), 'uagv');
    expect(Vda5050Preset.validInterfaceName('a/b'), isNull);
    expect(Vda5050Preset.validInterfaceName('+'), isNull);
    expect(Vda5050Preset.validInterfaceName(''), isNull);
  });
}
