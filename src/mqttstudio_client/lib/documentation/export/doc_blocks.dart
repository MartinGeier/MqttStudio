import 'dart:convert';
import 'package:mqttstudio/documentation/engine/schema_paths.dart';
import 'package:mqttstudio/documentation/export/doc_export.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';

sealed class DocBlock {}

class HeadingBlock extends DocBlock {
  final int level;
  final String text;
  // shown as code before the text, e.g. the topic
  final String? code;
  final String? anchor;

  HeadingBlock(this.level, this.text, {this.code, this.anchor});
}

// text the user wrote in Markdown: Markdown keeps it, HTML shows it as paragraphs
class MarkdownBlock extends DocBlock {
  final String text;

  MarkdownBlock(this.text);
}

class LabelBlock extends DocBlock {
  final String text;

  LabelBlock(this.text);
}

class FactsBlock extends DocBlock {
  final List<(String, String)> facts;

  FactsBlock(this.facts);
}

class TableBlock extends DocBlock {
  final List<String> headers;
  final List<List<String>> rows;

  TableBlock(this.headers, this.rows);
}

class CodeBlock extends DocBlock {
  final String text;
  final String language;

  CodeBlock(this.text, this.language);
}

class TocBlock extends DocBlock {
  final List<({int depth, String code, String text, String anchor})> entries;

  TocBlock(this.entries);
}

// The documentation as a list of blocks, rendered as Markdown or as a self-contained HTML page
// (doc/documentation-design.md §9.1)
class DocBlocks {
  final String title;
  final List<DocBlock> blocks;

  DocBlocks(this.title, this.blocks);

  static DocBlocks build(TopicDocumentation documentation, List<DocNode> nodes, DocExportOptions options,
      {MqttSettings? broker, required DateTime exportedAt}) {
    var title = documentation.title.isEmpty ? 'MQTT topic documentation' : documentation.title;
    var anchors = {for (var (index, node) in nodes.indexed) node: 't${index + 1}'};
    var server = broker == null || !options.includeBroker ? null : DocExport.brokerOf(broker);
    var blocks = <DocBlock>[
      if (documentation.description.isNotEmpty) MarkdownBlock(documentation.description),
      FactsBlock([
        if (documentation.owner.isNotEmpty) ('Owner', documentation.owner),
        if (server != null) ('Broker', '${server.host} · ${server.protocol} · MQTT ${server.protocolVersion}'),
        ('Topics', '${nodes.where((node) => node.isTopic).length}'),
        ('Revision', '${documentation.revision}'),
        ('Exported', _date(exportedAt)),
      ]),
      if (nodes.isNotEmpty) ...[
        HeadingBlock(2, 'Contents'),
        TocBlock([
          for (var node in nodes)
            (depth: _depth(node, nodes), code: node.path, text: node.title, anchor: anchors[node]!)
        ]),
      ],
      for (var node in nodes) ..._node(node, anchors[node]!, options),
    ];
    return DocBlocks(title, blocks);
  }

  static int _depth(DocNode node, List<DocNode> nodes) =>
      nodes.where((other) => other != node && node.path.startsWith('${other.path}/')).length;

  static List<DocBlock> _node(DocNode node, String anchor, DocExportOptions options) {
    var blocks = <DocBlock>[
      HeadingBlock(2, node.title, code: node.path, anchor: anchor),
      FactsBlock([
        ('Status', _label(node.status.name)),
        if (!node.isTopic) ('Kind', 'Namespace'),
        if (node.replacedBy != null) ('Replaced by', node.replacedBy!),
        if (node.owner.isNotEmpty) ('Owner', node.owner),
        if (node.tags.isNotEmpty) ('Tags', node.tags.join(', ')),
      ]),
      if (node.description.isNotEmpty) MarkdownBlock(node.description),
      if (node.links.isNotEmpty)
        FactsBlock([for (var link in node.links) (link.label.isEmpty ? 'Link' : link.label, link.url)]),
      if (node.parameters.isNotEmpty) ...[
        LabelBlock('Parameters'),
        TableBlock([
          'Name',
          'Pattern',
          'Description',
          'Examples'
        ], [
          for (var parameter in node.parameters)
            [parameter.name, parameter.pattern ?? '', parameter.description, parameter.examples.join(', ')]
        ]),
      ],
    ];
    var topic = node.topic;
    if (topic != null) {
      blocks.addAll(_payload(topic.payload, options));
      blocks.addAll(_delivery(topic));
      blocks.addAll(_mqtt5(topic.mqtt5));
      blocks.addAll(_access(topic));
    }
    var observed = node.observed;
    if (options.includeObserved && observed != null) {
      var interval = observed.interval;
      blocks.addAll([
        LabelBlock('Observed'),
        FactsBlock([
          ('Source', '${observed.source.name}${observed.sourceName == null ? '' : ' ${observed.sourceName}'}'),
          ('From', _date(observed.from)),
          ('Messages', '${observed.messages}'),
          ('Instances', '${observed.instanceCount}'),
          ('Rate', '${interval.rate.toStringAsFixed(2)} msg/s'),
          if (interval.medianMs != null)
            ('Interval', '${_ms(interval.medianMs)} (${_ms(interval.p10Ms)} – ${_ms(interval.p90Ms)})'),
          ('Size', '${observed.sizeMin} – ${observed.sizeMax} B'),
          if (observed.mainQos != null) ('QoS', '${observed.mainQos}'),
          ('Retained', '${observed.retainedSnapshot} snapshot, ${observed.retainedLive} live'),
        ]),
      ]);
    }
    return blocks;
  }

  static List<DocBlock> _payload(PayloadSpec payload, DocExportOptions options) {
    var rows = SchemaPaths.flatten(payload.schema);
    var examples =
        options.includeExamples ? payload.examples.where((example) => example.payload.isNotEmpty) : <DocExample>[];
    return [
      LabelBlock('Payload'),
      FactsBlock([
        ('Format', _label(payload.format.name)),
        if (payload.encoding != null) ('Encoding', payload.encoding!),
        if (payload.unit != null) ('Unit', payload.unit!),
        if (payload.min != null || payload.max != null) ('Range', '${_number(payload.min)} – ${_number(payload.max)}'),
        if (payload.allowedValues.isNotEmpty) ('Allowed values', payload.allowedValues.join(', ')),
      ]),
      if (rows.isNotEmpty)
        TableBlock([
          'Field',
          'Type',
          'Unit',
          'Range or values',
          'Required',
          'Description'
        ], [
          for (var row in rows)
            [
              row.path,
              row.node.format == null
                  ? _schemaType(row.node.type)
                  : '${_schemaType(row.node.type)} (${row.node.format})',
              row.node.unit ?? '',
              row.node.enumValues.isNotEmpty
                  ? row.node.enumValues.join(', ')
                  : row.node.minimum == null && row.node.maximum == null
                      ? ''
                      : '${_number(row.node.minimum)} – ${_number(row.node.maximum)}',
              row.required ? 'yes' : '',
              row.node.description,
            ]
        ]),
      for (var example in examples) ...[
        if (example.note.isNotEmpty) LabelBlock('Example: ${example.note}') else LabelBlock('Example'),
        CodeBlock(_pretty(example.payload), payload.format == PayloadFormat.json ? 'json' : ''),
      ],
    ];
  }

  static List<DocBlock> _delivery(TopicSpec topic) => [
        LabelBlock('Delivery'),
        FactsBlock([
          ('QoS', topic.qos == null ? 'not documented' : '${topic.qos!.index}'),
          ('Retain', _label(topic.retain.name)),
          ('Interval', _label(topic.interval.kind.name)),
          if (topic.interval.nominalMs != null) ('Nominal interval', _ms(topic.interval.nominalMs)),
          if (topic.interval.staleAfterMs != null) ('Stale after', _ms(topic.interval.staleAfterMs)),
          if (topic.lastWill) ('Last will', 'yes'),
        ]),
      ];

  static List<DocBlock> _mqtt5(Mqtt5Spec mqtt5) {
    var facts = [
      if (mqtt5.contentType != null) ('Content type', mqtt5.contentType!),
      if (mqtt5.utf8Payload == true) ('Payload format', 'UTF-8'),
      if (mqtt5.messageExpirySeconds != null) ('Message expiry', '${mqtt5.messageExpirySeconds} s'),
      if (mqtt5.responseTopic != null) ('Response topic', mqtt5.responseTopic!),
      if (mqtt5.correlationData != null) ('Correlation data', mqtt5.correlationData!),
    ];
    if (facts.isEmpty && mqtt5.userProperties.isEmpty) {
      return [];
    }
    return [
      LabelBlock('MQTT 5'),
      if (facts.isNotEmpty) FactsBlock(facts),
      if (mqtt5.userProperties.isNotEmpty)
        TableBlock([
          'User property',
          'Description',
          'Example'
        ], [
          for (var property in mqtt5.userProperties) [property.key, property.description, property.example]
        ]),
    ];
  }

  static List<DocBlock> _access(TopicSpec topic) {
    var facts = [
      if (topic.producers.isNotEmpty) ('Producers', topic.producers.join(', ')),
      if (topic.consumers.isNotEmpty) ('Consumers', topic.consumers.join(', ')),
      if (topic.sensitivity != Sensitivity.none) ('Sensitivity', _label(topic.sensitivity.name)),
    ];
    if (facts.isEmpty && topic.accessNotes.isEmpty) {
      return [];
    }
    return [
      LabelBlock('Access'),
      if (facts.isNotEmpty) FactsBlock(facts),
      if (topic.accessNotes.isNotEmpty) MarkdownBlock(topic.accessNotes),
    ];
  }

  // ---------- Markdown ----------

  String toMarkdown() {
    var out = StringBuffer('# ${_mdText(title)}\n');
    for (var block in blocks) {
      out.writeln();
      switch (block) {
        case HeadingBlock():
          var anchor = block.anchor == null ? '' : '<a id="${block.anchor}"></a>';
          var code = block.code == null ? '' : '`${block.code}`${block.text.isEmpty ? '' : ' — '}';
          out.writeln('${'#' * block.level} $anchor$code${_mdText(block.text)}');
        case MarkdownBlock():
          out.writeln(block.text.trim());
        case LabelBlock():
          out.writeln('**${_mdText(block.text)}**');
        case FactsBlock():
          out.writeln(block.facts.map((fact) => '**${_mdText(fact.$1)}:** ${_mdText(fact.$2)}').join(' · '));
        case TableBlock():
          out.writeln('| ${block.headers.map(_mdCell).join(' | ')} |');
          out.writeln('|${block.headers.map((_) => '---').join('|')}|');
          for (var row in block.rows) {
            out.writeln('| ${row.map(_mdCell).join(' | ')} |');
          }
        case CodeBlock():
          out.writeln('```${block.language}\n${block.text}\n```');
        case TocBlock():
          for (var entry in block.entries) {
            var text = entry.text.isEmpty ? '' : ' — ${_mdText(entry.text)}';
            out.writeln('${'  ' * entry.depth}- [`${entry.code}`](#${entry.anchor})$text');
          }
      }
    }
    return out.toString();
  }

  static String _mdText(String text) => text.replaceAll('\n', ' ');

  static String _mdCell(String text) => text.replaceAll('|', r'\|').replaceAll('\r', '').replaceAll('\n', '<br>');

  // ---------- HTML ----------

  String toHtml() {
    var out = StringBuffer()
      ..writeln('<!doctype html>')
      ..writeln('<html lang="en"><head><meta charset="utf-8">')
      ..writeln('<meta name="viewport" content="width=device-width, initial-scale=1">')
      ..writeln('<title>${_html(title)}</title>')
      ..writeln('<style>$_css</style>')
      ..writeln('</head><body><main>')
      ..writeln('<h1>${_html(title)}</h1>');
    for (var block in blocks) {
      switch (block) {
        case HeadingBlock():
          var id = block.anchor == null ? '' : ' id="${block.anchor}"';
          var code = block.code == null ? '' : '<code class="topic">${_html(block.code!)}</code> ';
          out.writeln('<h${block.level}$id>$code${_html(block.text)}</h${block.level}>');
        case MarkdownBlock():
          for (var paragraph in block.text.trim().split(RegExp(r'\n\s*\n'))) {
            out.writeln('<p>${_html(paragraph).replaceAll('\n', '<br>')}</p>');
          }
        case LabelBlock():
          out.writeln('<h3>${_html(block.text)}</h3>');
        case FactsBlock():
          out.writeln(
              '<p class="facts">${block.facts.map((fact) => '<span><b>${_html(fact.$1)}</b> ${_html(fact.$2)}</span>').join('')}</p>');
        case TableBlock():
          out.writeln(
              '<div class="table"><table><thead><tr>${block.headers.map((header) => '<th>${_html(header)}</th>').join()}</tr></thead><tbody>');
          for (var row in block.rows) {
            out.writeln('<tr>${row.map((cell) => '<td>${_html(cell)}</td>').join()}</tr>');
          }
          out.writeln('</tbody></table></div>');
        case CodeBlock():
          out.writeln('<pre><code>${_html(block.text)}</code></pre>');
        case TocBlock():
          out.writeln('<nav><ul>');
          for (var entry in block.entries) {
            var text = entry.text.isEmpty ? '' : ' ${_html(entry.text)}';
            out.writeln(
                '<li style="margin-left:${entry.depth * 16}px"><a href="#${entry.anchor}"><code>${_html(entry.code)}</code>$text</a></li>');
          }
          out.writeln('</ul></nav>');
      }
    }
    out.writeln('</main></body></html>');
    return out.toString();
  }

  // text between tags only, so / and quotes stay readable
  static String _html(String text) => const HtmlEscape(HtmlEscapeMode.element).convert(text);

  // the app's look: Segoe UI, grey chrome, dividers; a print stylesheet for PDF
  static const String _css = '''
:root{--ink:#1d1b20;--hint:#00000099;--divider:#0000001f;--primary:#616161;--surface:#fff;--chip:#9e9e9e}
body{margin:0;background:#fafafa;color:var(--ink);font:14px/1.5 "Segoe UI",system-ui,-apple-system,Roboto,Arial,sans-serif}
main{max-width:1100px;margin:0 auto;padding:24px 16px 48px}
h1{font-size:28px;font-weight:500;margin:0 0 12px}
h2{font-size:18px;font-weight:500;margin:40px 0 8px;padding-top:12px;border-top:1px solid var(--divider)}
h3{font-size:14px;font-weight:600;margin:16px 0 6px}
code{font-family:Consolas,"Cascadia Mono",monospace;font-size:13px}
code.topic{display:inline-block;background:var(--chip);color:#fff;border-radius:999px;padding:2px 12px;font-family:inherit;font-weight:600}
.facts{display:flex;flex-wrap:wrap;gap:4px 20px;margin:6px 0}
.facts b{font-weight:500;color:var(--hint);margin-right:4px}
.table{overflow-x:auto}
table{border-collapse:collapse;width:100%;margin:4px 0 8px}
th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--divider);vertical-align:top}
th{font-weight:500;color:#000000dd}
pre{background:var(--surface);border:1px solid var(--divider);border-radius:4px;padding:8px 12px;overflow-x:auto;white-space:pre-wrap}
nav ul{list-style:none;padding:0;margin:0}
nav li{padding:2px 0}
a{color:var(--primary)}
@media print{body{background:#fff}main{max-width:none;padding:0}h2{break-after:avoid}pre,table{break-inside:avoid}a{color:inherit;text-decoration:none}}
''';

  // ---------- values ----------

  static String _date(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    var local = at.toLocal();
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  static String _label(String name) {
    var words = name.replaceAllMapped(RegExp(r'[A-Z]'), (match) => ' ${match[0]!.toLowerCase()}');
    return words.isEmpty ? words : '${words[0].toUpperCase()}${words.substring(1)}';
  }

  static String _schemaType(SchemaType type) => type == SchemaType.nullValue ? 'null' : type.name;

  static String _number(double? value) {
    if (value == null) {
      return '';
    }
    return value == value.roundToDouble() && value.abs() < 1e15 ? value.toInt().toString() : value.toString();
  }

  static String _ms(int? ms) {
    if (ms == null) {
      return '';
    }
    if (ms < 1000) {
      return '$ms ms';
    }
    var seconds = ms / 1000;
    return seconds == seconds.roundToDouble() ? '${seconds.toInt()} s' : '${seconds.toStringAsFixed(1)} s';
  }

  static String _pretty(String payload) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(payload));
    } on FormatException {
      return payload;
    }
  }
}
