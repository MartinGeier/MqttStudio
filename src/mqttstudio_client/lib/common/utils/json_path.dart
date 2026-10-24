// The JSON path subset of doc/recorder-design.md §10: $, .name, ['name with spaces'] and [index]. No wildcards,
// filters or recursive descent. Shared by charts, conditions, compare, anonymize and export.
class JsonPath {
  static final RegExp _name = RegExp(r'^[A-Za-z_][A-Za-z0-9_\-]*$');

  // String for a member, int for an array index
  final List<Object> segments;

  const JsonPath(this.segments);

  static const JsonPath root = JsonPath([]);

  // throws a FormatException that names the position of the problem
  static JsonPath parse(String text) {
    var source = text.trim();
    if (!source.startsWith(r'$')) {
      throw FormatException(r'A JSON path starts with $', text, 0);
    }
    var segments = <Object>[];
    var i = 1;
    while (i < source.length) {
      var char = source[i];
      if (char == '.') {
        var end = i + 1;
        while (end < source.length && source[end] != '.' && source[end] != '[') {
          end++;
        }
        var name = source.substring(i + 1, end);
        if (!_name.hasMatch(name)) {
          throw FormatException('Invalid member name "$name"', text, i + 1);
        }
        segments.add(name);
        i = end;
      } else if (char == '[') {
        if (i + 1 < source.length && source[i + 1] == "'") {
          var name = StringBuffer();
          var j = i + 2;
          var closed = false;
          while (j < source.length) {
            if (source[j] == r'\' && j + 1 < source.length) {
              name.write(source[j + 1]);
              j += 2;
            } else if (source[j] == "'") {
              closed = true;
              break;
            } else {
              name.write(source[j]);
              j++;
            }
          }
          if (!closed || j + 1 >= source.length || source[j + 1] != ']') {
            throw FormatException("Missing '] after a quoted member name", text, i);
          }
          segments.add(name.toString());
          i = j + 2;
        } else {
          var end = source.indexOf(']', i);
          var index = end < 0 ? null : int.tryParse(source.substring(i + 1, end));
          if (index == null || index < 0) {
            throw FormatException('Invalid array index', text, i);
          }
          segments.add(index);
          i = end + 1;
        }
      } else {
        throw FormatException('Unexpected "$char"', text, i);
      }
    }
    return JsonPath(segments);
  }

  static JsonPath? tryParse(String text) {
    try {
      return parse(text);
    } on FormatException {
      return null;
    }
  }

  // the value at this path in a decoded JSON document, null when it is not there
  Object? evaluate(Object? json) {
    var current = json;
    for (var segment in segments) {
      if (segment is String && current is Map) {
        if (!current.containsKey(segment)) {
          return null;
        }
        current = current[segment];
      } else if (segment is int && current is List) {
        if (segment >= current.length) {
          return null;
        }
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }

  // Replaces the value at this path in a decoded, modifiable JSON document; false when the path isn't there.
  // The root path can't be replaced in place.
  bool replaceIn(Object? json, Object? Function(Object? old) replace) {
    var parent = _parentOf(json);
    if (parent == null) {
      return false;
    }
    var last = segments.last;
    if (last is String && parent is Map && parent.containsKey(last)) {
      parent[last] = replace(parent[last]);
      return true;
    }
    if (last is int && parent is List && last < parent.length) {
      parent[last] = replace(parent[last]);
      return true;
    }
    return false;
  }

  // removes the member or array element at this path; false when it isn't there
  bool removeIn(Object? json) {
    var parent = _parentOf(json);
    if (parent == null) {
      return false;
    }
    var last = segments.last;
    if (last is String && parent is Map && parent.containsKey(last)) {
      parent.remove(last);
      return true;
    }
    if (last is int && parent is List && last < parent.length) {
      parent.removeAt(last);
      return true;
    }
    return false;
  }

  Object? _parentOf(Object? json) => segments.isEmpty ? null : JsonPath(segments.sublist(0, segments.length - 1)).evaluate(json);

  // the paths of the numbers in a decoded JSON document, in document order
  static List<JsonPath> numericPaths(Object? json, {int max = 50}) {
    var found = <JsonPath>[];
    void visit(Object? value, List<Object> path) {
      if (found.length >= max) {
        return;
      }
      if (value is num) {
        found.add(JsonPath(List.of(path)));
      } else if (value is Map) {
        for (var entry in value.entries) {
          visit(entry.value, [...path, '${entry.key}']);
        }
      } else if (value is List) {
        for (var i = 0; i < value.length; i++) {
          visit(value[i], [...path, i]);
        }
      }
    }

    visit(json, []);
    return found;
  }

  @override
  String toString() {
    var text = StringBuffer(r'$');
    for (var segment in segments) {
      if (segment is int) {
        text.write('[$segment]');
      } else if (_name.hasMatch(segment as String)) {
        text.write('.$segment');
      } else {
        text.write("['${segment.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}']");
      }
    }
    return text.toString();
  }

  @override
  bool operator ==(Object other) => other is JsonPath && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}
