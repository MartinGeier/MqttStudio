import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/engine/conformance_checker.dart';
import 'package:mqttstudio/documentation/engine/schema_validator.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';

final DateTime start = DateTime.utc(2026, 10, 25, 9);

RecordedMessage message(String topic, String payload,
        {MqttQos qos = MqttQos.atLeastOnce,
        bool retain = false,
        bool snapshot = false,
        MqttMessageProperties? properties}) =>
    RecordedMessage(
        offsetMicros: 0,
        topic: topic,
        payload: Uint8List.fromList(utf8.encode(payload)),
        qos: qos,
        retain: retain,
        snapshot: snapshot,
        properties: properties);

TopicDocumentation documentation() => TopicDocumentation(nodes: [
      DocNode(
          path: 'plant/m{machine}/status',
          parameters: [DocParameter(name: 'machine', pattern: r'\d+')],
          topic: TopicSpec(
              qos: MqttQos.atLeastOnce,
              retain: RetainMode.always,
              mqtt5: Mqtt5Spec(contentType: 'application/json'),
              payload: PayloadSpec(
                  format: PayloadFormat.json,
                  schema: SchemaNode(properties: {
                    'state': SchemaNode(type: SchemaType.string, enumValues: ['idle', 'running']),
                    'temp': SchemaNode(type: SchemaType.number, maximum: 120),
                    'alarms': SchemaNode(type: SchemaType.array, items: SchemaNode(type: SchemaType.integer)),
                  }, required: {
                    'state'
                  })))),
      DocNode(
          path: 'plant/speed',
          topic: TopicSpec(
              qos: MqttQos.atMostOnce,
              interval: IntervalSpec(staleAfterMs: 30000),
              payload: PayloadSpec(format: PayloadFormat.number, min: 0, max: 24000))),
      DocNode(
          path: 'plant/mode',
          status: DocStatus.deprecated,
          replacedBy: 'plant/m{machine}/status',
          topic: TopicSpec(payload: PayloadSpec(format: PayloadFormat.string, allowedValues: ['auto', 'manual']))),
      DocNode(path: 'plant/on', topic: TopicSpec(payload: PayloadSpec(format: PayloadFormat.boolean))),
    ]);

Map<FindingRule, List<Finding>> run(List<RecordedMessage> messages,
    {bool isMqtt5 = true, List<String> ignore = const []}) {
  var checker = ConformanceChecker(documentation(), isMqtt5: isMqtt5, ignoreFilters: ignore);
  for (var message in messages) {
    checker.check(message, start);
  }
  var result = <FindingRule, List<Finding>>{};
  for (var finding in checker.findings) {
    result.putIfAbsent(finding.rule, () => []).add(finding);
  }
  return result;
}

void main() {
  group('SchemaValidator', () {
    test('reports types, missing fields, values outside the enum and ranges with their paths', () {
      var schema = documentation().nodes.first.topic!.payload.schema!;
      var issues = SchemaValidator.validate(schema, {
        'state': 'maintenance',
        'temp': 131.2,
        'alarms': [1, 'x']
      });
      expect(issues.map((issue) => '${issue.kind.name} ${issue.path}'), [
        'notAllowed \$.state',
        'range \$.temp',
        'type \$.alarms[]',
      ]);
      expect(SchemaValidator.validate(schema, {'temp': 20}).single.kind, SchemaIssueKind.required);
      expect(SchemaValidator.validate(schema, [1]).single.message, 'is an array, documented object');
      expect(SchemaValidator.validate(schema, {'state': 'idle', 'temp': null, 'extra': 1}), isEmpty);
    });
  });

  group('ConformanceChecker', () {
    test('a message that matches its documentation gives no finding', () {
      var findings = run([
        message('plant/m12/status', '{"state":"idle","temp":40,"alarms":[3]}',
            retain: true, properties: MqttMessageProperties(contentType: 'application/json')),
        message('plant/speed', '1200', qos: MqttQos.atMostOnce),
        message('plant/on', '1'),
      ]);
      expect(findings, isEmpty);
    });

    test('each rule is found and aggregated per topic', () {
      var findings = run([
        message('plant/m12/status', '{"state":"maintenance","temp":131}', qos: MqttQos.atMostOnce),
        message('plant/m12/status', '{"state":"maintenance","temp":131}', qos: MqttQos.atMostOnce),
        message('plant/mx/status', '{"state":"idle"}', retain: true),
        message('plant/speed', 'fast', qos: MqttQos.atMostOnce),
        message('plant/speed', '30000', qos: MqttQos.atMostOnce),
        message('plant/mode', 'semi'),
        message('plant/other', '1'),
      ]);
      expect(findings.keys.toSet(), {
        FindingRule.valueNotAllowed,
        FindingRule.outOfRange,
        FindingRule.qosDiffers,
        FindingRule.retainDiffers,
        FindingRule.parameterMismatch,
        FindingRule.formatMismatch,
        FindingRule.deprecatedInUse,
        FindingRule.undocumented,
      });
      var notAllowed =
          findings[FindingRule.valueNotAllowed]!.firstWhere((finding) => finding.topic == 'plant/m12/status');
      expect(notAllowed.count, 2);
      expect(notAllowed.detail, r'$.state maintenance is not one of idle, running');
      expect(notAllowed.severity, FindingSeverity.error);
      expect(findings[FindingRule.parameterMismatch]!.single.detail,
          r'machine = x breaks the pattern of plant/m{machine}/status');
      expect(findings[FindingRule.formatMismatch]!.single.detail, 'Payload is string, documented number');
      expect(findings[FindingRule.outOfRange]!.map((finding) => finding.topic), ['plant/m12/status', 'plant/speed']);
      expect(findings[FindingRule.deprecatedInUse]!.single.detail, contains('replaced by plant/m{machine}/status'));
      expect(findings[FindingRule.undocumented]!.single.node, isNull);
    });

    test('ignore filters leave topics out, MQTT 3.1.1 only judges retain from the snapshot', () {
      expect(run([message('plant/other', '1')], ignore: ['plant/+']), isEmpty);
      var v311 = run([message('plant/m1/status', '{"state":"idle"}')], isMqtt5: false);
      expect(v311.containsKey(FindingRule.retainDiffers), isFalse);
      expect(v311.containsKey(FindingRule.mqtt5Differs), isFalse);
      var snapshot =
          run([message('plant/speed', '1', qos: MqttQos.atMostOnce, retain: true, snapshot: true)], isMqtt5: false);
      expect(snapshot.containsKey(FindingRule.retainDiffers), isFalse);
    });

    test('a topic is stale once it was silent for its threshold', () {
      var checker = ConformanceChecker(documentation());
      checker.start(start);
      checker.checkStale(start.add(Duration(seconds: 20)));
      expect(checker.findings, isEmpty);
      checker.checkStale(start.add(Duration(seconds: 31)));
      expect(checker.findings.single.rule, FindingRule.stale);
      expect(checker.findings.single.topic, 'plant/speed');

      var fresh = ConformanceChecker(documentation())..start(start);
      fresh.check(message('plant/speed', '1', qos: MqttQos.atMostOnce), start.add(Duration(seconds: 25)));
      fresh.checkStale(start.add(Duration(seconds: 40)));
      expect(fresh.findings, isEmpty);
      expect(fresh.severityByPath, isEmpty);
    });

    test('the filters are the documented topics and those of the last discovery', () {
      var docs = documentation();
      expect(ConformanceChecker.filtersOf(docs), ['plant/+/status', 'plant/mode', 'plant/on', 'plant/speed']);
      docs
        ..lastDiscoveryAt = start
        ..discoverySettings =
            DiscoverySettings(filters: [RecorderFilter('plant/#'), RecorderFilter('plant/x/#', exclude: true)]);
      expect(ConformanceChecker.filtersOf(docs), ['plant/#']);
      // documented topics outside the discovery's filters are still checked, e.g. after a preset import
      docs
        ..discoverySettings = DiscoverySettings(filters: [RecorderFilter('+')])
        ..nodes.add(DocNode(path: 'vda5050/v3/{manufacturer}/{serialNumber}/state', topic: TopicSpec()));
      expect(ConformanceChecker.filtersOf(docs),
          ['+', 'plant/+/status', 'plant/mode', 'plant/on', 'plant/speed', 'vda5050/v3/+/+/state']);
    });
  });
}
