import 'dart:convert';
import 'package:mqttstudio/documentation/engine/doc_index.dart';
import 'package:mqttstudio/documentation/engine/schema_paths.dart';
import 'package:mqttstudio/documentation/export/doc_export.dart';
import 'package:mqttstudio/documentation/export/markdown_html.dart';
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

// text the user wrote in Markdown: Markdown keeps it, HTML renders it
class MarkdownBlock extends DocBlock {
  final String text;

  MarkdownBlock(this.text);
}

class LabelBlock extends DocBlock {
  final String text;

  LabelBlock(this.text);
}

class Fact {
  final String label;
  final String value;
  // a web address, or #anchor of a node in the same export
  final String? href;

  Fact(this.label, this.value, {this.href});
}

class FactsBlock extends DocBlock {
  final List<Fact> facts;

  FactsBlock(this.facts);
}

class TableBlock extends DocBlock {
  final List<String> headers;
  final List<List<String>> rows;

  TableBlock(this.headers, this.rows);

  // the columns after the first one that are empty in every row are left out
  factory TableBlock.compact(List<String> headers, List<List<String>> rows) {
    var keep = [
      for (var column = 0; column < headers.length; column++)
        if (column == 0 || rows.any((row) => row[column].isNotEmpty)) column
    ];
    return TableBlock([for (var column in keep) headers[column]], [
      for (var row in rows) [for (var column in keep) row[column]]
    ]);
  }
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
// (doc/documentation-design.md §9.1). Fields that are not documented are left out.
class DocBlocks {
  final String title;
  final List<DocBlock> blocks;
  // the anchor of a [label](topic:path) link in a description, null when the path is not in the export
  final String? Function(String path) topicAnchor;

  DocBlocks(this.title, this.blocks, {String? Function(String path)? topicAnchor})
      : topicAnchor = topicAnchor ?? ((_) => null);

  static DocBlocks build(TopicDocumentation documentation, List<DocNode> nodes, DocExportOptions options,
      {MqttSettings? broker, required DateTime exportedAt}) {
    var title = documentation.title.isEmpty ? 'MQTT topic documentation' : documentation.title;
    var anchors = {for (var (index, node) in nodes.indexed) node.path: 't${index + 1}'};
    var index = DocIndex(nodes);
    // a link names a documented path or a concrete topic one of them matches
    String? anchorOf(String path) {
      var anchor = anchors[path] ?? anchors[index.match(path)?.node.path];
      return anchor == null ? null : '#$anchor';
    }

    var server = broker == null || !options.includeBroker ? null : DocExport.brokerOf(broker);
    var blocks = <DocBlock>[
      if (documentation.description.isNotEmpty) MarkdownBlock(documentation.description),
      FactsBlock([
        if (documentation.owner.isNotEmpty) Fact('Owner', documentation.owner),
        if (server != null) Fact('Broker', '${server.host} · ${server.protocol} · MQTT ${server.protocolVersion}'),
        Fact('Topics', '${nodes.where((node) => node.isTopic).length}'),
        Fact('Revision', '${documentation.revision}'),
        Fact('Exported', _date(exportedAt)),
      ]),
      if (nodes.isNotEmpty) ...[
        HeadingBlock(2, 'Contents'),
        TocBlock([
          for (var node in nodes)
            (depth: _depth(node, nodes), code: node.path, text: node.title, anchor: anchors[node.path]!)
        ]),
      ],
      for (var node in nodes) ..._node(node, anchors[node.path]!, options, anchorOf),
    ];
    return DocBlocks(title, blocks, topicAnchor: anchorOf);
  }

  static int _depth(DocNode node, List<DocNode> nodes) =>
      nodes.where((other) => other != node && node.path.startsWith('${other.path}/')).length;

  static List<DocBlock> _node(
      DocNode node, String anchor, DocExportOptions options, String? Function(String path) anchorOf) {
    var replacedBy = node.replacedBy;
    var blocks = <DocBlock>[
      HeadingBlock(2, node.title, code: node.path, anchor: anchor),
      FactsBlock([
        Fact('Status', _label(node.status.name)),
        if (!node.isTopic) Fact('Kind', 'Namespace'),
        if (replacedBy != null) Fact('Replaced by', replacedBy, href: anchorOf(replacedBy)),
        if (node.owner.isNotEmpty) Fact('Owner', node.owner),
        if (node.tags.isNotEmpty) Fact('Tags', node.tags.join(', ')),
      ]),
      if (node.description.isNotEmpty) MarkdownBlock(node.description),
      ..._links(node.links),
      ..._parameters(node.parameters),
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
          Fact('Source', '${observed.source.name}${observed.sourceName == null ? '' : ' ${observed.sourceName}'}'),
          Fact('From', _date(observed.from)),
          Fact('Messages', '${observed.messages}'),
          Fact('Instances', '${observed.instanceCount}'),
          Fact('Rate', '${interval.rate.toStringAsFixed(2)} msg/s'),
          if (interval.medianMs != null)
            Fact('Interval', '${_ms(interval.medianMs)} (${_ms(interval.p10Ms)} – ${_ms(interval.p90Ms)})'),
          Fact('Size', '${observed.sizeMin} – ${observed.sizeMax} B'),
          if (observed.mainQos != null) Fact('QoS', '${observed.mainQos}'),
          Fact('Retained', '${observed.retainedSnapshot} snapshot, ${observed.retainedLive} live'),
        ]),
      ]);
    }
    return blocks;
  }

  static List<DocBlock> _links(List<DocLink> links) {
    var filled = links.where((link) => link.url.isNotEmpty || link.label.isNotEmpty).toList();
    if (filled.isEmpty) {
      return [];
    }
    return [
      LabelBlock('Links'),
      FactsBlock([
        for (var link in filled)
          Fact(link.label.isEmpty ? 'Link' : link.label, link.url,
              href: MarkdownHtml.isSafeUrl(link.url) ? link.url.trim() : null)
      ]),
    ];
  }

  static List<DocBlock> _parameters(List<DocParameter> parameters) {
    if (parameters.isEmpty) {
      return [];
    }
    return [
      LabelBlock('Parameters'),
      TableBlock.compact([
        'Name',
        'Pattern',
        'Description',
        'Examples'
      ], [
        for (var parameter in parameters)
          [parameter.name, parameter.pattern ?? '', parameter.description, parameter.examples.join(', ')]
      ]),
    ];
  }

  static List<DocBlock> _payload(PayloadSpec payload, DocExportOptions options) {
    var schema = payload.schema;
    var rows = [
      // a schema whose payload is not an object, or that is described itself, gets a row for the payload
      if (schema != null && (schema.type != SchemaType.object || _hasDetails(schema)))
        SchemaRow(SchemaPaths.root, schema, false),
      ...SchemaPaths.flatten(schema),
    ];
    var examples = options.includeExamples
        ? payload.examples.where((example) => example.payload.isNotEmpty).toList()
        : <DocExample>[];
    var facts = [
      if (payload.format != PayloadFormat.unknown) Fact('Format', _label(payload.format.name)),
      if (payload.encoding != null) Fact('Encoding', payload.encoding!),
      if (payload.unit != null) Fact('Unit', payload.unit!),
      if (payload.min != null || payload.max != null) Fact('Range', _range(payload.min, payload.max)),
      if (payload.allowedValues.isNotEmpty) Fact('Allowed values', payload.allowedValues.join(', ')),
    ];
    if (facts.isEmpty && rows.isEmpty && examples.isEmpty) {
      return [];
    }
    return [
      LabelBlock('Payload'),
      if (facts.isNotEmpty) FactsBlock(facts),
      if (rows.isNotEmpty)
        TableBlock.compact([
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
              [
                if (row.node.enumValues.isNotEmpty) row.node.enumValues.join(', '),
                if (row.node.minimum != null || row.node.maximum != null)
                  _range(row.node.minimum, row.node.maximum),
              ].join('; '),
              row.required ? 'yes' : '',
              row.node.description,
            ]
        ]),
      for (var example in examples) ...[
        LabelBlock(example.note.isEmpty ? 'Example' : 'Example: ${example.note}'),
        if (example.topic != null || example.capturedAt != null)
          FactsBlock([
            if (example.topic != null) Fact('Topic', example.topic!),
            if (example.capturedAt != null) Fact('Captured', _date(example.capturedAt!)),
          ]),
        CodeBlock(_pretty(example.payload), payload.format == PayloadFormat.json ? 'json' : ''),
      ],
    ];
  }

  static bool _hasDetails(SchemaNode node) =>
      node.description.isNotEmpty ||
      node.unit != null ||
      node.format != null ||
      node.minimum != null ||
      node.maximum != null ||
      node.enumValues.isNotEmpty;

  static List<DocBlock> _delivery(TopicSpec topic) {
    var facts = [
      if (topic.qos != null) Fact('QoS', '${topic.qos!.index}'),
      if (topic.retain != RetainMode.unknown) Fact('Retain', _label(topic.retain.name)),
      if (topic.interval.kind != IntervalKind.unknown) Fact('Interval', _label(topic.interval.kind.name)),
      if (topic.interval.nominalMs != null) Fact('Nominal interval', _ms(topic.interval.nominalMs)),
      if (topic.interval.staleAfterMs != null) Fact('Stale after', _ms(topic.interval.staleAfterMs)),
      if (topic.lastWill) Fact('Last will', 'yes'),
    ];
    return facts.isEmpty ? [] : [LabelBlock('Delivery'), FactsBlock(facts)];
  }

  static List<DocBlock> _mqtt5(Mqtt5Spec mqtt5) {
    var facts = [
      if (mqtt5.contentType != null) Fact('Content type', mqtt5.contentType!),
      if (mqtt5.utf8Payload == true) Fact('Payload format', 'UTF-8'),
      if (mqtt5.messageExpirySeconds != null) Fact('Message expiry', '${mqtt5.messageExpirySeconds} s'),
      if (mqtt5.responseTopic != null) Fact('Response topic', mqtt5.responseTopic!),
      if (mqtt5.correlationData != null) Fact('Correlation data', mqtt5.correlationData!),
    ];
    var properties = mqtt5.userProperties.where((property) => property.key.isNotEmpty).toList();
    if (facts.isEmpty && properties.isEmpty) {
      return [];
    }
    return [
      LabelBlock('MQTT 5'),
      if (facts.isNotEmpty) FactsBlock(facts),
      if (properties.isNotEmpty)
        TableBlock.compact([
          'User property',
          'Description',
          'Example'
        ], [
          for (var property in properties) [property.key, property.description, property.example]
        ]),
    ];
  }

  static List<DocBlock> _access(TopicSpec topic) {
    var facts = [
      if (topic.producers.isNotEmpty) Fact('Producers', topic.producers.join(', ')),
      if (topic.consumers.isNotEmpty) Fact('Consumers', topic.consumers.join(', ')),
      if (topic.sensitivity != Sensitivity.none) Fact('Sensitivity', _label(topic.sensitivity.name)),
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

  static final RegExp _topicLink = RegExp(r'\]\(topic:([^)\s]+)\)');

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
          // links to documented topics point to their section
          out.writeln(block.text.trim().replaceAllMapped(_topicLink, (match) {
            var anchor = topicAnchor(match.group(1)!);
            return anchor == null ? match.group(0)! : ']($anchor)';
          }));
        case LabelBlock():
          out.writeln('**${_mdText(block.text)}**');
        case FactsBlock():
          out.writeln(block.facts.map(_mdFact).join(' · '));
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

  static String _mdFact(Fact fact) {
    var value = _mdText(fact.value);
    return '**${_mdText(fact.label)}:** ${fact.href == null ? value : '[$value](${fact.href})'}';
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
    // a node's heading and each label start a part, so printing keeps a label with its facts and table
    var inPart = false;
    for (var block in blocks) {
      if (block is HeadingBlock || block is LabelBlock) {
        if (inPart) {
          out.writeln('</div>');
        }
        inPart = block is LabelBlock || (block as HeadingBlock).anchor != null;
        if (inPart) {
          out.writeln('<div class="part">');
        }
      }
      switch (block) {
        case HeadingBlock():
          var id = block.anchor == null ? '' : ' id="${block.anchor}"';
          var code = block.code == null ? '' : '<code class="topic">${_html(block.code!)}</code> ';
          out.writeln('<h${block.level}$id>$code${_html(block.text)}</h${block.level}>');
        case MarkdownBlock():
          out.writeln('<div class="text">${MarkdownHtml.convert(block.text, topicHref: topicAnchor)}</div>');
        case LabelBlock():
          out.writeln('<h3>${_html(block.text)}</h3>');
        case FactsBlock():
          out.writeln('<p class="facts">${block.facts.map(_htmlFact).join('')}</p>');
        case TableBlock():
          out.writeln(
              '<div class="table"><table><thead><tr>${block.headers.map((header) => '<th>${_html(header)}</th>').join()}</tr></thead><tbody>');
          for (var row in block.rows) {
            out.writeln('<tr>${row.map((cell) => '<td>${_html(cell).replaceAll('\n', '<br>')}</td>').join()}</tr>');
          }
          out.writeln('</tbody></table></div>');
        case CodeBlock():
          out.writeln('<pre><code>${_html(block.text)}</code></pre>');
        case TocBlock():
          out.writeln('<nav><ul>');
          for (var entry in block.entries) {
            var text = entry.text.isEmpty ? '' : ' <span>${_html(entry.text)}</span>';
            out.writeln(
                '<li style="margin-left:${entry.depth * 16}px"><a href="#${entry.anchor}"><code>${_html(entry.code)}</code>$text</a></li>');
          }
          out.writeln('</ul></nav>');
      }
    }
    if (inPart) {
      out.writeln('</div>');
    }
    out.writeln('</main></body></html>');
    return out.toString();
  }

  static String _htmlFact(Fact fact) {
    var value = _html(fact.value);
    if (fact.href != null) {
      value = '<a href="${MarkdownHtml.attribute(fact.href!)}">$value</a>';
    }
    return '<span><b>${_html(fact.label)}</b> $value</span>';
  }

  // text between tags only, so / and quotes stay readable
  static String _html(String text) => MarkdownHtml.escape(text);

  // the app's look: Segoe UI, grey chrome, dividers; a print stylesheet for PDF that keeps headings with what follows
  // them, wraps long paths instead of clipping them and repeats table headers on a new page
  static const String _css = '''
:root{--ink:#1d1b20;--hint:#00000099;--divider:#0000001f;--primary:#616161;--surface:#fff;--chip:#9e9e9e}
body{margin:0;background:#fafafa;color:var(--ink);font:14px/1.5 "Segoe UI",system-ui,-apple-system,Roboto,Arial,sans-serif}
main{max-width:1100px;margin:0 auto;padding:24px 16px 48px}
h1{font-size:28px;font-weight:500;margin:0 0 12px}
h2{font-size:18px;font-weight:500;margin:40px 0 8px;padding-top:12px;border-top:1px solid var(--divider)}
h3{font-size:14px;font-weight:600;margin:16px 0 6px}
h4{font-size:14px;font-weight:600;margin:12px 0 4px}
code{font-family:Consolas,"Cascadia Mono",monospace;font-size:13px}
code.topic{display:inline-block;max-width:100%;overflow-wrap:anywhere;background:var(--chip);color:#fff;border-radius:999px;padding:2px 12px;font-family:inherit;font-weight:600}
.facts{display:flex;flex-wrap:wrap;gap:4px 20px;margin:6px 0}
.facts span{overflow-wrap:anywhere}
.facts b{font-weight:500;color:var(--hint);margin-right:4px}
.text p,.text ul,.text ol{margin:6px 0}
.text blockquote{margin:6px 0;padding-left:12px;border-left:3px solid var(--divider);color:var(--hint)}
.table{overflow-x:auto}
table{border-collapse:collapse;width:100%;margin:4px 0 8px}
th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--divider);vertical-align:top;overflow-wrap:anywhere}
th{font-weight:500;color:#000000dd}
pre{background:var(--surface);border:1px solid var(--divider);border-radius:4px;padding:8px 12px;overflow-x:auto;white-space:pre-wrap;overflow-wrap:anywhere}
nav ul{list-style:none;padding:0;margin:0}
nav li{padding:2px 0}
nav span{color:var(--ink)}
a{color:var(--primary)}
@page{margin:16mm 14mm}
@media print{
body{background:#fff;font-size:12px}main{max-width:none;padding:0}
h2,h3,h4{break-after:avoid}.part,.facts,tr,nav li{break-inside:avoid}
.table,pre{overflow:visible}thead{display:table-header-group}
code.topic{-webkit-print-color-adjust:exact;print-color-adjust:exact}a{color:inherit;text-decoration:none}
}
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

  static String _range(double? min, double? max) {
    if (min == null) {
      return '≤ ${_number(max)}';
    }
    if (max == null) {
      return '≥ ${_number(min)}';
    }
    return '${_number(min)} – ${_number(max)}';
  }

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
