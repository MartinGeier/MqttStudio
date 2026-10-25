import 'package:mqttstudio/documentation/engine/schema_paths.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';

enum SchemaIssueKind { type, required, notAllowed, range }

class SchemaIssue {
  final SchemaIssueKind kind;
  final String path;
  final String message;

  SchemaIssue(this.kind, this.path, this.message);
}

// Checks a decoded JSON payload against a documented schema (doc/documentation-design.md §7): types, required fields,
// allowed values and ranges. Fields the schema doesn't mention are fine.
class SchemaValidator {
  static const int maxIssues = 20;

  static List<SchemaIssue> validate(SchemaNode schema, Object? value) {
    var issues = <SchemaIssue>[];
    _check(schema, value, SchemaPaths.root, issues);
    return issues;
  }

  static void _check(SchemaNode schema, Object? value, String path, List<SchemaIssue> issues) {
    if (issues.length >= maxIssues) {
      return;
    }
    if (!_typeMatches(schema.type, value)) {
      issues.add(SchemaIssue(SchemaIssueKind.type, path, 'is ${_typeOf(value)}, documented ${_typeName(schema.type)}'));
      return;
    }
    if (schema.enumValues.isNotEmpty && value != null && !schema.enumValues.contains(_text(value))) {
      issues.add(SchemaIssue(
          SchemaIssueKind.notAllowed, path, '${_text(value)} is not one of ${schema.enumValues.join(', ')}'));
    }
    if (value is num) {
      if (schema.minimum != null && value < schema.minimum!) {
        issues.add(
            SchemaIssue(SchemaIssueKind.range, path, '${_text(value)} is below the minimum ${_text(schema.minimum)}'));
      }
      if (schema.maximum != null && value > schema.maximum!) {
        issues.add(
            SchemaIssue(SchemaIssueKind.range, path, '${_text(value)} is above the maximum ${_text(schema.maximum)}'));
      }
    }
    if (value is Map) {
      for (var name in schema.required) {
        if (!value.containsKey(name)) {
          issues.add(SchemaIssue(SchemaIssueKind.required, '$path.$name', 'is missing'));
        }
      }
      for (var entry in schema.properties.entries) {
        if (value.containsKey(entry.key)) {
          _check(entry.value, value[entry.key], '$path.${entry.key}', issues);
        }
      }
    }
    var items = schema.items;
    if (value is List && items != null) {
      for (var item in value) {
        _check(items, item, '$path${SchemaPaths.items}', issues);
      }
    }
  }

  static bool _typeMatches(SchemaType type, Object? value) =>
      switch (type) {
        SchemaType.mixed => true,
        SchemaType.object => value is Map,
        SchemaType.array => value is List,
        SchemaType.string => value is String,
        SchemaType.number => value is num,
        SchemaType.integer => value is num && value == value.roundToDouble(),
        SchemaType.boolean => value is bool,
        SchemaType.nullValue => value == null,
      } ||
      // a documented field may be null now and then
      (value == null && type != SchemaType.nullValue);

  static String _typeOf(Object? value) => switch (value) {
        null => 'null',
        bool _ => 'a boolean',
        num _ => 'a number',
        String _ => 'a string',
        List _ => 'an array',
        Map _ => 'an object',
        _ => 'something else',
      };

  static String _typeName(SchemaType type) => type == SchemaType.nullValue ? 'null' : type.name;

  static String _text(Object? value) {
    if (value is double && value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    return '$value';
  }
}
