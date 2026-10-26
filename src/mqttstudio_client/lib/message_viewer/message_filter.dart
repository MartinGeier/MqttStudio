import 'dart:convert';
import 'dart:typed_data';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/model/message_condition.dart';

enum MessageFilterMode { topic, payload, condition }

// The filter of the topic viewer's command bar:
// - topic: part of the topic, ignoring case, or an MQTT topic filter when the text has + or # (plant/+/temp)
// - payload: text in the payload, ignoring case
// - condition: the recorder's condition syntax (MessageCondition); without a topic filter in front it applies to
//   all topics, e.g. $.status == "error" or > 80
// Topic and payload texts can also be regular expressions, which ignore case as well.
class MessageFilter {
  static final RegExp _startsWithPath = RegExp(r'^\$($|[.\[\s])');
  static const List<String> _operators = ['==', '!=', '>=', '<=', '>', '<', '~', 'contains '];

  final MessageFilterMode mode;
  final String text;
  final bool regex;

  RegExp? _regex;
  String? _wildcardFilter;
  MessageCondition? _condition;
  // the result per message, so rebuilding the views doesn't decode the payloads again
  final Expando<bool> _results = Expando();

  // throws a FormatException with a message for the user
  MessageFilter(this.text, {this.mode = MessageFilterMode.topic, this.regex = false}) {
    var trimmed = text.trim();
    if (mode == MessageFilterMode.condition) {
      _condition = MessageCondition.parse(_withTopicFilter(trimmed));
      return;
    }
    if (regex) {
      try {
        _regex = RegExp(trimmed, caseSensitive: false);
      } on FormatException {
        throw FormatException('"$trimmed" is no valid regular expression');
      }
      return;
    }
    if (mode == MessageFilterMode.topic && (trimmed.contains('+') || trimmed.contains('#'))) {
      if (RecorderRules.validateFilter(trimmed) != null) {
        throw FormatException('+ and # must fill a whole level, # only the last one');
      }
      _wildcardFilter = trimmed;
    }
  }

  // null for an empty text: nothing is filtered
  static MessageFilter? create(String? text, {MessageFilterMode mode = MessageFilterMode.topic, bool regex = false}) {
    if (text == null || text.trim().isEmpty) {
      return null;
    }
    return MessageFilter(text, mode: mode, regex: regex);
  }

  bool get filtersPayload => mode != MessageFilterMode.topic;

  bool matches(ReceivedMqttMessage message) {
    var known = _results[message];
    if (known != null) {
      return known;
    }
    var result = _matches(message);
    _results[message] = result;
    return result;
  }

  bool _matches(ReceivedMqttMessage message) {
    switch (mode) {
      case MessageFilterMode.topic:
        return matchesTopic(message.topicName);
      case MessageFilterMode.payload:
        return _matchesText(utf8.decode(message.payload, allowMalformed: true));
      case MessageFilterMode.condition:
        return _condition!.matches(message.topicName, Uint8List.fromList(message.payload));
    }
  }

  // only the topic, for topic filters
  bool matchesTopic(String topic) {
    if (_wildcardFilter != null) {
      return RecorderRules.matches(topic, _wildcardFilter!);
    }
    return _matchesText(topic);
  }

  bool _matchesText(String value) {
    if (_regex != null) {
      return _regex!.hasMatch(value);
    }
    return value.toLowerCase().contains(text.trim().toLowerCase());
  }

  // a condition may start with the JSON path or the comparison, then it applies to all topics
  static String _withTopicFilter(String text) {
    if (text.isEmpty || _startsWithPath.hasMatch(text) || _operators.any(text.startsWith)) {
      return '# $text';
    }
    return text;
  }
}
