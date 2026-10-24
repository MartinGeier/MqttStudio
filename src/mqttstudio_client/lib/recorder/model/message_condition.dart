import 'dart:convert';
import 'dart:typed_data';
import 'package:json_annotation/json_annotation.dart';
import 'package:mqttstudio/common/utils/json_path.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';

// use 'dart run build_runner build' to run the code generator
part 'message_condition.g.dart';

enum ConditionOp { equals, notEquals, greater, greaterOrEqual, less, lessOrEqual, contains, regex }

// Which messages start, stop or save a recording (doc/recorder-design.md §10). The text form is
// "<topic filter> [<json path>] [<op> <value>]", e.g. plant/+/temp > 80 or plant/line1/state $.status == "error".
@JsonSerializable()
class MessageCondition {
  static const Map<String, ConditionOp> _ops = {
    '==': ConditionOp.equals,
    '!=': ConditionOp.notEquals,
    '>=': ConditionOp.greaterOrEqual,
    '<=': ConditionOp.lessOrEqual,
    '>': ConditionOp.greater,
    '<': ConditionOp.less,
    'contains': ConditionOp.contains,
    '~': ConditionOp.regex,
  };

  String topicFilter;
  // null = the whole payload
  String? jsonPath;
  // null = any message on the filter matches
  ConditionOp? op;
  String? value;

  MessageCondition(this.topicFilter, {this.jsonPath, this.op, this.value});

  @JsonKey(includeFromJson: false, includeToJson: false)
  late final JsonPath? _path = jsonPath == null ? null : JsonPath.parse(jsonPath!);

  @JsonKey(includeFromJson: false, includeToJson: false)
  late final RegExp? _regex = op == ConditionOp.regex ? RegExp(value ?? '') : null;

  // throws a FormatException with a message for the user
  static MessageCondition parse(String text) {
    var rest = text.trim();
    if (rest.isEmpty) {
      throw FormatException('A condition starts with a topic filter');
    }
    var space = rest.indexOf(RegExp(r'\s'));
    var filter = space < 0 ? rest : rest.substring(0, space);
    rest = space < 0 ? '' : rest.substring(space).trim();
    var issue = RecorderRules.validateFilter(filter);
    if (issue != null) {
      throw FormatException('"$filter" is no valid topic filter');
    }
    String? path;
    if (rest.startsWith(r'$')) {
      var end = _pathEnd(rest);
      path = rest.substring(0, end);
      rest = rest.substring(end).trim();
      JsonPath.parse(path);
    }
    if (rest.isEmpty) {
      return MessageCondition(filter, jsonPath: path);
    }
    for (var entry in _ops.entries) {
      if (rest.startsWith(entry.key)) {
        var value = _unquote(rest.substring(entry.key.length).trim(), entry.value);
        if (value.isEmpty && entry.value != ConditionOp.equals && entry.value != ConditionOp.notEquals) {
          throw FormatException('"${entry.key}" needs a value');
        }
        var condition = MessageCondition(filter, jsonPath: path, op: entry.value, value: value);
        if (entry.value == ConditionOp.regex) {
          try {
            RegExp(value);
          } on FormatException {
            throw FormatException('"$value" is no valid regular expression');
          }
        }
        return condition;
      }
    }
    throw FormatException('Unknown comparison "$rest", use == != > >= < <= contains or ~');
  }

  static MessageCondition? tryParse(String text) {
    try {
      return parse(text);
    } on FormatException {
      return null;
    }
  }

  // the end of a JSON path: the first blank outside ['…']
  static int _pathEnd(String text) {
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      var char = text[i];
      if (char == "'" && (i == 0 || text[i - 1] != r'\')) {
        inQuotes = !inQuotes;
      } else if (!inQuotes && (char == ' ' || char == '\t')) {
        return i;
      }
    }
    return text.length;
  }

  // "text" is a string; a regular expression may be written as /…/
  static String _unquote(String value, ConditionOp op) {
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      return value.substring(1, value.length - 1).replaceAll(r'\"', '"');
    }
    if (op == ConditionOp.regex && value.length >= 2 && value.startsWith('/') && value.endsWith('/')) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  String toText() {
    var text = StringBuffer(topicFilter);
    if (jsonPath != null) {
      text.write(' $jsonPath');
    }
    if (op != null) {
      var symbol = _ops.entries.firstWhere((entry) => entry.value == op).key;
      var shown = op == ConditionOp.regex
          ? '/$value/'
          : num.tryParse(value ?? '') != null
              ? value
              : '"${(value ?? '').replaceAll('"', r'\"')}"';
      text.write(' $symbol $shown');
    }
    return text.toString();
  }

  bool matches(String topic, Uint8List payload) {
    if (!RecorderRules.matches(topic, topicFilter)) {
      return false;
    }
    if (_path == null && op == null) {
      return true;
    }
    var text = utf8.decode(payload, allowMalformed: true);
    Object? subject = text;
    if (_path != null) {
      try {
        subject = _path.evaluate(jsonDecode(text));
      } on FormatException {
        return false;
      }
      if (subject == null) {
        return false;
      }
    }
    if (op == null) {
      return true;
    }
    return _compare(subject is String ? subject : jsonEncode(subject));
  }

  // numbers compare as numbers when both sides are numbers, everything else as text
  bool _compare(String subject) {
    var expected = value ?? '';
    var left = num.tryParse(subject.trim());
    var right = num.tryParse(expected.trim());
    var numeric = left != null && right != null;
    int order() => numeric ? left.compareTo(right) : subject.compareTo(expected);
    switch (op!) {
      case ConditionOp.equals:
        return numeric ? left == right : subject == expected;
      case ConditionOp.notEquals:
        return numeric ? left != right : subject != expected;
      case ConditionOp.greater:
        return order() > 0;
      case ConditionOp.greaterOrEqual:
        return order() >= 0;
      case ConditionOp.less:
        return order() < 0;
      case ConditionOp.lessOrEqual:
        return order() <= 0;
      case ConditionOp.contains:
        return subject.contains(expected);
      case ConditionOp.regex:
        return _regex!.hasMatch(subject);
    }
  }

  factory MessageCondition.fromJson(Map<String, dynamic> json) => _$MessageConditionFromJson(json);
  Map<String, dynamic> toJson() => _$MessageConditionToJson(this);
}
