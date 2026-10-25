import 'dart:convert';

// Writes maps, lists and scalars as block-style YAML. Strings are double quoted with JSON escapes (valid YAML) unless
// they span lines, which become literal blocks.
class YamlWriter {
  static final RegExp _plainKey = RegExp(r'^[A-Za-z_$][A-Za-z0-9_.$-]*$');

  static String write(Object? value) {
    var out = StringBuffer();
    _value(out, value, 0, inList: false);
    return '${out.toString().trimRight()}\n';
  }

  static void _value(StringBuffer out, Object? value, int indent, {required bool inList}) {
    switch (value) {
      case Map<String, Object?> map when map.isNotEmpty:
        var first = true;
        for (var entry in map.entries) {
          // the first entry of a map in a list goes right after "- "
          var pad = first && inList ? '' : ' ' * indent;
          first = false;
          out.write('$pad${_key(entry.key)}:');
          _child(out, entry.value, indent);
        }
      case List<Object?> list when list.isNotEmpty:
        var first = true;
        for (var item in list) {
          var pad = first && inList ? '' : ' ' * indent;
          first = false;
          out.write('$pad- ');
          if (item is Map<String, Object?> && item.isNotEmpty || item is List<Object?> && item.isNotEmpty) {
            _value(out, item, indent + 2, inList: true);
          } else {
            out.writeln(_scalar(item, indent + 2));
          }
        }
      default:
        out.writeln(_scalar(value, indent));
    }
  }

  static void _child(StringBuffer out, Object? value, int indent) {
    if (value is Map<String, Object?> && value.isNotEmpty) {
      out.writeln();
      _value(out, value, indent + 2, inList: false);
    } else if (value is List<Object?> && value.isNotEmpty) {
      out.writeln();
      _value(out, value, indent + 2, inList: false);
    } else {
      out.writeln(' ${_scalar(value, indent + 2)}');
    }
  }

  static String _key(String key) => _plainKey.hasMatch(key) ? key : jsonEncode(key);

  static String _scalar(Object? value, int indent) {
    if (value is Map) {
      return '{}';
    }
    if (value is List) {
      return '[]';
    }
    if (value is String) {
      return _string(value, indent);
    }
    return jsonEncode(value);
  }

  static String _string(String value, int indent) {
    var lines = value.split('\n');
    var block = lines.length > 1 &&
        !value.contains('\r') &&
        lines.first.isNotEmpty &&
        !lines.first.startsWith(' ') &&
        !lines.any((line) => line.trimRight() != line);
    if (!block) {
      return jsonEncode(value);
    }
    var pad = ' ' * indent;
    var chomp = value.endsWith('\n') ? '' : '-';
    var body = (value.endsWith('\n') ? lines.sublist(0, lines.length - 1) : lines)
        .map((line) => line.isEmpty ? '' : '$pad$line')
        .join('\n');
    return '|$chomp\n$body';
  }
}
