import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:mqttstudio/common/utils/json_path.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';

// use 'dart run build_runner build' to run the code generator
part 'anonymize_rule.g.dart';

enum AnonymizeTarget { jsonPath, wholePayload, topicLevel }

enum AnonymizeAction { hash, mask, fixed, remove, jitterNumber }

// What to hide in the messages of matching topics before a recording is shared (doc/recorder-design.md §8.1)
@JsonSerializable()
class AnonymizeRule {
  String topicFilter;
  AnonymizeTarget target;
  // for AnonymizeTarget.jsonPath
  String? jsonPath;
  // for AnonymizeTarget.topicLevel, 0 is the first level
  int? level;
  AnonymizeAction action;
  // for AnonymizeAction.fixed
  String? value;
  // for AnonymizeAction.jitterNumber: ± this many percent
  double? percent;

  AnonymizeRule(this.topicFilter, this.target, this.action, {this.jsonPath, this.level, this.value, this.percent});

  // the rules as saved to a .json file, which the CLI reads too
  static String encodeList(List<AnonymizeRule> rules) =>
      JsonEncoder.withIndent('  ').convert([for (var rule in rules) rule.toJson()]);

  // throws a FormatException when the file holds no rules
  static List<AnonymizeRule> decodeList(String text) {
    var json = jsonDecode(text);
    if (json is! List) {
      throw FormatException('An anonymize rules file holds a JSON list of rules');
    }
    try {
      return [for (var entry in json) AnonymizeRule.fromJson(entry as Map<String, dynamic>)];
    } catch (exc) {
      throw FormatException('Invalid anonymize rule: $exc');
    }
  }

  // a description of what is wrong, null when the rule can be applied
  String? get problem {
    if (RecorderRules.validateFilter(topicFilter) != null) {
      return 'topicFilter';
    }
    if (target == AnonymizeTarget.jsonPath && JsonPath.tryParse(jsonPath ?? '') == null) {
      return 'jsonPath';
    }
    if (target == AnonymizeTarget.topicLevel && (level == null || level! < 0)) {
      return 'level';
    }
    if (action == AnonymizeAction.jitterNumber && (percent == null || percent! <= 0)) {
      return 'percent';
    }
    return null;
  }

  factory AnonymizeRule.fromJson(Map<String, dynamic> json) => _$AnonymizeRuleFromJson(json);
  Map<String, dynamic> toJson() => _$AnonymizeRuleToJson(this);
}

// Applies anonymize rules in order. Hashes are salted SHA-256, cut to 12 hex characters. The salt is new for every
// Anonymizer, so equal values stay equal within one anonymized recording but can't be matched with the original.
class Anonymizer {
  final List<AnonymizeRule> rules;
  // user property values and correlation data get the wholePayload rules too
  final bool properties;
  final Random _random;
  late final List<int> _salt = List.generate(16, (_) => _random.nextInt(256));

  Anonymizer(this.rules, {this.properties = false, Random? random}) : _random = random ?? Random.secure();

  String hash(String input) => sha256.convert([..._salt, ...utf8.encode(input)]).toString().substring(0, 12);

  RecordedMessage apply(RecordedMessage message) {
    var topic = message.topic;
    Uint8List payload = message.payload;
    var props = message.properties;
    var changed = false;
    for (var rule in rules.where((rule) => RecorderRules.matches(message.topic, rule.topicFilter))) {
      switch (rule.target) {
        case AnonymizeTarget.topicLevel:
          topic = _applyToTopic(topic, rule);
        case AnonymizeTarget.wholePayload:
          payload = _bytes(_text(utf8.decode(payload, allowMalformed: true), rule));
          if (properties && props != null) {
            props = _applyToProperties(props, rule);
          }
        case AnonymizeTarget.jsonPath:
          // a cut payload is no valid JSON
          if (!message.truncated) {
            payload = _applyToJson(payload, rule);
          }
      }
      changed = true;
    }
    if (!changed) {
      return message;
    }
    return RecordedMessage(
      offsetMicros: message.offsetMicros,
      topic: topic,
      payload: payload,
      // the stored payload is the whole payload now, unless it was cut and is still the cut one
      payloadLength: identical(payload, message.payload) ? message.payloadLength : payload.length,
      qos: message.qos,
      retain: message.retain,
      snapshot: message.snapshot,
      truncated: message.truncated && identical(payload, message.payload),
      properties: props,
    );
  }

  String _applyToTopic(String topic, AnonymizeRule rule) {
    var levels = topic.split('/');
    var level = rule.level ?? 0;
    if (level >= levels.length) {
      return topic;
    }
    if (rule.action == AnonymizeAction.remove) {
      levels.removeAt(level);
    } else {
      levels[level] = _text(levels[level], rule).replaceAll('/', '_');
    }
    return levels.join('/');
  }

  Uint8List _applyToJson(Uint8List payload, AnonymizeRule rule) {
    Object? json;
    try {
      json = jsonDecode(utf8.decode(payload));
    } on FormatException {
      return payload;
    }
    var path = JsonPath.parse(rule.jsonPath!);
    if (path.segments.isEmpty) {
      return rule.action == AnonymizeAction.remove ? Uint8List(0) : _bytes(jsonEncode(_value(json, rule)));
    }
    var found = rule.action == AnonymizeAction.remove ? path.removeIn(json) : path.replaceIn(json, (old) => _value(old, rule));
    return found ? _bytes(jsonEncode(json)) : payload;
  }

  MqttMessageProperties _applyToProperties(MqttMessageProperties props, AnonymizeRule rule) => MqttMessageProperties(
        contentType: props.contentType,
        responseTopic: props.responseTopic,
        correlationData: props.correlationData == null ? null : _bytes(_text(base64Encode(props.correlationData!), rule)),
        messageExpiryInterval: props.messageExpiryInterval,
        payloadFormatUtf8: props.payloadFormatUtf8,
        userProperties: [
          for (var entry in props.userProperties) MqttUserPropertyEntry(entry.key, _text(entry.value, rule)),
        ],
      );

  // a JSON value keeps its type where it can: numbers stay numbers for fixed and jitter
  Object? _value(Object? old, AnonymizeRule rule) {
    switch (rule.action) {
      case AnonymizeAction.jitterNumber:
        return old is num ? _jitter(old, rule.percent ?? 0) : old;
      case AnonymizeAction.fixed:
        var fixed = rule.value ?? '';
        return old is num ? (num.tryParse(fixed) ?? fixed) : fixed;
      case AnonymizeAction.hash:
      case AnonymizeAction.mask:
      case AnonymizeAction.remove:
        return _text(old is String ? old : jsonEncode(old), rule);
    }
  }

  String _text(String old, AnonymizeRule rule) {
    switch (rule.action) {
      case AnonymizeAction.hash:
        return hash(old);
      case AnonymizeAction.mask:
        return '*' * old.length;
      case AnonymizeAction.fixed:
        return rule.value ?? '';
      case AnonymizeAction.remove:
        return '';
      case AnonymizeAction.jitterNumber:
        var number = num.tryParse(old.trim());
        return number == null ? old : '${_jitter(number, rule.percent ?? 0)}';
    }
  }

  num _jitter(num value, double percent) {
    var jittered = value * (1 + (_random.nextDouble() * 2 - 1) * percent / 100);
    return value is int ? jittered.round() : jittered;
  }

  static Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));
}
