import 'package:flutter/services.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:yaml/yaml.dart';

// The official JSON schemas of VDA 5050 2.1.0 and 3.0.0 (github.com/VDA5050/VDA5050, MIT licence in
// assets/vda5050/LICENSE.txt), bundled unchanged as assets. Some 3.0.0 files have trailing commas, which strict JSON
// rejects, so they are read with the YAML parser.
class Vda5050Schemas {
  static const String assetFolder = 'assets/vda5050';

  // the keywords MQTT Studio's documentation keeps (doc/documentation-design.md §5.4)
  static const Set<String> _kept = {
    'type', 'description', 'format', 'minimum', 'maximum', 'enum', 'properties', 'required', 'items', //
  };

  static List<String> topicsOf(VdaVersion version) =>
      VdaTopic.all.where((topic) => version.isV3 || !VdaTopic.isV3Only(topic)).toList();

  static String assetOf(VdaVersion version, String topic) => '$assetFolder/${version.protocolVersion}/$topic.schema';

  // the schema of each topic as published
  static Future<Map<String, Map<String, Object?>>> load(VdaVersion version, {AssetBundle? bundle}) async {
    var assets = bundle ?? rootBundle;
    return {
      for (var topic in topicsOf(version))
        topic: correct(version, topic, parse(await assets.loadString(assetOf(version, topic), cache: false))),
    };
  }

  // Fixes mistakes of the published schemas that would report correct messages as wrong. 3.0.0 factsheet: "required"
  // names mobileRobotKinematic although the property is mobileRobotKinematics, and pauseAllowed and cancelAllowed are
  // typed string although they are true or false.
  static Map<String, Object?> correct(VdaVersion version, String topic, Map<String, Object?> schema) {
    if (version.isV3 && topic == VdaTopic.factsheet) {
      _walk(schema, (node) {
        var required = node['required'];
        if (required is List) {
          node['required'] = [for (var name in required) name == 'mobileRobotKinematic' ? 'mobileRobotKinematics' : name];
        }
        var properties = node['properties'];
        if (properties is Map) {
          for (var name in ['pauseAllowed', 'cancelAllowed']) {
            var property = properties[name];
            if (property is Map && property['type'] == 'string') {
              property['type'] = 'boolean';
            }
          }
        }
      });
    }
    return schema;
  }

  static void _walk(Object? value, void Function(Map node) visit) {
    if (value is Map) {
      visit(value);
      for (var child in value.values) {
        _walk(child, visit);
      }
    } else if (value is List) {
      for (var child in value) {
        _walk(child, visit);
      }
    }
  }

  static Map<String, Object?> parse(String text) => _plain(loadYaml(text)) as Map<String, Object?>;

  // The schema in the subset the documentation keeps: references into #/definitions inlined, the properties of
  // allOf/if/then branches merged in as optional properties, the custom "unit" keyword as x-unit, other keywords left
  // out.
  static Map<String, Object?> flatten(Map<String, Object?> schema) => _flatten(schema, schema, 0);

  static Map<String, Object?> _flatten(Map<String, Object?> node, Map<String, Object?> root, int depth) {
    if (depth > 40) {
      return {};
    }
    var resolved = _resolve(node, root);
    var result = <String, Object?>{};
    for (var entry in resolved.entries) {
      var key = entry.key;
      var value = entry.value;
      if (key == 'unit' && value is String) {
        result['x-unit'] = value;
      } else if (key == 'properties' && value is Map) {
        result['properties'] = {
          for (var property in value.entries)
            if (property.value is Map) '${property.key}': _flatten(_map(property.value), root, depth + 1)
        };
      } else if (key == 'items' && value is Map) {
        result['items'] = _flatten(_map(value), root, depth + 1);
      } else if (_kept.contains(key)) {
        result[key] = value;
      }
    }
    // the type-specific parameters of a 3.0 zone: optional properties of the zone itself
    var branches = resolved['allOf'];
    if (branches is List) {
      var properties = Map<String, Object?>.of(_map(result['properties']));
      for (var branch in branches.whereType<Map>()) {
        var then = _map(_map(branch)['then']);
        for (var property in _map(then['properties']).entries) {
          if (property.value is Map) {
            properties.putIfAbsent(property.key, () => _flatten(_map(property.value), root, depth + 1));
          }
        }
      }
      result['properties'] = properties;
    }
    return result;
  }

  // follows "$ref": "#/definitions/name" inside the same file; the keywords next to it are kept and win
  static Map<String, Object?> _resolve(Map<String, Object?> node, Map<String, Object?> root) {
    var current = node;
    for (var i = 0; i < 10; i++) {
      var reference = current[r'$ref'];
      if (reference is! String || !reference.startsWith('#/')) {
        return current;
      }
      Object? target = root;
      for (var part in reference.substring(2).split('/')) {
        target = target is Map ? target[part] : null;
      }
      var rest = Map<String, Object?>.of(current)..remove(r'$ref');
      current = {..._map(target), ...rest};
    }
    return current;
  }

  static Object? _plain(Object? value) => switch (value) {
        Map map => {for (var entry in map.entries) '${entry.key}': _plain(entry.value)},
        List list => [for (var item in list) _plain(item)],
        _ => value,
      };

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? value.map((key, value) => MapEntry('$key', value)) : <String, Object?>{};
}
