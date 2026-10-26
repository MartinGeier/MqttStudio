import 'dart:convert';
import 'package:mqttstudio/common/utils/json_path.dart';

enum JsonChangeKind { added, removed, changed }

class JsonChange {
  final JsonPath path;
  final JsonChangeKind kind;
  final Object? oldValue;
  final Object? newValue;

  const JsonChange(this.path, this.kind, {this.oldValue, this.newValue});
}

enum JsonDiffSide { old, current }

// One line of a pretty printed JSON document with what changed in it
class JsonDiffLine {
  final int indent;
  final String text;
  final JsonChangeKind? kind;
  // for a changed value: the other side's value
  final String? otherValue;

  const JsonDiffLine(this.indent, this.text, {this.kind, this.otherValue});
}

// Compares decoded JSON documents member by member and array elements by index. Numbers compare by value, so 1 and
// 1.0 are equal. A value that changes its type, e.g. from an object to a number, is one change.
class JsonDiff {
  static List<JsonChange> compare(Object? oldJson, Object? newJson) {
    var changes = <JsonChange>[];
    _compare(oldJson, newJson, [], changes);
    return changes;
  }

  static void _compare(Object? oldValue, Object? newValue, List<Object> path, List<JsonChange> changes) {
    if (oldValue is Map && newValue is Map) {
      for (var entry in newValue.entries) {
        var childPath = [...path, '${entry.key}'];
        if (!oldValue.containsKey(entry.key)) {
          changes.add(JsonChange(JsonPath(childPath), JsonChangeKind.added, newValue: entry.value));
        } else {
          _compare(oldValue[entry.key], entry.value, childPath, changes);
        }
      }
      for (var entry in oldValue.entries) {
        if (!newValue.containsKey(entry.key)) {
          changes.add(JsonChange(JsonPath([...path, '${entry.key}']), JsonChangeKind.removed, oldValue: entry.value));
        }
      }
      return;
    }
    if (oldValue is List && newValue is List) {
      for (var i = 0; i < newValue.length; i++) {
        if (i >= oldValue.length) {
          changes.add(JsonChange(JsonPath([...path, i]), JsonChangeKind.added, newValue: newValue[i]));
        } else {
          _compare(oldValue[i], newValue[i], [...path, i], changes);
        }
      }
      for (var i = newValue.length; i < oldValue.length; i++) {
        changes.add(JsonChange(JsonPath([...path, i]), JsonChangeKind.removed, oldValue: oldValue[i]));
      }
      return;
    }
    if (!equal(oldValue, newValue)) {
      changes.add(JsonChange(JsonPath(path), JsonChangeKind.changed, oldValue: oldValue, newValue: newValue));
    }
  }

  static bool equal(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length && a.entries.every((entry) => b.containsKey(entry.key) && equal(entry.value, b[entry.key]));
    }
    if (a is List && b is List) {
      if (a.length != b.length) {
        return false;
      }
      for (var i = 0; i < a.length; i++) {
        if (!equal(a[i], b[i])) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }

  // Pretty prints one side with the changes marked. The current side marks added and changed values; the old side
  // marks removed and changed ones. With withRemoved the current side also shows removed members, struck out.
  static List<JsonDiffLine> lines(Object? oldJson, Object? newJson, JsonDiffSide side, {bool withRemoved = false}) {
    var printer = _DiffPrinter(side, withRemoved);
    var shown = side == JsonDiffSide.current ? newJson : oldJson;
    var other = side == JsonDiffSide.current ? oldJson : newJson;
    printer.value(shown, other, true, '', 0, false);
    return printer.result;
  }

  static String compact(Object? value) {
    try {
      return jsonEncode(value, toEncodable: (x) => '$x');
    } on JsonUnsupportedObjectError {
      // NaN and infinity, e.g. from CBOR
      return '$value';
    }
  }
}

class _DiffPrinter {
  final JsonDiffSide side;
  final bool withRemoved;
  final List<JsonDiffLine> result = [];

  _DiffPrinter(this.side, this.withRemoved);

  // a value missing on the other side is added (current side) or removed (old side)
  JsonChangeKind get _missingKind => side == JsonDiffSide.current ? JsonChangeKind.added : JsonChangeKind.removed;

  void value(Object? shown, Object? other, bool hasOther, String prefix, int indent, bool comma) {
    if (!hasOther) {
      _plain(shown, prefix, indent, comma, _missingKind);
    } else if (shown is Map && other is Map) {
      _map(shown, other, prefix, indent, comma);
    } else if (shown is List && other is List) {
      _list(shown, other, prefix, indent, comma);
    } else if (JsonDiff.equal(shown, other)) {
      _plain(shown, prefix, indent, comma, null);
    } else if (shown is Map || shown is List) {
      _plain(shown, prefix, indent, comma, JsonChangeKind.changed);
    } else {
      result.add(JsonDiffLine(indent, '$prefix${JsonDiff.compact(shown)}${comma ? ',' : ''}',
          kind: JsonChangeKind.changed, otherValue: JsonDiff.compact(other)));
    }
  }

  void _map(Map shown, Map other, String prefix, int indent, bool comma) {
    var removed = withRemoved ? other.keys.where((key) => !shown.containsKey(key)).toList() : [];
    if (shown.isEmpty && removed.isEmpty) {
      result.add(JsonDiffLine(indent, '$prefix{}${comma ? ',' : ''}'));
      return;
    }
    result.add(JsonDiffLine(indent, '$prefix{'));
    var keys = shown.keys.toList();
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i];
      value(shown[key], other[key], other.containsKey(key), '${jsonEncode('$key')}: ', indent + 1,
          i < keys.length - 1 || removed.isNotEmpty);
    }
    for (var i = 0; i < removed.length; i++) {
      _plain(other[removed[i]], '${jsonEncode('${removed[i]}')}: ', indent + 1, i < removed.length - 1, JsonChangeKind.removed);
    }
    result.add(JsonDiffLine(indent, '}${comma ? ',' : ''}'));
  }

  void _list(List shown, List other, String prefix, int indent, bool comma) {
    var removed = withRemoved && other.length > shown.length ? other.sublist(shown.length) : [];
    if (shown.isEmpty && removed.isEmpty) {
      result.add(JsonDiffLine(indent, '$prefix[]${comma ? ',' : ''}'));
      return;
    }
    result.add(JsonDiffLine(indent, '$prefix['));
    for (var i = 0; i < shown.length; i++) {
      value(shown[i], i < other.length ? other[i] : null, i < other.length, '', indent + 1,
          i < shown.length - 1 || removed.isNotEmpty);
    }
    for (var i = 0; i < removed.length; i++) {
      _plain(removed[i], '', indent + 1, i < removed.length - 1, JsonChangeKind.removed);
    }
    result.add(JsonDiffLine(indent, ']${comma ? ',' : ''}'));
  }

  // a value and everything in it with the same mark
  void _plain(Object? shown, String prefix, int indent, bool comma, JsonChangeKind? kind) {
    if (shown is Map && shown.isNotEmpty) {
      result.add(JsonDiffLine(indent, '$prefix{', kind: kind));
      var keys = shown.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        _plain(shown[keys[i]], '${jsonEncode('${keys[i]}')}: ', indent + 1, i < keys.length - 1, kind);
      }
      result.add(JsonDiffLine(indent, '}${comma ? ',' : ''}', kind: kind));
    } else if (shown is List && shown.isNotEmpty) {
      result.add(JsonDiffLine(indent, '$prefix[', kind: kind));
      for (var i = 0; i < shown.length; i++) {
        _plain(shown[i], '', indent + 1, i < shown.length - 1, kind);
      }
      result.add(JsonDiffLine(indent, ']${comma ? ',' : ''}', kind: kind));
    } else {
      result.add(JsonDiffLine(indent, '$prefix${JsonDiff.compact(shown)}${comma ? ',' : ''}', kind: kind));
    }
  }
}
