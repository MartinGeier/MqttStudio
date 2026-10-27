import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/export/asyncapi_importer.dart';
import 'package:mqttstudio/documentation/export/doc_export.dart';
import 'package:mqttstudio/documentation/export/import_merge.dart';
import 'package:mqttstudio/documentation/export/markdown_html.dart';
import 'package:mqttstudio/documentation/export/yaml_writer.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:yaml/yaml.dart';

final DateTime exportedAt = DateTime.utc(2026, 10, 24, 10);

TopicDocumentation sample() =>
    TopicDocumentation(title: 'Demo factory', description: 'Machines | QA', owner: 'Automation', revision: 3, nodes: [
      DocNode(path: 'plant', title: 'Plant', description: 'All machines of the plant.', status: DocStatus.stable),
      DocNode(
          path: 'plant/{line}/m{machine}/status',
          title: 'Machine status',
          description: 'Sent every 10 s.\n\nRetained, <b>not</b> HTML.',
          status: DocStatus.stable,
          owner: 'Automation team',
          tags: ['machine', 'mes'],
          links: [
            DocLink(label: 'MES spec', url: 'https://example.com/mes'),
            DocLink(label: 'OEE', url: 'https://example.com/oee')
          ],
          parameters: [
            DocParameter(name: 'line', description: 'Line number', pattern: r'\d+', examples: ['1', '2']),
            DocParameter(name: 'machine', description: 'Machine, "type plate"'),
          ],
          observed: ObservedTopic(from: exportedAt, to: exportedAt, messages: 12, instanceCount: 3),
          topic: TopicSpec(
              qos: MqttQos.atLeastOnce,
              retain: RetainMode.always,
              interval: IntervalSpec(kind: IntervalKind.periodic, nominalMs: 10000, staleAfterMs: 30000),
              lastWill: true,
              producers: ['Gateway'],
              consumers: ['MES', 'OEE dashboard'],
              sensitivity: Sensitivity.confidential,
              accessNotes: 'Gateways publish, mes reads.',
              mqtt5: Mqtt5Spec(
                  contentType: 'application/json',
                  utf8Payload: true,
                  messageExpirySeconds: 60,
                  userProperties: [DocUserProperty(key: 'source', description: 'Gateway id', example: 'gw-1')]),
              payload: PayloadSpec(
                  format: PayloadFormat.json,
                  encoding: 'UTF-8',
                  examples: [DocExample(payload: '{"state":"running","temp":75.6}', note: 'running')],
                  schema: SchemaNode(properties: {
                    'state': SchemaNode(
                        type: SchemaType.string, enumValues: ['idle', 'running'], description: 'Machine state'),
                    'temp': SchemaNode(type: SchemaType.number, unit: '°C', minimum: 0, maximum: 120),
                    'alarms': SchemaNode(type: SchemaType.array, items: SchemaNode(type: SchemaType.integer)),
                    'ts': SchemaNode(type: SchemaType.string, format: 'date-time'),
                    'x': SchemaNode(type: SchemaType.mixed),
                  }, required: {
                    'state',
                    'temp'
                  })))),
      DocNode(
          path: 'plant/{line}/speed',
          title: 'Speed, in rpm',
          parameters: [DocParameter(name: 'line')],
          topic: TopicSpec(
              qos: MqttQos.atMostOnce,
              retain: RetainMode.never,
              payload: PayloadSpec(format: PayloadFormat.number, unit: 'rpm', min: 0, max: 24000))),
      DocNode(
          path: 'qa/result',
          topic: TopicSpec(payload: PayloadSpec(format: PayloadFormat.string, allowedValues: ['good', 'bad']))),
    ]);

MqttSettings broker() =>
    MqttSettings('broker.local', 'client-1', 8883, username: 'user', password: 'secret', useSsl: true)
      ..protocolVersion = MqttProtocolVersion.v5;

String export(DocExportFormat format,
        {String? scope, bool observed = false, bool brokerToo = true, bool examples = true}) =>
    DocExport.run(
        sample(),
        DocExportOptions(format,
            scope: scope, includeObserved: observed, includeBroker: brokerToo, includeExamples: examples),
        broker: broker(),
        exportedAt: exportedAt);

// the sample with every field the editor fills in, in Markdown and as a deprecated node
TopicDocumentation rich() {
  var documentation = sample();
  var status = documentation.nodeAt('plant/{line}/m{machine}/status')!
    ..status = DocStatus.deprecated
    ..replacedBy = 'plant/{line}/speed'
    ..description = 'Sent **every** 10 s, see the [speed topic](topic:plant/7/speed).\n\n'
        '- publishes `state`\n- [OEE](https://example.com/oee)\n\n[bad link](javascript:void)';
  var topic = status.topic!
    ..mqtt5.responseTopic = 'plant/reply'
    ..mqtt5.correlationData = 'request id';
  var payload = topic.payload;
  payload.schema!
    ..description = 'One status report'
    ..properties['load'] = SchemaNode(type: SchemaType.integer, unit: '%', minimum: 0);
  payload.examples.single
    ..topic = 'plant/1/m7/status'
    ..capturedAt = exportedAt;
  documentation.nodes.add(DocNode(path: 'qa/raw', topic: TopicSpec()));
  documentation.sortNodes();
  return documentation;
}

String richExport(DocExportFormat format) => DocExport.run(rich(), DocExportOptions(format), exportedAt: exportedAt);

// the documented part of a node, as an import compares it
String documented(DocNode node) => jsonEncode(node.toJson()
  ..remove('observed')
  ..remove('review')
  ..remove('editedFields'));

void main() {
  group('YamlWriter', () {
    test('writes what the yaml package reads back', () {
      var value = {
        'plain': 'text',
        'needs quotes': 'a: b # c',
        'multi': 'line one\nline two\n',
        'number': 1.5,
        'flag': true,
        'none': null,
        'empty map': <String, Object?>{},
        'empty list': <Object?>[],
        r'$ref': '#/components/messages/a',
        'plant/{line}/temp': {
          'list': [
            1,
            'two',
            {
              'a': 1,
              'b': [true]
            },
            []
          ],
          'leading': ' blank'
        },
        'list of maps': [
          {
            'name': 'a',
            'nested': {'x': 'y'}
          },
          {'name': 'b'}
        ],
      };
      var text = YamlWriter.write(value);
      expect(jsonDecode(jsonEncode(loadYaml(text))), value);
    });
  });

  group('export', () {
    test('Markdown has a table of contents, anchors, tables and examples', () {
      var text = export(DocExportFormat.markdown);
      expect(text, startsWith('# Demo factory\n'));
      expect(text, contains('**Broker:** broker.local:8883 · mqtts · MQTT 5'));
      expect(text, contains('- [`plant`](#t1) — Plant'));
      expect(text, contains('  - [`plant/{line}/m{machine}/status`](#t2) — Machine status'));
      expect(text, contains('## <a id="t2"></a>`plant/{line}/m{machine}/status` — Machine status'));
      expect(text, contains(r'| line | \d+ | Line number | 1, 2 |'));
      expect(text, contains('| \$.temp | number | °C | 0 – 120 | yes |  |'));
      expect(text, contains('```json\n{\n  "state": "running",'));
      expect(text, contains('**QoS:** 1 · **Retain:** Always · **Interval:** Periodic · **Nominal interval:** 10 s'));
      expect(text, isNot(contains('secret')));
      expect(text, isNot(contains('client-1')));
    });

    test('HTML is self-contained and escapes the texts', () {
      var text = export(DocExportFormat.html);
      expect(text, startsWith('<!doctype html>'));
      expect(
          text, contains('<h2 id="t2"><code class="topic">plant/{line}/m{machine}/status</code> Machine status</h2>'));
      expect(text, contains('Retained, &lt;b&gt;not&lt;/b&gt; HTML.'));
      expect(text, contains('@media print'));
      expect(text, isNot(contains('<script')));
    });

    test('CSV has one row per topic, quoted where needed', () {
      var lines = const LineSplitter().convert(export(DocExportFormat.csv));
      expect(lines.first, startsWith('path,title,status,format'));
      expect(lines, hasLength(4));
      expect(lines[2], 'plant/{line}/speed,"Speed, in rpm",draft,number,rpm,0,24000,0,never,unknown,,,,,');
    });

    test('the JSON Schema bundle has a definition per documented payload', () {
      var bundle = jsonDecode(export(DocExportFormat.jsonSchema)) as Map<String, dynamic>;
      var defs = bundle[r'$defs'] as Map<String, dynamic>;
      expect(defs.keys, ['plant/{line}/m{machine}/status', 'plant/{line}/speed', 'qa/result']);
      var status = defs['plant/{line}/m{machine}/status'] as Map<String, dynamic>;
      expect(status['required'], ['state', 'temp']);
      expect(status['properties']['temp'], {'type': 'number', 'x-unit': '°C', 'minimum': 0, 'maximum': 120});
      expect(status['properties']['x'], isEmpty);
      expect(defs['qa/result']['enum'], ['good', 'bad']);
    });

    test('a scope exports one namespace or topic with everything below it', () {
      var text = export(DocExportFormat.csv, scope: 'plant/{line}/speed');
      expect(const LineSplitter().convert(text), hasLength(2));
    });

    test('AsyncAPI 3.0 has a channel, operation and message per topic and no credentials', () {
      var api = jsonDecode(export(DocExportFormat.asyncapiJson)) as Map<String, dynamic>;
      expect(api['asyncapi'], '3.0.0');
      expect(api['info']['version'], '1.3');
      expect(api['servers']['broker'], {'host': 'broker.local:8883', 'protocol': 'mqtts', 'protocolVersion': '5'});
      var channel = api['channels']['plant_line_mmachine_status'] as Map<String, dynamic>;
      expect(channel['address'], 'plant/{line}/m{machine}/status');
      expect(channel['parameters']['line']['x-mqttstudio-pattern'], r'\d+');
      var operation = api['operations']['plant_line_mmachine_status'] as Map<String, dynamic>;
      expect(operation['action'], 'receive');
      expect(operation['bindings']['mqtt'], {'qos': 1, 'retain': true, 'bindingVersion': '0.2.0'});
      var message = api['components']['messages']['plant_line_mmachine_status'] as Map<String, dynamic>;
      expect(message['examples'].single['payload'], {'state': 'running', 'temp': 75.6});
      expect(message['bindings']['mqtt']['messageExpiryInterval'], 60);
      expect(api['x-mqttstudio-namespaces'].single['path'], 'plant');
      expect(jsonEncode(api), isNot(contains('secret')));
      expect(channel.containsKey('x-mqttstudio-observed'), isFalse);
      var withoutBroker = jsonDecode(export(DocExportFormat.asyncapiJson, brokerToo: false)) as Map<String, dynamic>;
      expect(withoutBroker.containsKey('servers'), isFalse);
    });
  });

  group('Markdown and HTML documents', () {
    test('HTML shows every documented field of a node', () {
      var html = richExport(DocExportFormat.html);
      expect(html,
          contains('<a href="#t2"><code>plant/{line}/m{machine}/status</code> <span>Machine status</span></a>'));
      expect(html, contains('<span><b>Status</b> Deprecated</span>'));
      expect(html, contains('<span><b>Replaced by</b> <a href="#t3">plant/{line}/speed</a></span>'));
      expect(html, contains('<span><b>Owner</b> Automation team</span>'));
      expect(html, contains('<span><b>Tags</b> machine, mes</span>'));
      expect(html, contains('<strong>every</strong> 10 s'));
      expect(html,
          contains('<span><b>MES spec</b> <a href="https://example.com/mes">https://example.com/mes</a></span>'));
      expect(html, contains('<td>line</td><td>\\d+</td><td>Line number</td><td>1, 2</td>'));
      expect(html, contains('<span><b>Format</b> Json</span><span><b>Encoding</b> UTF-8</span>'));
      expect(html, contains(r'<td>$</td><td>object</td><td></td><td></td><td></td><td>One status report</td>'));
      expect(html, contains(r'<td>$.state</td><td>string</td><td></td><td>idle, running</td><td>yes</td>'));
      expect(html, contains(r'<td>$.temp</td><td>number</td><td>°C</td><td>0 – 120</td><td>yes</td>'));
      expect(html, contains(r'<td>$.load</td><td>integer</td><td>%</td><td>≥ 0</td>'));
      expect(html, contains(r'<td>$.ts</td><td>string (date-time)</td>'));
      expect(html, contains('<h3>Example: running</h3>'));
      expect(html, contains('<span><b>Topic</b> plant/1/m7/status</span>'));
      expect(html, contains('<span><b>Captured</b> '));
      expect(html, contains('<span><b>QoS</b> 1</span><span><b>Retain</b> Always</span>'));
      expect(html, contains('<span><b>Stale after</b> 30 s</span><span><b>Last will</b> yes</span>'));
      expect(html, contains('<span><b>Content type</b> application/json</span>'));
      expect(html, contains('<span><b>Response topic</b> plant/reply</span>'));
      expect(html, contains('<span><b>Correlation data</b> request id</span>'));
      expect(html, contains('<td>source</td><td>Gateway id</td><td>gw-1</td>'));
      expect(html, contains('<span><b>Producers</b> Gateway</span><span><b>Consumers</b> MES, OEE dashboard</span>'));
      expect(html, contains('<span><b>Sensitivity</b> Confidential</span>'));
      expect(html, contains('Gateways publish, mes reads.'));
    });

    test('HTML leaves out what is not documented', () {
      var html = richExport(DocExportFormat.html);
      // a discovered topic nobody documented yet
      var raw = html.substring(html.indexOf('<h2 id="t4">'), html.indexOf('<h2 id="t5">'));
      expect(raw, contains('<h2 id="t4"><code class="topic">qa/raw</code> </h2>\n'
          '<p class="facts"><span><b>Status</b> Draft</span></p>\n</div>'));
      expect(raw, isNot(contains('<h3>')));
      expect(html, isNot(contains('not documented')));
      // the speed topic's parameter has a name only
      var speed = html.substring(html.indexOf('<h2 id="t3">'), html.indexOf('<h2 id="t4">'));
      expect(speed, contains('<thead><tr><th>Name</th></tr></thead>'));
      expect(speed, contains('<span><b>Range</b> 0 – 24000</span>'));
    });

    test('HTML renders the Markdown of descriptions safely', () {
      var html = richExport(DocExportFormat.html);
      expect(html, contains('<li>publishes <code>state</code></li>'));
      expect(html, contains('<a href="#t3">speed topic</a>'));
      expect(html, contains('<a href="https://example.com/oee">OEE</a>'));
      expect(html, isNot(contains('javascript:')));
      expect(html, contains('<p>bad link</p>'));
    });

    test('Markdown links facts and topics', () {
      var text = richExport(DocExportFormat.markdown);
      expect(text, contains('**Replaced by:** [plant/{line}/speed](#t3)'));
      expect(text, contains('**MES spec:** [https://example.com/mes](https://example.com/mes)'));
      expect(text, contains('[speed topic](#t3)'));
      expect(text, contains('**Topic:** plant/1/m7/status'));
      expect(text, contains(r'| $ | object |  |  |  | One status report |'));
      expect(text, contains('**Correlation data:** request id'));
      expect(text, isNot(contains('**Delivery**\n\n**QoS:** not documented')));
    });

    test('the print stylesheet keeps tables and long paths on the page', () {
      var html = richExport(DocExportFormat.html);
      expect(html, contains('thead{display:table-header-group}'));
      expect(html, contains('.table,pre{overflow:visible}'));
      expect(html, contains('overflow-wrap:anywhere'));
      expect(html, contains('<div class="part">\n<h3>Payload</h3>\n<p class="facts">'));
    });
  });

  group('MarkdownHtml', () {
    test('renders paragraphs, headings, lists, quotes and code', () {
      var html = MarkdownHtml.convert('# Title\n\nline one\nline two\n\n- a\n- b\n\n1. c\n\n> note\n\n```\n<x>\n```');
      expect(
          html,
          '<h4>Title</h4>\n<p>line one<br>line two</p>\n<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n<ol>\n<li>c</li>\n</ol>\n'
          '<blockquote>note</blockquote>\n<pre><code>&lt;x&gt;</code></pre>\n');
    });

    test('renders inline formatting and keeps names and HTML as text', () {
      expect(MarkdownHtml.convert('**b** *i* _j_ `a*b*` temp_max_value <b>x</b>'),
          '<p><strong>b</strong> <em>i</em> <em>j</em> <code>a*b*</code> temp_max_value &lt;b&gt;x&lt;/b&gt;</p>\n');
    });

    test('links web addresses and documented topics only', () {
      String? anchor(String path) => path == 'a/b' ? '#t1' : null;
      expect(MarkdownHtml.convert('[x](javascript:alert) [y](topic:a/b) [z](topic:c) see https://e.com/a_b.',
              topicHref: anchor),
          '<p>x <a href="#t1">y</a> z see <a href="https://e.com/a_b">https://e.com/a_b</a>.</p>\n');
    });
  });

  group('AsyncAPI import', () {
    for (var format in [DocExportFormat.asyncapiYaml, DocExportFormat.asyncapiJson]) {
      test('an export imports without loss (${format.name})', () {
        var original = sample();
        var imported = AsyncApiImporter.read(export(format, observed: true));
        expect(imported.warnings, isEmpty);
        expect(imported.version, '3.0.0');
        var documentation = imported.documentation;
        expect(documentation.title, original.title);
        expect(documentation.description, original.description);
        expect(documentation.owner, original.owner);
        expect(documentation.revision, original.revision);
        expect(documentation.nodes.map((node) => node.path), original.nodes.map((node) => node.path));
        for (var node in original.nodes) {
          expect(documented(documentation.nodeAt(node.path)!), documented(node), reason: node.path);
        }
        expect(documentation.nodeAt('plant/{line}/m{machine}/status')!.observed!.messages, 12);
      });
    }

    test('reads AsyncAPI 2.6 with publish operations, references and parameter patterns', () {
      var imported = AsyncApiImporter.read('''
asyncapi: '2.6.0'
info:
  title: Street lights
  version: 1.0.0
channels:
  smartylighting/streetlights/{streetlightId}/lighting/measured:
    description: The topic on which measured values may be produced and consumed.
    parameters:
      streetlightId:
        description: The ID of the streetlight.
        schema:
          type: string
          pattern: '^[a-z0-9]+\$'
    subscribe:
      summary: Receive information about environmental lighting conditions of a particular streetlight.
      message:
        \$ref: '#/components/messages/lightMeasured'
      bindings:
        mqtt:
          qos: 1
          retain: false
  smartylighting/+/broken:
    publish:
      message:
        payload:
          type: string
components:
  messages:
    lightMeasured:
      contentType: application/json
      payload:
        type: object
        properties:
          lumens:
            type: integer
            minimum: 0
          sentAt:
            type: string
            format: date-time
          extra:
            oneOf: []
''');
      var node = imported.documentation.nodes.single;
      expect(node.path, 'smartylighting/streetlights/{streetlightId}/lighting/measured');
      expect(node.title, startsWith('Receive information'));
      expect(node.parameters.single.pattern, r'^[a-z0-9]+$');
      var topic = node.topic!;
      expect(topic.qos, MqttQos.atLeastOnce);
      expect(topic.retain, RetainMode.never);
      expect(topic.payload.format, PayloadFormat.json);
      expect(topic.payload.schema!.properties['lumens']!.minimum, 0);
      expect(topic.payload.schema!.properties['sentAt']!.format, 'date-time');
      expect(imported.warnings, hasLength(2));
      expect(imported.warnings.any((warning) => warning.contains('smartylighting/+/broken')), isTrue);
      expect(imported.warnings.any((warning) => warning.contains(r'$.extra: "oneOf"')), isTrue);
    });

    test('rejects what is no AsyncAPI document', () {
      expect(() => AsyncApiImporter.read('just: yaml'), throwsFormatException);
      expect(() => AsyncApiImporter.read('{not yaml'), throwsFormatException);
      expect(() => AsyncApiImporter.read('asyncapi: "1.2.0"'), throwsFormatException);
    });
  });

  group('ImportPlan', () {
    test('sorts imported topics into new, changed, same and conflicting ones and merges the chosen ones', () {
      var current = TopicDocumentation(nodes: [
        DocNode(
            path: 'plant/{line}/speed',
            title: 'Old',
            observed: ObservedTopic(from: exportedAt, to: exportedAt, messages: 5),
            topic: TopicSpec()),
        DocNode(
            path: 'qa/result',
            topic: TopicSpec(payload: PayloadSpec(format: PayloadFormat.string, allowedValues: ['good', 'bad']))),
        DocNode(path: 'plant/{l}/m{m}/status', topic: TopicSpec()),
      ]);
      var plan = ImportPlan.of(current, sample());
      var states = {for (var item in plan.items) item.imported.path: item.state};
      expect(states, {
        'plant': ImportState.added,
        'plant/{line}/m{machine}/status': ImportState.conflict,
        'plant/{line}/speed': ImportState.changed,
        'qa/result': ImportState.same,
      });
      plan.applyTo(current);
      expect(current.nodes.map((node) => node.path),
          ['plant', 'plant/{line}/speed', 'plant/{l}/m{m}/status', 'qa/result']);
      var speed = current.nodeAt('plant/{line}/speed')!;
      expect(speed.title, 'Speed, in rpm');
      expect(speed.observed!.messages, 5);
      expect(current.title, 'Demo factory');
      expect(current.revision, 1);
    });

    test('replace all takes the imported documentation and keeps observed values', () {
      var current = TopicDocumentation(title: 'Old', nodes: [
        DocNode(path: 'gone', topic: TopicSpec()),
        DocNode(
            path: 'qa/result',
            observed: ObservedTopic(from: exportedAt, to: exportedAt, messages: 7),
            topic: TopicSpec()),
      ]);
      ImportPlan.of(current, sample()).applyTo(current, replaceAll: true);
      expect(current.title, 'Demo factory');
      expect(current.nodeAt('gone'), isNull);
      expect(current.nodeAt('qa/result')!.observed!.messages, 7);
      expect(current.nodes, hasLength(4));
    });
  });
}
