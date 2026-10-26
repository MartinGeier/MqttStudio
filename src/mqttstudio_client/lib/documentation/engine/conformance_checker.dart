import 'dart:convert';
import 'package:mqttstudio/documentation/engine/discovery_merger.dart';
import 'package:mqttstudio/documentation/engine/doc_index.dart';
import 'package:mqttstudio/documentation/engine/documentation_analyzer.dart';
import 'package:mqttstudio/documentation/engine/schema_validator.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/protocol/protocol_profile.dart';
import 'package:mqttstudio/protocol/protocol_registry.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';

enum FindingRule {
  undocumented,
  formatMismatch,
  schemaViolation,
  outOfRange,
  valueNotAllowed,
  parameterMismatch,
  qosDiffers,
  retainDiffers,
  stale,
  deprecatedInUse,
  mqtt5Differs,
  // a rule of a protocol profile, e.g. VDA 5050; the finding names it (doc/vda5050-design.md §9.3)
  protocol,
}

enum FindingSeverity { error, warning }

// One rule broken by one topic, aggregated over all its messages (doc/documentation-design.md §7)
class Finding {
  final FindingRule rule;
  // the concrete topic; for a stale topic its documented path
  final String topic;
  // the documented topic it belongs to, null for an undocumented one
  final DocNode? node;
  // what is wrong, in English like the CLI output; the last message's details
  String detail;
  int count = 0;
  final DateTime first;
  DateTime last;
  String? examplePayload;

  // for FindingRule.protocol: the profile's rule, e.g. vda5050.headerIdGap, and its severity
  final String? protocolRule;
  final FindingSeverity? protocolSeverity;

  Finding(this.rule, this.topic, this.node, this.detail, this.first, {this.protocolRule, this.protocolSeverity})
      : last = first;

  FindingSeverity get severity => protocolSeverity ?? severityOf(rule);

  // the rule's name in exports and the CLI
  String get ruleId => protocolRule ?? rule.name;

  static FindingSeverity severityOf(FindingRule rule) => switch (rule) {
        FindingRule.formatMismatch ||
        FindingRule.schemaViolation ||
        FindingRule.valueNotAllowed ||
        FindingRule.parameterMismatch ||
        FindingRule.stale =>
          FindingSeverity.error,
        _ => FindingSeverity.warning,
      };

  Map<String, Object?> toJson() => {
        'severity': severity.name,
        'rule': ruleId,
        'topic': topic,
        if (node != null) 'documented': node!.path,
        'count': count,
        'first': first.toUtc().toIso8601String(),
        'last': last.toUtc().toIso8601String(),
        'detail': detail,
        if (examplePayload != null) 'payload': examplePayload,
      };
}

// Checks messages against the documentation: every message against the topic it matches, and every documented
// topic with a stale threshold for silence. Findings are kept per rule, topic and detail.
class ConformanceChecker {
  static const int maxFindings = 10000;
  static const int maxPayloadLength = 1024;

  final TopicDocumentation documentation;
  final bool isMqtt5;
  final List<String> ignoreFilters;
  final DocIndex _index;
  final DocIndex _loose;
  final ProtocolRegistry _protocols;
  final Map<ProtocolProfile, ProtocolChecker> _protocolCheckers = {};
  final Map<String, Finding> _findings = {};
  final Map<DocNode, DateTime> _lastSeen = {};
  DateTime? _startedAt;
  int messages = 0;

  ConformanceChecker(this.documentation, {this.isMqtt5 = true, this.ignoreFilters = const [], ProtocolRegistry? protocols})
      : _index = DocIndex(documentation.nodes),
        _loose = DocIndex(documentation.nodes, patterns: false),
        _protocols = protocols ?? ProtocolRegistry.standard();

  List<Finding> get findings => _findings.values.toList()
    ..sort((a, b) {
      var bySeverity = a.severity.index.compareTo(b.severity.index);
      return bySeverity != 0 ? bySeverity : a.topic.compareTo(b.topic);
    });

  int countOf(FindingSeverity severity) => _findings.values.where((finding) => finding.severity == severity).length;

  // the worst severity per documented path, for the tree
  Map<String, FindingSeverity> get severityByPath {
    var result = <String, FindingSeverity>{};
    for (var finding in _findings.values) {
      var path = finding.node?.path;
      if (path != null && (result[path] == null || finding.severity.index < result[path]!.index)) {
        result[path] = finding.severity;
      }
    }
    return result;
  }

  void start(DateTime at) => _startedAt ??= at;

  // forgets the findings so far; stale topics count again from now. The protocol rules keep what they know, e.g. the
  // last header ids.
  void clearFindings(DateTime now) {
    _findings.clear();
    _lastSeen.clear();
    if (_startedAt != null) {
      _startedAt = now;
    }
  }

  void check(RecordedMessage message, DateTime at) {
    start(at);
    messages++;
    var match = _index.match(message.topic);
    _checkProtocol(message, at, match?.node ?? _loose.match(message.topic)?.node);
    if (match == null) {
      _unmatched(message, at);
      return;
    }
    var node = match.node;
    _lastSeen[node] = at;
    if (node.status == DocStatus.deprecated) {
      var replacement = node.replacedBy == null ? '' : ', replaced by ${node.replacedBy}';
      _add(FindingRule.deprecatedInUse, message, at, node, 'Deprecated$replacement');
    }
    var topic = node.topic!;
    // an empty retained message clears the retained value, it is no payload of the topic
    var clearing = message.payload.isEmpty && message.retain;
    if (!clearing) {
      _checkPayload(topic.payload, message, at, node);
    }
    if (topic.qos != null && message.qos.index != topic.qos!.index) {
      _add(FindingRule.qosDiffers, message, at, node,
          'Delivered with QoS ${message.qos.index}, documented ${topic.qos!.index}');
    }
    _checkRetain(topic.retain, message, at, node);
    _checkMqtt5(topic.mqtt5, message, at, node);
  }

  // documented topics with a stale threshold that sent nothing for that long; once the check has run that long. The
  // protocol rules that fire on time run here too.
  void checkStale(DateTime now) {
    for (var checker in _protocolCheckers.values) {
      for (var (topic, finding) in checker.tick(now)) {
        _addProtocol(finding, topic, _index.match(topic)?.node, now, null);
      }
    }
    var startedAt = _startedAt;
    if (startedAt == null) {
      return;
    }
    for (var node in documentation.topics) {
      var staleAfter = node.topic!.interval.staleAfterMs;
      if (staleAfter == null || staleAfter <= 0 || now.difference(startedAt).inMilliseconds < staleAfter) {
        continue;
      }
      var last = _lastSeen[node] ?? startedAt;
      var silent = now.difference(last);
      var key = '${FindingRule.stale.name}|${node.path}';
      if (silent.inMilliseconds >= staleAfter) {
        var detail = _lastSeen[node] == null
            ? 'No message since the check started, stale after ${_duration(staleAfter)}'
            : 'No message for ${_duration(silent.inMilliseconds)}, stale after ${_duration(staleAfter)}';
        var finding = _findings[key] ??= Finding(FindingRule.stale, node.path, node, detail, now);
        finding
          ..detail = detail
          ..last = now
          ..count = 1;
      }
    }
  }

  // the rules of the protocol the topic belongs to, documented or not (doc/vda5050-design.md §9.3)
  void _checkProtocol(RecordedMessage message, DateTime at, DocNode? node) {
    if (message.payload.isEmpty) {
      return;
    }
    var match = _protocols.match(message.topic);
    if (match == null) {
      return;
    }
    var json = ClassifiedPayload.of(message.payload).json;
    if (json == null) {
      return;
    }
    var checker = _protocolCheckers.putIfAbsent(match.profile, match.profile.createChecker);
    for (var finding in checker.check(message.topic, match, json, at, snapshot: message.snapshot)) {
      _addProtocol(finding, message.topic, node, at, message);
    }
  }

  void _addProtocol(ProtocolFinding finding, String topic, DocNode? node, DateTime at, RecordedMessage? message) {
    var id = '${finding.rule}|$topic|${finding.key}';
    var existing = _findings[id];
    if (existing == null) {
      if (_findings.length >= maxFindings) {
        return;
      }
      existing = _findings[id] = Finding(FindingRule.protocol, topic, node, finding.detail, at,
          protocolRule: finding.rule,
          protocolSeverity:
              finding.severity == ProtocolSeverity.error ? FindingSeverity.error : FindingSeverity.warning);
    }
    existing
      ..count += 1
      ..last = at
      ..detail = finding.detail;
    if (message != null) {
      existing.examplePayload = _payloadText(message);
    }
  }

  void _unmatched(RecordedMessage message, DateTime at) {
    if (ignoreFilters.any((filter) => RecorderRules.matches(message.topic, filter))) {
      return;
    }
    var loose = _loose.match(message.topic);
    if (loose == null) {
      _add(FindingRule.undocumented, message, at, null, 'No documented topic matches');
      return;
    }
    _lastSeen[loose.node] = at;
    var broken = [
      for (var parameter in loose.node.parameters)
        if (_breaks(parameter, loose.parameters[parameter.name]))
          '${parameter.name} = ${loose.parameters[parameter.name]}'
    ];
    _add(FindingRule.parameterMismatch, message, at, loose.node,
        '${broken.join(', ')} breaks the pattern of ${loose.node.path}',
        key: broken.map((text) => text.split(' = ').first).join(','));
  }

  static bool _breaks(DocParameter parameter, String? value) {
    var pattern = parameter.pattern;
    if (pattern == null || pattern.isEmpty || value == null) {
      return false;
    }
    try {
      var match = RegExp(pattern).matchAsPrefix(value);
      return match == null || match.end != value.length;
    } on FormatException {
      return false;
    }
  }

  void _checkPayload(PayloadSpec payload, RecordedMessage message, DateTime at, DocNode node) {
    var classified = ClassifiedPayload.of(message.payload);
    var format = classified.format;
    var documented = payload.format;
    // 0 and 1 are fine for a boolean, a number is fine as text
    var compatible = documented == PayloadFormat.unknown ||
        documented == format ||
        (documented == PayloadFormat.boolean && (classified.number == 0 || classified.number == 1)) ||
        (documented == PayloadFormat.string && classified.text != null);
    if (!compatible) {
      _add(FindingRule.formatMismatch, message, at, node, 'Payload is ${format.name}, documented ${documented.name}');
      return;
    }
    var text = classified.text?.trim();
    if (payload.allowedValues.isNotEmpty &&
        text != null &&
        documented != PayloadFormat.json &&
        !_allowed(payload, classified)) {
      _add(FindingRule.valueNotAllowed, message, at, node, '$text is not one of ${payload.allowedValues.join(', ')}');
    }
    var number = classified.number;
    if (number != null && documented == PayloadFormat.number) {
      if (payload.min != null && number < payload.min!) {
        _add(FindingRule.outOfRange, message, at, node, '$text is below the minimum ${_number(payload.min!)}',
            key: 'min');
      }
      if (payload.max != null && number > payload.max!) {
        _add(FindingRule.outOfRange, message, at, node, '$text is above the maximum ${_number(payload.max!)}',
            key: 'max');
      }
    }
    var schema = payload.schema;
    if (documented == PayloadFormat.json && schema != null && format == PayloadFormat.json) {
      for (var issue in SchemaValidator.validate(schema, classified.json)) {
        var rule = switch (issue.kind) {
          SchemaIssueKind.range => FindingRule.outOfRange,
          SchemaIssueKind.notAllowed => FindingRule.valueNotAllowed,
          _ => FindingRule.schemaViolation,
        };
        _add(rule, message, at, node, '${issue.path} ${issue.message}', key: '${issue.path}|${issue.kind.name}');
      }
    }
  }

  static bool _allowed(PayloadSpec payload, ClassifiedPayload classified) {
    var text = classified.text!.trim();
    var number = classified.number;
    return payload.allowedValues.any((value) => value == text || (number != null && double.tryParse(value) == number));
  }

  void _checkRetain(RetainMode documented, RecordedMessage message, DateTime at, DocNode node) {
    if (documented != RetainMode.always && documented != RetainMode.never) {
      return;
    }
    // MQTT 5 keeps the publisher's flag (Retain As Published); on 3.1.1 only the retained snapshot shows it
    var known = isMqtt5 || message.snapshot;
    if (!known) {
      return;
    }
    var retained = message.retain;
    if (documented == RetainMode.always && !retained) {
      _add(FindingRule.retainDiffers, message, at, node, 'Published without retain, documented always retained');
    } else if (documented == RetainMode.never && retained) {
      _add(FindingRule.retainDiffers, message, at, node, 'Published retained, documented never retained');
    }
  }

  void _checkMqtt5(Mqtt5Spec documented, RecordedMessage message, DateTime at, DocNode node) {
    var properties = message.properties;
    if (!isMqtt5 || properties == null) {
      return;
    }
    var contentType = documented.contentType;
    if (contentType != null && (properties.contentType ?? '') != contentType) {
      _add(FindingRule.mqtt5Differs, message, at, node,
          'Content type ${properties.contentType?.isEmpty ?? true ? 'missing' : properties.contentType}, documented $contentType',
          key: 'contentType');
    }
    if (documented.utf8Payload == true && !properties.payloadFormatUtf8) {
      _add(FindingRule.mqtt5Differs, message, at, node, 'Payload format indicator is not UTF-8', key: 'utf8');
    }
  }

  void _add(FindingRule rule, RecordedMessage message, DateTime at, DocNode? node, String detail, {String key = ''}) {
    var id = '${rule.name}|${message.topic}|$key';
    var finding = _findings[id];
    if (finding == null) {
      if (_findings.length >= maxFindings) {
        return;
      }
      finding = _findings[id] = Finding(rule, message.topic, node, detail, at);
    }
    finding
      ..count += 1
      ..last = at
      ..detail = detail
      ..examplePayload = _payloadText(message);
  }

  static String? _payloadText(RecordedMessage message) {
    try {
      var text = utf8.decode(message.payload);
      return text.length > maxPayloadLength ? text.substring(0, maxPayloadLength) : text;
    } on FormatException {
      return null;
    }
  }

  // the filters a check listens to: the documented topics with their parameters as +, and those of the last applied
  // discovery for undocumented topics. Documented topics are always checked, also those a discovery's filters miss,
  // e.g. after importing a preset.
  static List<String> filtersOf(TopicDocumentation documentation) {
    var filters = {
      if (documentation.lastDiscoveryAt != null)
        for (var filter in documentation.discoverySettings.filters)
          if (!filter.exclude) filter.filter,
      for (var node in documentation.topics) DiscoveryMerger.ignoreFilterOf(node.path),
    }.toList()
      ..sort();
    return filters
        .where((filter) => !filters.any((other) => other != filter && RecorderRules.covers(other, filter)))
        .toList();
  }

  static String _number(double value) =>
      value == value.roundToDouble() && value.abs() < 1e15 ? value.toInt().toString() : value.toString();

  static String _duration(int ms) {
    if (ms < 1000) {
      return '$ms ms';
    }
    if (ms < 60000) {
      return '${(ms / 1000).round()} s';
    }
    if (ms < 3600000) {
      return '${(ms / 60000).toStringAsFixed(ms % 60000 == 0 ? 0 : 1)} min';
    }
    return '${(ms / 3600000).toStringAsFixed(1)} h';
  }
}
