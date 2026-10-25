import 'package:mqttstudio/documentation/engine/conformance_checker.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';

// One row per documented topic, for a spreadsheet overview (doc/documentation-design.md §9.1)
class CsvExporter {
  static const List<String> columns = [
    'path',
    'title',
    'status',
    'format',
    'unit',
    'min',
    'max',
    'qos',
    'retain',
    'interval',
    'nominal_interval_ms',
    'stale_after_ms',
    'owner',
    'tags',
    'description'
  ];

  static String write(List<DocNode> nodes) {
    var out = StringBuffer()..writeln(columns.join(','));
    for (var node in nodes.where((node) => node.isTopic)) {
      var topic = node.topic!;
      var payload = topic.payload;
      out.writeln([
        node.path,
        node.title,
        node.status.name,
        payload.format.name,
        payload.unit ?? '',
        _number(payload.min),
        _number(payload.max),
        topic.qos == null ? '' : '${topic.qos!.index}',
        topic.retain.name,
        topic.interval.kind.name,
        topic.interval.nominalMs?.toString() ?? '',
        topic.interval.staleAfterMs?.toString() ?? '',
        node.owner,
        node.tags.join('; '),
        node.description.trim().split('\n').first,
      ].map(field).join(','));
    }
    return out.toString();
  }

  // the findings of a check, one row per finding
  static String findings(List<Finding> findings) {
    var out = StringBuffer()..writeln('severity,rule,topic,documented,count,first,last,detail,payload');
    for (var finding in findings) {
      out.writeln([
        finding.severity.name,
        finding.rule.name,
        finding.topic,
        finding.node?.path ?? '',
        '${finding.count}',
        finding.first.toUtc().toIso8601String(),
        finding.last.toUtc().toIso8601String(),
        finding.detail,
        finding.examplePayload ?? '',
      ].map(field).join(','));
    }
    return out.toString();
  }

  static String _number(double? value) {
    if (value == null) {
      return '';
    }
    return value == value.roundToDouble() && value.abs() < 1e15 ? value.toInt().toString() : value.toString();
  }

  // quotes a field when it holds a comma, a quote, a line break or blanks at its ends (RFC 4180)
  static String field(String value) {
    if (value.contains(RegExp(r'[",\r\n]')) || value.trim() != value) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
