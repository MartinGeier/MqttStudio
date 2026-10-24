import 'package:mqttstudio/documentation/engine/schema_paths.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';

// Merges JSON payloads into a SchemaNode (doc/documentation-design.md §5.4): types per field, which fields every
// object has, whole numbers, ISO 8601 strings, a few distinct strings as an enum, and the observed number ranges.
class SchemaInferrer {
  static const int maxDepth = 12;
  static const int maxProperties = 200;
  // more distinct strings than this are not kept
  static const int maxStrings = 16;
  static const int maxEnumValues = 8;
  static const int minEnumSamples = 20;

  static final RegExp _dateTime = RegExp(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?$');

  final _FieldStats _root = _FieldStats();
  int samples = 0;

  void add(Object? json) {
    samples++;
    _root.add(json, 0);
  }

  // merges what another inferrer saw, e.g. of another instance of a template
  void merge(SchemaInferrer other) {
    samples += other.samples;
    _root.merge(other._root);
  }

  SchemaNode build() => _root.build();

  // field path and the share of all samples that had the field, 0..1
  Map<String, double> presence() {
    var result = <String, double>{};
    void walk(_FieldStats stats, String path) {
      for (var entry in stats.properties.entries) {
        var childPath = '$path.${entry.key}';
        result[childPath] = samples == 0 ? 0 : entry.value.count / samples;
        walk(entry.value, childPath);
      }
      var items = stats.items;
      if (items != null) {
        var childPath = '$path${SchemaPaths.items}';
        result[childPath] = samples == 0 ? 0 : stats.arrayCount / samples;
        walk(items, childPath);
      }
    }

    walk(_root, SchemaPaths.root);
    return result;
  }
}

class _FieldStats {
  int count = 0;
  int objectCount = 0;
  int arrayCount = 0;
  final Set<String> types = {};
  bool allInteger = true;
  bool allDateTime = true;
  double? minimum;
  double? maximum;
  // null once more than SchemaInferrer.maxStrings distinct values were seen
  Set<String>? strings = {};
  int stringCount = 0;
  final Map<String, _FieldStats> properties = {};
  _FieldStats? items;

  void add(Object? value, int depth) {
    count++;
    switch (value) {
      case null:
        types.add('null');
      case bool _:
        types.add('boolean');
      case num number:
        types.add('number');
        if (number != number.roundToDouble()) {
          allInteger = false;
        }
        var asDouble = number.toDouble();
        minimum = minimum == null || asDouble < minimum! ? asDouble : minimum;
        maximum = maximum == null || asDouble > maximum! ? asDouble : maximum;
      case String text:
        types.add('string');
        stringCount++;
        if (!SchemaInferrer._dateTime.hasMatch(text)) {
          allDateTime = false;
        }
        var kept = strings;
        if (kept != null && (kept.contains(text) || kept.length < SchemaInferrer.maxStrings)) {
          kept.add(text);
        } else {
          strings = null;
        }
      case Map<String, dynamic> object:
        types.add('object');
        objectCount++;
        if (depth >= SchemaInferrer.maxDepth) {
          return;
        }
        for (var entry in object.entries) {
          var child = properties[entry.key];
          if (child == null) {
            if (properties.length >= SchemaInferrer.maxProperties) {
              continue;
            }
            child = properties[entry.key] = _FieldStats();
          }
          child.add(entry.value, depth + 1);
        }
      case List<dynamic> list:
        types.add('array');
        arrayCount++;
        if (depth >= SchemaInferrer.maxDepth) {
          return;
        }
        for (var item in list) {
          (items ??= _FieldStats()).add(item, depth + 1);
        }
      default:
        types.add('mixed');
    }
  }

  void merge(_FieldStats other) {
    count += other.count;
    objectCount += other.objectCount;
    arrayCount += other.arrayCount;
    types.addAll(other.types);
    allInteger = allInteger && other.allInteger;
    allDateTime = allDateTime && other.allDateTime;
    if (other.minimum != null && (minimum == null || other.minimum! < minimum!)) {
      minimum = other.minimum;
    }
    if (other.maximum != null && (maximum == null || other.maximum! > maximum!)) {
      maximum = other.maximum;
    }
    stringCount += other.stringCount;
    var mine = strings;
    var theirs = other.strings;
    strings = mine == null || theirs == null || mine.union(theirs).length > SchemaInferrer.maxStrings
        ? null
        : mine.union(theirs);
    for (var entry in other.properties.entries) {
      (properties[entry.key] ??= _FieldStats()).merge(entry.value);
    }
    if (other.items != null) {
      (items ??= _FieldStats()).merge(other.items!);
    }
  }

  SchemaType get type {
    var real = types.difference({'null'});
    if (real.isEmpty) {
      return SchemaType.nullValue;
    }
    if (real.length > 1) {
      return SchemaType.mixed;
    }
    return switch (real.single) {
      'object' => SchemaType.object,
      'array' => SchemaType.array,
      'string' => SchemaType.string,
      'boolean' => SchemaType.boolean,
      'number' => allInteger ? SchemaType.integer : SchemaType.number,
      _ => SchemaType.mixed,
    };
  }

  SchemaNode build() {
    var type = this.type;
    var isNumber = type == SchemaType.number || type == SchemaType.integer;
    var isString = type == SchemaType.string;
    var values = strings;
    var isEnum = isString &&
        values != null &&
        values.length <= SchemaInferrer.maxEnumValues &&
        stringCount >= SchemaInferrer.minEnumSamples &&
        !allDateTime;
    return SchemaNode(
      type: type,
      format: isString && allDateTime && stringCount > 0 ? 'date-time' : null,
      minimum: isNumber ? minimum : null,
      maximum: isNumber ? maximum : null,
      enumValues: isEnum ? (values.toList()..sort()) : [],
      properties: {for (var entry in properties.entries) entry.key: entry.value.build()},
      required: {
        for (var entry in properties.entries)
          if (entry.value.count >= objectCount && objectCount > 0) entry.key
      },
      items: items?.build(),
    );
  }
}
