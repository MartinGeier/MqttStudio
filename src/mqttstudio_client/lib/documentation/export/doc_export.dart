import 'dart:convert';
import 'package:mqttstudio/documentation/engine/doc_path.dart';
import 'package:mqttstudio/documentation/export/asyncapi_exporter.dart';
import 'package:mqttstudio/documentation/export/csv_exporter.dart';
import 'package:mqttstudio/documentation/export/doc_blocks.dart';
import 'package:mqttstudio/documentation/export/schema_json.dart';
import 'package:mqttstudio/documentation/export/yaml_writer.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';

enum DocExportFormat { markdown, html, asyncapiYaml, asyncapiJson, jsonSchema, csv }

class DocExportOptions {
  final DocExportFormat format;
  // the namespace or topic to export with everything below it; null for the whole documentation
  final String? scope;
  final bool includeExamples;
  final bool includeObserved;
  // the broker's host, port and protocol, never its credentials or client id (T15)
  final bool includeBroker;

  const DocExportOptions(this.format,
      {this.scope, this.includeExamples = true, this.includeObserved = false, this.includeBroker = false});
}

// Writes the documentation as Markdown, HTML, AsyncAPI 3.0, a JSON Schema bundle or CSV (doc/documentation-design.md
// §9). The texts of the exported documents are English; they are documents, not app UI.
class DocExport {
  static String extensionOf(DocExportFormat format) => switch (format) {
        DocExportFormat.markdown => 'md',
        DocExportFormat.html => 'html',
        DocExportFormat.asyncapiYaml => 'asyncapi.yaml',
        DocExportFormat.asyncapiJson => 'asyncapi.json',
        DocExportFormat.jsonSchema => 'schema.json',
        DocExportFormat.csv => 'csv',
      };

  static String run(TopicDocumentation documentation, DocExportOptions options,
      {MqttSettings? broker, DateTime? exportedAt}) {
    var nodes = nodesInScope(documentation, options.scope);
    var at = exportedAt ?? DateTime.now();
    switch (options.format) {
      case DocExportFormat.markdown:
        return DocBlocks.build(documentation, nodes, options, broker: broker, exportedAt: at).toMarkdown();
      case DocExportFormat.html:
        return DocBlocks.build(documentation, nodes, options, broker: broker, exportedAt: at).toHtml();
      case DocExportFormat.asyncapiYaml:
        return YamlWriter.write(AsyncApiExporter.build(documentation, nodes, options, broker: broker));
      case DocExportFormat.asyncapiJson:
        return const JsonEncoder.withIndent('  ')
            .convert(AsyncApiExporter.build(documentation, nodes, options, broker: broker));
      case DocExportFormat.jsonSchema:
        return const JsonEncoder.withIndent('  ').convert(jsonSchemaBundle(documentation, nodes));
      case DocExportFormat.csv:
        return CsvExporter.write(nodes);
    }
  }

  static List<DocNode> nodesInScope(TopicDocumentation documentation, String? scope) => [
        for (var node in documentation.nodes)
          if (scope == null || DocPath.isAtOrBelow(node.path, scope)) node
      ];

  // one $defs entry per topic with a documented payload, keyed by its path
  static Map<String, Object?> jsonSchemaBundle(TopicDocumentation documentation, List<DocNode> nodes) => {
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        'title': documentation.title.isEmpty ? 'MQTT topic payloads' : documentation.title,
        r'$defs': {
          for (var node in nodes)
            if (node.topic != null && SchemaJson.ofPayload(node.topic!.payload) != null)
              node.path: {
                if (node.title.isNotEmpty) 'title': node.title,
                ...SchemaJson.ofPayload(node.topic!.payload)!,
              }
        },
      };

  // a key AsyncAPI accepts ([a-zA-Z0-9._-]), the same for the same set of paths
  static Map<DocNode, String> idsOf(Iterable<DocNode> nodes) {
    var ids = <DocNode, String>{};
    var used = <String>{};
    for (var node in nodes) {
      var base = node.path.replaceAll(RegExp(r'[{}]'), '').replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
      base = base.replaceAll(RegExp(r'^_+|_+$'), '');
      if (base.isEmpty) {
        base = 'topic';
      }
      var id = base;
      for (var i = 2; used.contains(id); i++) {
        id = '${base}_$i';
      }
      used.add(id);
      ids[node] = id;
    }
    return ids;
  }

  // host:port and the AsyncAPI protocol of the broker
  static ({String host, String protocol, String protocolVersion}) brokerOf(MqttSettings settings) => (
        host: '${settings.hostname}:${settings.port}',
        protocol: settings.useWebSockets ? (settings.useSsl ? 'wss' : 'ws') : (settings.useSsl ? 'mqtts' : 'mqtt'),
        protocolVersion: settings.isMqtt5 ? '5' : '3.1.1',
      );
}
