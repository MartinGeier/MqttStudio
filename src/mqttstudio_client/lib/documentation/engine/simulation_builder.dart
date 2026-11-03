import 'dart:convert';
import 'dart:math';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/engine/doc_path.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';

// Builds simulated devices from documented topics (doc/documentation-design.md §8.2): the payload generator follows
// the documented format, range, allowed values and schema; the interval, QoS and retain come from the documentation.
class SimulationBuilder {
  static const int defaultIntervalMs = 1000;
  static final RegExp _digits = RegExp(r'^\d+$');

  // one device per documented topic; its first parameter becomes {n}
  static SimulatedDevice deviceOf(DocNode node, String name) {
    var path = DocPath.parse(node.path);
    var first = path.segments.where((segment) => segment.isParameter).firstOrNull;
    var values = first == null ? <String>[] : _valuesOf(node, first.parameter!);
    var numbers = values.where(_digits.hasMatch).map(int.parse).toList();
    var instances = first == null ? 1 : max(1, min(values.length, SimulationRules.maxInstances));
    var topic = [
      for (var segment in path.segments)
        if (!segment.isParameter)
          segment.prefix
        else if (identical(segment, first))
          '${segment.prefix}{n}${segment.suffix}'
        else
          '${segment.prefix}${_valuesOf(node, segment.parameter!).firstOrNull ?? segment.parameter}${segment.suffix}'
    ].join('/');
    return SimulatedDevice(
      name: name,
      instanceCount: instances,
      firstInstance: numbers.length == values.length && numbers.isNotEmpty ? numbers.reduce(min) : 1,
      topics: [_topic(node, topic)],
    );
  }

  static List<String> _valuesOf(DocNode node, String parameter) {
    var observed = node.observed?.parameterValues[parameter];
    if (observed != null && observed.isNotEmpty) {
      return observed;
    }
    return node.parameters.where((p) => p.name == parameter).firstOrNull?.examples ?? [];
  }

  static SimulatedTopic _topic(DocNode node, String topic) {
    var spec = node.topic!;
    return SimulatedTopic(
      topic: topic,
      generator: generatorOf(node),
      qos: spec.qos ?? MqttQos.atMostOnce,
      retain: spec.retain == RetainMode.always,
      interval: _interval(node),
      mqtt5: Mqtt5PublishProperties(
        contentType: spec.mqtt5.contentType,
        messageExpirySeconds: spec.mqtt5.messageExpirySeconds,
        userProperties: [
          for (var property in spec.mqtt5.userProperties)
            if (property.key.isNotEmpty) SimulatedUserProperty(property.key, property.example)
        ],
      ),
    );
  }

  static PublishInterval _interval(DocNode node) {
    var spec = node.topic!.interval;
    var observed = node.observed?.interval;
    int bounded(int? ms) => max(SimulationRules.minIntervalMs, ms ?? defaultIntervalMs);
    // an event-driven topic sends now and then: a random interval between the usual short and long ones
    if (spec.kind == IntervalKind.event || spec.kind == IntervalKind.onChange) {
      var low = bounded(observed?.p10Ms ?? spec.nominalMs);
      var high = max(low, bounded(observed?.p90Ms ?? (spec.nominalMs == null ? null : spec.nominalMs! * 3)));
      return PublishInterval(minMs: low, maxMs: high);
    }
    return PublishInterval(minMs: bounded(spec.nominalMs ?? observed?.medianMs));
  }

  static PayloadGenerator generatorOf(DocNode node) {
    var payload = node.topic!.payload;
    var observed = node.observed;
    var examples = payload.examples.map((example) => example.payload).where((text) => text.isNotEmpty).toList();
    if (payload.allowedValues.isNotEmpty && payload.format != PayloadFormat.json) {
      return ValueListGenerator(values: payload.allowedValues);
    }
    switch (payload.format) {
      case PayloadFormat.number:
        return _number(payload.min ?? observed?.numericMin, payload.max ?? observed?.numericMax);
      case PayloadFormat.boolean:
        return const BoolGenerator();
      case PayloadFormat.string:
        return const RandomStringGenerator();
      case PayloadFormat.json:
        var schema = payload.schema ?? observed?.schema;
        if (schema != null) {
          return _template(schema);
        }
        return examples.isEmpty ? TemplateGenerator.example() : ValueListGenerator(values: examples);
      case PayloadFormat.image:
        return const RandomImageGenerator();
      case PayloadFormat.gnss:
        return const GpsTrackGenerator();
      case PayloadFormat.binary || PayloadFormat.empty || PayloadFormat.unknown:
        return examples.isEmpty ? const RandomStringGenerator() : ValueListGenerator(values: examples);
    }
  }

  // a random walk inside the documented or observed range, else random numbers
  static PayloadGenerator _number(double? low, double? high) {
    if (low == null || high == null || high <= low) {
      return RandomNumberGenerator(min: low ?? 0, max: low == null ? 100 : low + 100);
    }
    var whole = low == low.roundToDouble() && high == high.roundToDouble();
    return RandomWalkGenerator(
        start: (low + high) / 2, min: low, max: high, volatility: (high - low) / 50, decimals: whole ? 0 : 1);
  }

  // a template with one field per schema leaf, named after its path
  static TemplateGenerator _template(SchemaNode schema) {
    var fields = <String, PayloadGenerator>{};
    String fieldName(String path) {
      var name = path.replaceAll(r'$', '').replaceAll('[]', '_item').replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_');
      name = name.replaceAll(RegExp(r'^_+|_+$'), '');
      if (name.isEmpty || RegExp(r'^\d').hasMatch(name)) {
        name = 'f_$name';
      }
      var unique = name;
      for (var i = 2; fields.containsKey(unique); i++) {
        unique = '${name}_$i';
      }
      return unique;
    }

    String value(SchemaNode node, String path, String indent) {
      switch (node.type) {
        case SchemaType.object:
          if (node.properties.isEmpty) {
            return '{}';
          }
          var inner = '$indent  ';
          var entries = [
            for (var entry in node.properties.entries)
              '$inner${jsonEncode(entry.key)}: ${value(entry.value, '$path.${entry.key}', inner)}'
          ];
          return '{\n${entries.join(',\n')}\n$indent}';
        case SchemaType.array:
          var items = node.items;
          return items == null ? '[]' : '[${value(items, '$path[]', indent)}]';
        case SchemaType.number || SchemaType.integer:
          var name = fieldName(path);
          fields[name] = node.enumValues.isNotEmpty
              ? ValueListGenerator(values: node.enumValues)
              : node.type == SchemaType.integer
                  ? _integer(node.minimum, node.maximum)
                  : _number(node.minimum, node.maximum);
          return '{{$name}}';
        case SchemaType.boolean:
          var name = fieldName(path);
          fields[name] = const BoolGenerator();
          return '{{$name}}';
        case SchemaType.string:
          var name = fieldName(path);
          fields[name] = node.enumValues.isNotEmpty
              ? ValueListGenerator(values: node.enumValues)
              : node.format == 'date-time'
                  ? const TimestampGenerator()
                  : const RandomStringGenerator();
          return '"{{$name}}"';
        case SchemaType.nullValue || SchemaType.mixed:
          return 'null';
      }
    }

    return TemplateGenerator(template: value(schema, r'$', ''), fields: fields);
  }

  static PayloadGenerator _integer(double? low, double? high) {
    if (low == null || high == null || high <= low) {
      return RandomNumberGenerator(min: low ?? 0, max: low == null ? 100 : low + 100);
    }
    return RandomWalkGenerator(
        start: ((low + high) / 2).roundToDouble(), min: low, max: high, volatility: (high - low) / 50, decimals: 0);
  }
}
