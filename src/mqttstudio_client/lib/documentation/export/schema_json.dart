import 'package:mqttstudio/documentation/model/topic_spec.dart';

// Converts payload schemas to JSON Schema (draft 2020-12, the subset of doc/documentation-design.md §5.4) and back
class SchemaJson {
  static const String unitKey = 'x-unit';
  static const String formatKey = 'x-mqttstudio-format';

  static Map<String, Object?> toJsonSchema(SchemaNode node) {
    var type = _typeName(node.type);
    return {
      if (type != null) 'type': type,
      if (node.description.isNotEmpty) 'description': node.description,
      if (node.format != null) 'format': node.format,
      if (node.unit != null) unitKey: node.unit,
      if (node.minimum != null) 'minimum': _number(node.minimum!),
      if (node.maximum != null) 'maximum': _number(node.maximum!),
      if (node.enumValues.isNotEmpty) 'enum': [for (var value in node.enumValues) _enumValue(value, node.type)],
      if (node.properties.isNotEmpty)
        'properties': {for (var entry in node.properties.entries) entry.key: toJsonSchema(entry.value)},
      if (node.required.isNotEmpty) 'required': node.required.toList()..sort(),
      if (node.items != null) 'items': toJsonSchema(node.items!),
    };
  }

  // the schema of a payload: the JSON schema for JSON, a simple one for the other formats; null when undocumented
  static Map<String, Object?>? ofPayload(PayloadSpec payload) {
    var range = <String, Object?>{
      if (payload.unit != null) unitKey: payload.unit,
      if (payload.min != null) 'minimum': _number(payload.min!),
      if (payload.max != null) 'maximum': _number(payload.max!),
    };
    var schema = switch (payload.format) {
      PayloadFormat.json => payload.schema == null ? <String, Object?>{} : toJsonSchema(payload.schema!),
      PayloadFormat.number => <String, Object?>{'type': 'number', ...range},
      PayloadFormat.boolean => <String, Object?>{'type': 'boolean'},
      PayloadFormat.string => <String, Object?>{'type': 'string'},
      PayloadFormat.gnss => <String, Object?>{'type': 'string', 'description': 'latitude,longitude'},
      PayloadFormat.binary || PayloadFormat.image => <String, Object?>{'type': 'string', 'format': 'binary'},
      PayloadFormat.empty => <String, Object?>{'type': 'null'},
      PayloadFormat.unknown => null,
    };
    if (schema == null) {
      return null;
    }
    if (payload.allowedValues.isNotEmpty && payload.format != PayloadFormat.json) {
      schema['enum'] = [
        for (var value in payload.allowedValues)
          payload.format == PayloadFormat.number ? (num.tryParse(value) ?? value) : value
      ];
    }
    schema[formatKey] = payload.format.name;
    return schema;
  }

  // reads a JSON Schema; keywords outside the subset are left out and named in warnings
  static SchemaNode fromJsonSchema(Map<String, Object?> json, {List<String>? warnings, String path = r'$'}) {
    for (var key in json.keys) {
      if (!_known.contains(key) && !key.startsWith('x-')) {
        warnings?.add('$path: "$key" is not supported and was left out');
      }
    }
    var properties = json['properties'];
    var items = json['items'];
    return SchemaNode(
      type: _typeOf(json['type'], hasProperties: properties is Map),
      description: json['description'] is String ? json['description'] as String : '',
      unit: json[unitKey] is String ? json[unitKey] as String : null,
      format: json['format'] is String ? json['format'] as String : null,
      minimum: json['minimum'] is num ? (json['minimum'] as num).toDouble() : null,
      maximum: json['maximum'] is num ? (json['maximum'] as num).toDouble() : null,
      enumValues: json['enum'] is List ? [for (var value in json['enum'] as List) '$value'] : [],
      properties: properties is Map
          ? {
              for (var entry in properties.entries)
                if (entry.value is Map)
                  '${entry.key}': fromJsonSchema(_map(entry.value), warnings: warnings, path: '$path.${entry.key}')
            }
          : {},
      required: json['required'] is List ? {for (var name in json['required'] as List) '$name'} : {},
      items: items is Map ? fromJsonSchema(_map(items), warnings: warnings, path: '$path[]') : null,
    );
  }

  // the payload of a message: format, unit, range and allowed values for simple payloads, the schema for JSON
  static PayloadSpec payloadOf(Map<String, Object?>? schema, {List<String>? warnings}) {
    if (schema == null) {
      return PayloadSpec();
    }
    var marked = PayloadFormat.values.where((format) => format.name == schema[formatKey]).firstOrNull;
    var type = schema['type'];
    var format = marked ??
        switch (type) {
          'number' || 'integer' => PayloadFormat.number,
          'boolean' => PayloadFormat.boolean,
          'string' => schema['format'] == 'binary' ? PayloadFormat.binary : PayloadFormat.string,
          'null' => PayloadFormat.empty,
          _ => PayloadFormat.json,
        };
    if (format == PayloadFormat.json) {
      var copy = Map.of(schema)..remove(formatKey);
      return PayloadSpec(format: format, schema: copy.isEmpty ? null : fromJsonSchema(copy, warnings: warnings));
    }
    return PayloadSpec(
      format: format,
      unit: schema[unitKey] is String ? schema[unitKey] as String : null,
      min: schema['minimum'] is num ? (schema['minimum'] as num).toDouble() : null,
      max: schema['maximum'] is num ? (schema['maximum'] as num).toDouble() : null,
      allowedValues: schema['enum'] is List ? [for (var value in schema['enum'] as List) '$value'] : [],
    );
  }

  static const Set<String> _known = {
    'type',
    'description',
    'format',
    'minimum',
    'maximum',
    'enum',
    'properties',
    'required',
    'items',
    r'$schema',
    'title',
    r'$id',
    'examples',
    'default',
  };

  static Map<String, Object?> _map(Object? value) => (value as Map).map((key, value) => MapEntry('$key', value));

  static Object? _typeName(SchemaType type) => switch (type) {
        SchemaType.nullValue => 'null',
        SchemaType.mixed => null,
        _ => type.name,
      };

  static SchemaType _typeOf(Object? type, {required bool hasProperties}) {
    if (type is List) {
      var real = type.where((name) => name != 'null').toList();
      return real.length == 1 ? _typeOf(real.single, hasProperties: hasProperties) : SchemaType.mixed;
    }
    return switch (type) {
      'object' => SchemaType.object,
      'array' => SchemaType.array,
      'string' => SchemaType.string,
      'number' => SchemaType.number,
      'integer' => SchemaType.integer,
      'boolean' => SchemaType.boolean,
      'null' => SchemaType.nullValue,
      _ => hasProperties ? SchemaType.object : SchemaType.mixed,
    };
  }

  static num _number(double value) => value == value.roundToDouble() && value.abs() < 1e15 ? value.toInt() : value;

  static Object _enumValue(String value, SchemaType type) =>
      type == SchemaType.number || type == SchemaType.integer ? (num.tryParse(value) ?? value) : value;
}
