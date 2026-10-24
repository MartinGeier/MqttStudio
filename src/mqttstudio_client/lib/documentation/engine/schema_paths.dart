import 'package:mqttstudio/documentation/model/topic_spec.dart';

class SchemaRow {
  final String path;
  final SchemaNode node;
  // only properties can be required, array items cannot
  final bool required;

  SchemaRow(this.path, this.node, this.required);
}

// Field paths of a payload schema, as the schema table shows them: $ is the payload, .name a property and [] the
// items of an array, e.g. $.alarms[].code. Names with '.', '[' or ']' can't be written this way.
class SchemaPaths {
  static const String root = r'$';
  static const String items = '[]';
  static final RegExp _step = RegExp(r'\.([^.\[\]]+)|\[\]');

  // the steps of a path (property names and '[]'), null when the path is not valid
  static List<String>? parse(String path) {
    if (!path.startsWith(root)) {
      return null;
    }
    var steps = <String>[];
    var position = root.length;
    while (position < path.length) {
      var match = _step.matchAsPrefix(path, position);
      if (match == null) {
        return null;
      }
      steps.add(match.group(1) ?? items);
      position = match.end;
    }
    return steps.isEmpty ? null : steps;
  }

  static String join(List<String> steps) => root + steps.map((step) => step == items ? items : '.$step').join();

  static List<SchemaRow> flatten(SchemaNode? schema) {
    var rows = <SchemaRow>[];
    void add(SchemaNode node, String path) {
      for (var entry in node.properties.entries) {
        var childPath = '$path.${entry.key}';
        rows.add(SchemaRow(childPath, entry.value, node.required.contains(entry.key)));
        add(entry.value, childPath);
      }
      var itemNode = node.items;
      if (itemNode != null) {
        var childPath = '$path$items';
        rows.add(SchemaRow(childPath, itemNode, false));
        add(itemNode, childPath);
      }
    }

    if (schema != null) {
      add(schema, root);
    }
    return rows;
  }

  static SchemaNode? find(SchemaNode? schema, String path) {
    var steps = parse(path);
    if (schema == null || steps == null) {
      return null;
    }
    SchemaNode? node = schema;
    for (var step in steps) {
      node = step == items ? node?.items : node?.properties[step];
    }
    return node;
  }

  // sets the field at path, creating the objects and arrays above it. The field keeps the fields below it.
  static void put(SchemaNode schema, String path, SchemaNode field, {required bool required}) {
    var steps = parse(path)!;
    var parent = schema;
    for (var step in steps.take(steps.length - 1)) {
      parent = _child(parent, step);
    }
    var last = steps.last;
    var existing = last == items ? parent.items : parent.properties[last];
    if (existing != null) {
      field.properties = existing.properties;
      field.required = existing.required;
      field.items ??= existing.items;
    }
    if (last == items) {
      _makeArray(parent);
      parent.items = field;
    } else {
      _makeObject(parent);
      parent.properties[last] = field;
      if (required) {
        parent.required.add(last);
      } else {
        parent.required.remove(last);
      }
    }
  }

  static void remove(SchemaNode schema, String path) {
    var steps = parse(path);
    if (steps == null) {
      return;
    }
    var parent = steps.length == 1 ? schema : find(schema, join(steps.sublist(0, steps.length - 1)));
    if (parent == null) {
      return;
    }
    if (steps.last == items) {
      parent.items = null;
    } else {
      parent.properties.remove(steps.last);
      parent.required.remove(steps.last);
    }
  }

  static SchemaNode _child(SchemaNode parent, String step) {
    if (step == items) {
      _makeArray(parent);
      return parent.items ??= SchemaNode();
    }
    _makeObject(parent);
    return parent.properties.putIfAbsent(step, SchemaNode.new);
  }

  static void _makeObject(SchemaNode node) {
    if (node.type != SchemaType.object && node.type != SchemaType.mixed) {
      node.type = SchemaType.object;
    }
  }

  static void _makeArray(SchemaNode node) {
    if (node.type != SchemaType.array && node.type != SchemaType.mixed) {
      node.type = SchemaType.array;
    }
  }
}
