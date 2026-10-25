import 'dart:convert';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/documentation/engine/doc_path.dart';
import 'package:mqttstudio/documentation/export/asyncapi_exporter.dart';
import 'package:mqttstudio/documentation/export/schema_json.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:yaml/yaml.dart';

class ImportedDocumentation {
  final TopicDocumentation documentation;
  // the AsyncAPI version of the file
  final String version;
  // parts that were left out
  final List<String> warnings;

  ImportedDocumentation(this.documentation, this.version, this.warnings);
}

// Reads AsyncAPI 3.0 and 2.x documents, YAML or JSON (doc/documentation-design.md §9.3). x-mqttstudio-* extensions
// restore what an MQTT Studio export wrote; unknown parts are left out and listed as warnings.
class AsyncApiImporter {
  static const String prefix = AsyncApiExporter.prefix;

  final Map<String, Object?> _root;
  final List<String> _warnings = [];

  AsyncApiImporter._(this._root);

  // throws FormatException when the text is no AsyncAPI document
  static ImportedDocumentation read(String text) {
    Object? parsed;
    try {
      parsed = _plain(loadYaml(text));
    } on YamlException catch (exc) {
      throw FormatException('Not a YAML or JSON document: ${exc.message}');
    }
    if (parsed is! Map<String, Object?> || parsed['asyncapi'] is! String) {
      throw const FormatException('Not an AsyncAPI document: the "asyncapi" version is missing');
    }
    var version = parsed['asyncapi'] as String;
    var importer = AsyncApiImporter._(parsed);
    var documentation = version.startsWith('3.')
        ? importer._read3()
        : version.startsWith('2.')
            ? importer._read2()
            : throw FormatException('AsyncAPI $version is not supported, only 2.x and 3.x');
    documentation.sortNodes();
    return ImportedDocumentation(documentation, version, importer._warnings);
  }

  static Object? _plain(Object? value) => switch (value) {
        Map map => {for (var entry in map.entries) '${entry.key}': _plain(entry.value)},
        List list => [for (var item in list) _plain(item)],
        _ => value,
      };

  // ---------- AsyncAPI 3.0 ----------

  TopicDocumentation _read3() {
    var documentation = _info();
    var operations = _map(_root['operations']);
    var channels = _map(_root['channels']);
    for (var entry in channels.entries) {
      var channel = _map(_resolve(entry.value));
      var address = channel['address'];
      if (address is! String) {
        _warnings.add('Channel ${entry.key}: no address, left out');
        continue;
      }
      var messages = _map(channel['messages']).values.map((message) => _map(_resolve(message))).toList();
      if (messages.length > 1) {
        _warnings.add('$address: ${messages.length} messages, only the first one is used');
      }
      var operation = operations.values
          .map((operation) => _map(_resolve(operation)))
          .where((operation) => _map(operation['channel'])[r'$ref'] == '#/channels/${entry.key}')
          .firstOrNull;
      var node = _topic(address, channel, messages.firstOrNull, _map(_map(operation?['bindings'])['mqtt']),
          title: _string(channel['title']) ?? _string(operation?['summary']));
      if (node != null) {
        documentation.nodes.add(node);
      }
    }
    _namespaces(documentation);
    return documentation;
  }

  // ---------- AsyncAPI 2.x ----------

  TopicDocumentation _read2() {
    var documentation = _info();
    for (var entry in _map(_root['channels']).entries) {
      var channel = _map(_resolve(entry.value));
      var operation = _map(_resolve(channel['subscribe'] ?? channel['publish']));
      if (channel['subscribe'] != null && channel['publish'] != null) {
        _warnings.add('${entry.key}: publish and subscribe, the subscribe operation is used');
      }
      var message = _map(_resolve(operation['message']));
      if (message['oneOf'] is List) {
        _warnings.add('${entry.key}: several messages, only the first one is used');
        message = _map(_resolve((message['oneOf'] as List).firstOrNull));
      }
      var node = _topic(entry.key, channel, message.isEmpty ? null : message, _map(_map(operation['bindings'])['mqtt']),
          title: _string(channel['title']) ?? _string(operation['summary']));
      if (node != null) {
        documentation.nodes.add(node);
      }
    }
    _namespaces(documentation);
    return documentation;
  }

  // ---------- shared ----------

  TopicDocumentation _info() {
    var info = _map(_root['info']);
    var revision = RegExp(r'^1\.(\d+)$').firstMatch(_string(info['version']) ?? '');
    return TopicDocumentation(
        title: _string(info['title']) ?? '',
        description: _string(info['description']) ?? '',
        owner: _string(info['${prefix}owner']) ?? '',
        revision: revision == null ? 0 : int.parse(revision.group(1)!));
  }

  DocNode? _topic(
      String address, Map<String, Object?> channel, Map<String, Object?>? message, Map<String, Object?> binding,
      {String? title}) {
    var error = DocPath.validate(address);
    if (error != null) {
      _warnings.add('$address: not a documented topic (${error.name}), left out');
      return null;
    }
    var bindingMessage = _map(_map(message?['bindings'])['mqtt']);
    var payloadSchema = message?['payload'];
    // AsyncAPI 3 wraps schemas of other formats as {schemaFormat, schema}
    if (payloadSchema is Map && payloadSchema['schema'] is Map && payloadSchema['schemaFormat'] != null) {
      payloadSchema = payloadSchema['schema'];
    }
    var schemaWarnings = <String>[];
    var payload =
        SchemaJson.payloadOf(payloadSchema is Map ? _map(_resolve(payloadSchema)) : null, warnings: schemaWarnings);
    _warnings.addAll(schemaWarnings.map((warning) => '$address: $warning'));
    payload.encoding = _string(message?['${prefix}encoding']);
    payload.examples = [
      for (var example in _list(message?['examples']).map(_map))
        if (example['payload'] != null)
          DocExample(
              payload: _exampleText(example['payload']), note: _string(example['summary'] ?? example['name']) ?? '')
    ];
    var qos = binding['qos'];
    var retain = _string(channel['${prefix}retain']);
    var topic = TopicSpec(
      payload: payload,
      qos: qos is int && qos >= 0 && qos <= 2 ? MqttQos.values[qos] : null,
      retain: retain != null
          ? RetainMode.values.where((mode) => mode.name == retain).firstOrNull ?? RetainMode.unknown
          : switch (binding['retain']) {
              true => RetainMode.always,
              false => RetainMode.never,
              _ => RetainMode.unknown
            },
      interval: channel['${prefix}interval'] is Map
          ? IntervalSpec.fromJson(_map(channel['${prefix}interval']))
          : IntervalSpec(),
      mqtt5: Mqtt5Spec(
        contentType: _string(bindingMessage['contentType']) ?? _string(message?['contentType']),
        utf8Payload: switch (bindingMessage['payloadFormatIndicator']) { 1 => true, 0 => false, _ => null },
        messageExpirySeconds:
            bindingMessage['messageExpiryInterval'] is int ? bindingMessage['messageExpiryInterval'] as int : null,
        responseTopic: _string(bindingMessage['responseTopic']),
        correlationData: _string(_map(bindingMessage['correlationData'])['description']),
        userProperties: [
          for (var property in _list(message?['${prefix}user-properties']))
            if (property is Map) DocUserProperty.fromJson(_map(property))
        ],
      ),
      producers: _strings(channel['${prefix}producers']),
      consumers: _strings(channel['${prefix}consumers']),
      accessNotes: _string(channel['${prefix}access-notes']) ?? '',
      sensitivity: Sensitivity.values.where((value) => value.name == channel['${prefix}sensitivity']).firstOrNull ??
          Sensitivity.none,
      lastWill: channel['${prefix}last-will'] == true,
    );
    // a plain JSON content type without our marker still means JSON
    if (payload.format == PayloadFormat.unknown && (topic.mqtt5.contentType ?? '').contains('json')) {
      payload.format = PayloadFormat.json;
    }
    var node = _node(address, channel, title: title)..topic = topic;
    if (channel['${prefix}observed'] is Map) {
      try {
        node.observed = ObservedTopic.fromJson(_map(channel['${prefix}observed']));
      } catch (_) {
        _warnings.add('$address: the observed statistics could not be read');
      }
    }
    return node;
  }

  // the texts every node has, from a channel or an x-mqttstudio-namespaces entry
  DocNode _node(String path, Map<String, Object?> source, {String? title, bool namespace = false}) {
    String? field(String name) => _string(source[namespace ? name : '$prefix$name']);
    var externalDocs = _map(source['externalDocs']);
    var node = DocNode(
      path: path,
      title: title ?? _string(source['title']) ?? '',
      description: _string(source['description']) ?? '',
      status: DocStatus.values.where((status) => status.name == field('status')).firstOrNull ?? DocStatus.draft,
      replacedBy: field('replaced-by'),
      owner: field('owner') ?? '',
      tags: [
        for (var tag in _list(source['tags']))
          if (tag is String) tag else if (_string(_map(tag)['name']) != null) _string(_map(tag)['name'])!
      ],
      links: [
        if (_string(externalDocs['url']) != null)
          DocLink(label: _string(externalDocs['description']) ?? '', url: _string(externalDocs['url'])!),
        for (var link in _list(namespace ? source['links'] : source['${prefix}links']))
          if (link is Map) DocLink.fromJson(_map(link)),
      ],
    );
    DocumentationService.syncParameters(node);
    var parameters = _map(source['parameters']);
    for (var parameter in node.parameters) {
      var definition = _map(_resolve(parameters[parameter.name]));
      parameter
        ..description = _string(definition['description']) ?? ''
        ..pattern = _string(definition['${prefix}pattern']) ?? _string(_map(definition['schema'])['pattern'])
        ..examples = _strings(definition['examples']).isNotEmpty
            ? _strings(definition['examples'])
            : _strings(definition['enum']);
    }
    return node;
  }

  void _namespaces(TopicDocumentation documentation) {
    for (var entry in _list(_root['${prefix}namespaces']).map(_map)) {
      var path = _string(entry['path']);
      if (path == null || DocPath.validate(path) != null || documentation.nodeAt(path) != null) {
        _warnings.add('Namespace ${path ?? '?'}: left out');
        continue;
      }
      documentation.nodes.add(_node(path, entry, namespace: true));
    }
  }

  // follows a local reference like #/components/messages/status; others are left out
  Object? _resolve(Object? value) {
    for (var depth = 0; depth < 10; depth++) {
      var reference = value is Map ? value[r'$ref'] : null;
      if (reference is! String) {
        return value;
      }
      if (!reference.startsWith('#/')) {
        _warnings.add('Reference $reference: only references inside the document are followed');
        return null;
      }
      Object? target = _root;
      for (var part in reference.substring(2).split('/')) {
        target = target is Map ? target[part.replaceAll('~1', '/').replaceAll('~0', '~')] : null;
      }
      value = target;
    }
    return value;
  }

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? value.map((key, value) => MapEntry('$key', value)) : <String, Object?>{};

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  static String? _string(Object? value) => value is String ? value : (value is num || value is bool ? '$value' : null);

  static List<String> _strings(Object? value) => [
        for (var item in _list(value))
          if (item != null) '$item'
      ];

  static String _exampleText(Object? payload) => payload is String ? payload : jsonEncode(payload);
}
