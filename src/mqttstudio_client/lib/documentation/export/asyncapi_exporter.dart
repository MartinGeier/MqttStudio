import 'dart:convert';
import 'package:mqttstudio/documentation/export/doc_export.dart';
import 'package:mqttstudio/documentation/export/schema_json.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';

// Builds an AsyncAPI 3.0 document (doc/documentation-design.md §9.2): one channel, message and receive operation per
// documented topic. What AsyncAPI has no field for goes into x-mqttstudio-* extensions, so an export imports again
// without loss.
class AsyncApiExporter {
  static const String version = '3.0.0';
  static const String mqttBindingVersion = '0.2.0';
  static const String prefix = 'x-mqttstudio-';

  static Map<String, Object?> build(TopicDocumentation documentation, List<DocNode> nodes, DocExportOptions options,
      {MqttSettings? broker}) {
    var topics = nodes.where((node) => node.isTopic).toList();
    var namespaces = nodes.where((node) => !node.isTopic).toList();
    var ids = DocExport.idsOf(topics);
    var server = broker == null || !options.includeBroker ? null : DocExport.brokerOf(broker);
    return {
      'asyncapi': version,
      'info': {
        'title': documentation.title.isEmpty ? 'MQTT topics' : documentation.title,
        'version': '1.${documentation.revision}',
        if (documentation.description.isNotEmpty) 'description': documentation.description,
        if (documentation.owner.isNotEmpty) '${prefix}owner': documentation.owner,
      },
      if (server != null)
        'servers': {
          'broker': {'host': server.host, 'protocol': server.protocol, 'protocolVersion': server.protocolVersion}
        },
      'channels': {for (var node in topics) ids[node]!: _channel(node, ids[node]!, options)},
      'operations': {for (var node in topics) ids[node]!: _operation(node, ids[node]!)},
      'components': {
        'messages': {for (var node in topics) ids[node]!: _message(node, options)}
      },
      if (namespaces.isNotEmpty) '${prefix}namespaces': [for (var node in namespaces) _namespace(node)],
    };
  }

  static Map<String, Object?> _channel(DocNode node, String id, DocExportOptions options) {
    var topic = node.topic!;
    var links = node.links.where((link) => link.url.isNotEmpty).toList();
    return {
      'address': node.path,
      if (node.title.isNotEmpty) 'title': node.title,
      if (node.description.isNotEmpty) 'description': node.description,
      if (node.parameters.isNotEmpty)
        'parameters': {for (var parameter in node.parameters) parameter.name: _parameter(parameter)},
      'messages': {
        id: {r'$ref': '#/components/messages/$id'}
      },
      if (node.tags.isNotEmpty)
        'tags': [
          for (var tag in node.tags) {'name': tag}
        ],
      if (links.isNotEmpty)
        'externalDocs': {'url': links.first.url, if (links.first.label.isNotEmpty) 'description': links.first.label},
      if (links.length > 1) '${prefix}links': [for (var link in links.skip(1)) link.toJson()],
      '${prefix}status': node.status.name,
      if (node.replacedBy != null) '${prefix}replaced-by': node.replacedBy,
      if (node.owner.isNotEmpty) '${prefix}owner': node.owner,
      '${prefix}interval': topic.interval.toJson()..removeWhere((_, value) => value == null),
      if (topic.retain != RetainMode.unknown) '${prefix}retain': topic.retain.name,
      if (topic.sensitivity != Sensitivity.none) '${prefix}sensitivity': topic.sensitivity.name,
      if (topic.producers.isNotEmpty) '${prefix}producers': topic.producers,
      if (topic.consumers.isNotEmpty) '${prefix}consumers': topic.consumers,
      if (topic.lastWill) '${prefix}last-will': true,
      if (topic.accessNotes.isNotEmpty) '${prefix}access-notes': topic.accessNotes,
      if (options.includeObserved && node.observed != null) '${prefix}observed': node.observed!.toJson(),
    };
  }

  static Map<String, Object?> _parameter(DocParameter parameter) => {
        if (parameter.description.isNotEmpty) 'description': parameter.description,
        if (parameter.examples.isNotEmpty) 'examples': parameter.examples,
        if (parameter.pattern != null) '${prefix}pattern': parameter.pattern,
      };

  static Map<String, Object?> _operation(DocNode node, String id) {
    var topic = node.topic!;
    var retain = switch (topic.retain) { RetainMode.always => true, RetainMode.never => false, _ => null };
    var binding = {
      if (topic.qos != null) 'qos': topic.qos!.index,
      if (retain != null) 'retain': retain,
    };
    return {
      'action': 'receive',
      'channel': {r'$ref': '#/channels/$id'},
      if (node.title.isNotEmpty) 'summary': node.title,
      if (binding.isNotEmpty)
        'bindings': {
          'mqtt': {...binding, 'bindingVersion': mqttBindingVersion}
        },
    };
  }

  static Map<String, Object?> _message(DocNode node, DocExportOptions options) {
    var topic = node.topic!;
    var payload = topic.payload;
    var mqtt5 = topic.mqtt5;
    var binding = <String, Object?>{
      if (mqtt5.utf8Payload != null) 'payloadFormatIndicator': mqtt5.utf8Payload! ? 1 : 0,
      if (mqtt5.contentType != null) 'contentType': mqtt5.contentType,
      if (mqtt5.messageExpirySeconds != null) 'messageExpiryInterval': mqtt5.messageExpirySeconds,
      if (mqtt5.responseTopic != null) 'responseTopic': mqtt5.responseTopic,
      if (mqtt5.correlationData != null) 'correlationData': {'type': 'string', 'description': mqtt5.correlationData},
    };
    var schema = SchemaJson.ofPayload(payload);
    var examples = options.includeExamples
        ? payload.examples.where((example) => example.payload.isNotEmpty).toList()
        : <DocExample>[];
    return {
      'name': node.path,
      if (node.title.isNotEmpty) 'title': node.title,
      if (mqtt5.contentType != null)
        'contentType': mqtt5.contentType
      else if (payload.format == PayloadFormat.json)
        'contentType': 'application/json',
      if (schema != null) 'payload': schema,
      if (examples.isNotEmpty)
        'examples': [
          for (var example in examples)
            {
              'payload': _examplePayload(example.payload, payload.format),
              if (example.note.isNotEmpty) 'summary': example.note,
            }
        ],
      if (binding.isNotEmpty)
        'bindings': {
          'mqtt': {...binding, 'bindingVersion': mqttBindingVersion}
        },
      if (payload.encoding != null) '${prefix}encoding': payload.encoding,
      if (mqtt5.userProperties.isNotEmpty)
        '${prefix}user-properties': [for (var property in mqtt5.userProperties) property.toJson()],
    };
  }

  // JSON examples stay JSON in the document; everything else is text
  static Object? _examplePayload(String text, PayloadFormat format) {
    if (format == PayloadFormat.json) {
      try {
        return jsonDecode(text);
      } on FormatException {
        return text;
      }
    }
    return text;
  }

  static Map<String, Object?> _namespace(DocNode node) => {
        'path': node.path,
        if (node.title.isNotEmpty) 'title': node.title,
        if (node.description.isNotEmpty) 'description': node.description,
        'status': node.status.name,
        if (node.owner.isNotEmpty) 'owner': node.owner,
        if (node.tags.isNotEmpty) 'tags': node.tags,
        if (node.links.isNotEmpty) 'links': [for (var link in node.links) link.toJson()],
        if (node.parameters.isNotEmpty)
          'parameters': {for (var parameter in node.parameters) parameter.name: _parameter(parameter)},
      };
}
