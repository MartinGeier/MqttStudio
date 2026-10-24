import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/doc_node_editor_model.dart';
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/documentation/engine/doc_index.dart';
import 'package:mqttstudio/documentation/engine/doc_path.dart';
import 'package:mqttstudio/documentation/engine/documentation_analyzer.dart';
import 'package:mqttstudio/documentation/engine/schema_paths.dart';
import 'package:mqttstudio/documentation/engine/template_detector.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';

enum DifferenceKind {
  format,
  schemaFieldAdded,
  schemaFieldType,
  qos,
  retain,
  interval,
  range,
  schemaRange,
  userProperty
}

// A documented value that differs from the observed one. Adopt copies the observed value into the documentation.
class DocDifference {
  final DifferenceKind kind;
  // the schema field or user property it is about
  final String? subject;
  final String documented;
  final String observed;
  final void Function(DocNode node) _apply;
  bool adopt = false;

  DocDifference(this.kind, this.documented, this.observed, this._apply, {this.subject});

  void applyTo(DocNode node) => _apply(node);
}

// A documented topic whose observed values differ from the documented ones
class ChangedItem {
  final DocNode node;
  final ObservedTopic observed;
  final List<DocDifference> differences;

  ChangedItem(this.node, this.observed, this.differences);
}

// A topic or template that is not documented yet. A template can also collapse documented topics into itself.
class NewItem {
  final DetectedTopic detected;
  final ObservedTopic observed;
  // documented topics the template replaces; the first one keeps its texts
  final List<DocNode> collapses;
  bool accept = true;
  // false: the template's topics are added one by one
  bool asTemplate = true;
  // a rejected item goes into the ignore filters of future discoveries
  bool ignore = false;
  // new names of the template's parameters
  final Map<String, String> names = {};

  NewItem(this.detected, this.observed, {this.collapses = const []});

  bool get isTemplate => detected.isTemplate;

  String get path {
    var path = detected.path;
    for (var entry in names.entries) {
      path = path.replaceAll('{${entry.key}}', '{${entry.value}}');
    }
    return path;
  }

  List<String> get parameterNames => DocPath.parameterNames(detected.path);
}

class DiscoveryResult {
  final DiscoverySource source;
  final String? sourceName;
  final DateTime from;
  final DateTime to;
  final int messages;
  final int topicCount;
  final int skippedMessages;
  final List<String> errors;
  final List<NewItem> added;
  final List<ChangedItem> changed;
  final List<DocNode> notSeen;
  // every documented topic that received messages, with what it received
  final Map<DocNode, ObservedTopic> matched;
  // to observe topics that are added one by one
  final DocumentationAnalyzer analyzer;

  DiscoveryResult(
      {required this.source,
      this.sourceName,
      required this.from,
      required this.to,
      required this.messages,
      required this.topicCount,
      this.skippedMessages = 0,
      this.errors = const [],
      required this.added,
      required this.changed,
      required this.notSeen,
      required this.matched,
      required this.analyzer});

  List<NewItem> get templates => added.where((item) => item.isTemplate).toList();

  Duration get duration => to.difference(from);
}

// Compares what discovery saw with the documentation and applies the reviewed result
// (doc/documentation-design.md §4.4, §5.6)
class DiscoveryMerger {
  // a nominal interval this far off counts as changed
  static const double intervalTolerance = 0.5;

  static DiscoveryResult build(
      TopicDocumentation documentation, DocumentationAnalyzer analyzer, DiscoverySettings settings,
      {bool isMqtt5 = true, List<String> errors = const []}) {
    var index = DocIndex(documentation.nodes);
    var matchedTopics = <DocNode, List<String>>{};
    var unmatched = <String>[];
    for (var topic in analyzer.topics) {
      var match = index.match(topic);
      if (match == null) {
        unmatched.add(topic);
      } else {
        matchedTopics.putIfAbsent(match.node, () => []).add(topic);
      }
    }

    var matched = <DocNode, ObservedTopic>{};
    var changed = <ChangedItem>[];
    for (var entry in matchedTopics.entries) {
      var observed = analyzer.observe(entry.value, template: DocPath.tryParse(entry.key.path));
      matched[entry.key] = observed;
      var differences = compare(entry.key, observed, isMqtt5: isMqtt5);
      if (differences.isNotEmpty) {
        changed.add(ChangedItem(entry.key, observed, differences));
      }
    }

    var added = _newItems(documentation, analyzer, unmatched, settings.detectTemplates);
    var notSeen = [
      for (var node in documentation.topics)
        if (!matched.containsKey(node) && _isListenedTo(node.path, settings.filters)) node
    ];
    return DiscoveryResult(
        source: analyzer.source,
        sourceName: analyzer.sourceName,
        from: analyzer.from ?? DateTime.now(),
        to: analyzer.to ?? DateTime.now(),
        messages: analyzer.messages,
        topicCount: analyzer.topicCount,
        skippedMessages: analyzer.skipped,
        errors: errors,
        added: added,
        changed: changed,
        notSeen: notSeen,
        matched: matched,
        analyzer: analyzer);
  }

  static List<NewItem> _newItems(
      TopicDocumentation documentation, DocumentationAnalyzer analyzer, List<String> unmatched, bool detectTemplates) {
    if (!detectTemplates) {
      return [
        for (var topic in unmatched..sort())
          if (DocPath.validate(topic) == null) NewItem(DetectedTopic(topic, {topic}, {}), analyzer.observe([topic]))
      ];
    }
    // documented single topics take part, so new siblings can join them in a template
    var literals = {
      for (var node in documentation.topics)
        if (!(DocPath.tryParse(node.path)?.hasParameters ?? true)) node.path: node
    };
    var items = <NewItem>[];
    for (var detected in TemplateDetector.detect([...unmatched, ...literals.keys])) {
      var documented = [
        for (var topic in detected.topics)
          if (literals[topic] != null) literals[topic]!
      ]..sort((a, b) => a.path.compareTo(b.path));
      var fresh = detected.topics.where((topic) => !literals.containsKey(topic)).toList()..sort();
      if (!detected.isTemplate) {
        if (fresh.isNotEmpty) {
          items.add(NewItem(detected, analyzer.observe(fresh)));
        }
        continue;
      }
      var takenShape = _conflicts(documentation, detected.path, documented);
      if (takenShape || (fresh.isEmpty && documented.length < 2)) {
        for (var topic in fresh) {
          items.add(NewItem(DetectedTopic(topic, {topic}, {}), analyzer.observe([topic])));
        }
        continue;
      }
      items.add(NewItem(detected, analyzer.observe(detected.topics, template: DocPath.tryParse(detected.path)),
          collapses: documented));
    }
    items.sort((a, b) => a.detected.path.compareTo(b.detected.path));
    return items;
  }

  // a documented template that matches the same topics, other than the ones the template replaces
  static bool _conflicts(TopicDocumentation documentation, String path, List<DocNode> replaced) {
    var parsed = DocPath.tryParse(path);
    if (parsed == null) {
      return true;
    }
    for (var node in documentation.nodes) {
      if (replaced.contains(node)) {
        continue;
      }
      var other = DocPath.tryParse(node.path);
      if (node.path == path || (other != null && other.sameShape(parsed))) {
        return true;
      }
    }
    return false;
  }

  // a topic of the template, with x for every parameter value
  static String sampleTopic(String path) =>
      DocPath.tryParse(path)
          ?.segments
          .map((segment) => segment.isParameter ? '${segment.prefix}x${segment.suffix}' : segment.prefix)
          .join('/') ??
      path;

  static bool _isListenedTo(String path, List<RecorderFilter> filters) =>
      RecorderRules.isRecorded(sampleTopic(path), filters);

  // the filter that leaves a rejected topic or template out of future discoveries
  static String ignoreFilterOf(String path) =>
      DocPath.tryParse(path)?.segments.map((segment) => segment.isParameter ? '+' : segment.prefix).join('/') ?? path;

  // ---------- differences ----------

  static RetainMode observedRetain(ObservedTopic observed, {required bool isMqtt5}) {
    var live = observed.messages - observed.retainedSnapshot;
    if (isMqtt5 && live > 0) {
      if (observed.retainedLive == live) {
        return RetainMode.always;
      }
      return observed.retainedLive == 0 ? RetainMode.never : RetainMode.mixed;
    }
    return observed.retainedSnapshot > 0 ? RetainMode.always : RetainMode.unknown;
  }

  static List<DocDifference> compare(DocNode node, ObservedTopic observed, {required bool isMqtt5}) {
    var topic = node.topic;
    if (topic == null || observed.messages == 0) {
      return [];
    }
    var differences = <DocDifference>[];
    var payload = topic.payload;
    var format = observed.mainFormat;
    if (payload.format != PayloadFormat.unknown && format != PayloadFormat.unknown && payload.format != format) {
      differences.add(DocDifference(
          DifferenceKind.format, payload.format.name, format.name, (node) => node.topic!.payload.format = format));
    }
    var qos = observed.mainQos;
    if (topic.qos != null && qos != null && topic.qos!.index != qos) {
      differences.add(DocDifference(
          DifferenceKind.qos, '${topic.qos!.index}', '$qos', (node) => node.topic!.qos = MqttQos.values[qos]));
    }
    var retain = observedRetain(observed, isMqtt5: isMqtt5);
    if (topic.retain != RetainMode.unknown && retain != RetainMode.unknown && topic.retain != retain) {
      differences.add(
          DocDifference(DifferenceKind.retain, topic.retain.name, retain.name, (node) => node.topic!.retain = retain));
    }
    var nominal = topic.interval.nominalMs;
    var median = observed.interval.medianMs;
    if (nominal != null && nominal > 0 && median != null && (median - nominal).abs() / nominal > intervalTolerance) {
      differences.add(DocDifference(
          DifferenceKind.interval, '$nominal', '$median', (node) => node.topic!.interval.nominalMs = median));
    }
    _compareRange(differences, payload.min, payload.max, observed.numericMin, observed.numericMax, (node, min, max) {
      node.topic!.payload
        ..min = min
        ..max = max;
    });
    _compareSchema(differences, payload.schema, observed);
    _compareUserProperties(differences, topic.mqtt5.userProperties, observed);
    return differences;
  }

  static void _compareRange(List<DocDifference> differences, double? min, double? max, double? low, double? high,
      void Function(DocNode node, double? min, double? max) write,
      {String? subject, DifferenceKind kind = DifferenceKind.range}) {
    if (low == null || high == null || (min == null && max == null)) {
      return;
    }
    if ((min != null && low < min) || (max != null && high > max)) {
      var newMin = min == null || low >= min ? min : low;
      var newMax = max == null || high <= max ? max : high;
      differences.add(DocDifference(kind, '${_number(min)} – ${_number(max)}', '${_number(low)} – ${_number(high)}',
          (node) => write(node, newMin, newMax),
          subject: subject));
    }
  }

  static void _compareSchema(List<DocDifference> differences, SchemaNode? documented, ObservedTopic observed) {
    var seen = observed.schema;
    if (documented == null || seen == null) {
      return;
    }
    for (var row in SchemaPaths.flatten(seen)) {
      var field = SchemaPaths.find(documented, row.path);
      var presence = observed.fieldPresence[row.path] ?? 0;
      if (field == null) {
        var parent = row.path.substring(0, row.path.lastIndexOf(RegExp(r'\.|\[\]$')));
        if (parent != SchemaPaths.root && SchemaPaths.find(documented, parent) == null) {
          // the parent is reported, its fields come with it
          continue;
        }
        var added = _withoutRanges(row.node);
        differences.add(DocDifference(
            DifferenceKind.schemaFieldAdded,
            '',
            '${row.node.type.name} ${(presence * 100).round()} %',
            (node) => SchemaPaths.put(node.topic!.payload.schema ??= SchemaNode(), row.path, added, required: false),
            subject: row.path));
        continue;
      }
      if (!_compatible(field.type, row.node.type)) {
        var type = row.node.type;
        differences.add(DocDifference(DifferenceKind.schemaFieldType, field.type.name, type.name,
            (node) => SchemaPaths.find(node.topic!.payload.schema, row.path)?.type = type,
            subject: row.path));
      }
      _compareRange(differences, field.minimum, field.maximum, row.node.minimum, row.node.maximum, (node, min, max) {
        SchemaPaths.find(node.topic!.payload.schema, row.path)
          ?..minimum = min
          ..maximum = max;
      }, subject: row.path, kind: DifferenceKind.schemaRange);
    }
  }

  static bool _compatible(SchemaType documented, SchemaType observed) =>
      documented == observed ||
      documented == SchemaType.mixed ||
      (documented == SchemaType.number && observed == SchemaType.integer) ||
      observed == SchemaType.nullValue;

  static void _compareUserProperties(
      List<DocDifference> differences, List<DocUserProperty> documented, ObservedTopic observed) {
    if (documented.isEmpty) {
      return;
    }
    var known = documented.map((property) => property.key).toSet();
    for (var key in observed.userPropertyKeys.keys.where((key) => !known.contains(key))) {
      var share = observed.messages == 0 ? 0 : observed.userPropertyKeys[key]! * 100 ~/ observed.messages;
      differences.add(DocDifference(DifferenceKind.userProperty, '', '$share %',
          (node) => node.topic!.mqtt5.userProperties.add(DocUserProperty(key: key)),
          subject: key));
    }
  }

  static String _number(double? value) {
    if (value == null) {
      return '';
    }
    return value == value.roundToDouble() && value.abs() < 1e15 ? value.toInt().toString() : value.toString();
  }

  // the observed schema without its observed ranges: ranges are documented values the user sets (§4.4)
  static SchemaNode _withoutRanges(SchemaNode node) => SchemaNode.fromJson(node.toJson())
    ..minimum = null
    ..maximum = null
    ..properties = {for (var entry in node.properties.entries) entry.key: _withoutRanges(entry.value)}
    ..items = node.items == null ? null : _withoutRanges(node.items!);

  // ---------- prefilling ----------

  // fills the documented fields that are empty and the user never edited (T5)
  static void prefill(DocNode node, ObservedTopic observed, {required bool isMqtt5, bool keepExamples = true}) {
    var topic = node.topic;
    if (topic == null || observed.messages == 0) {
      return;
    }
    bool free(String key) => !node.editedFields.contains(key);
    var format = observed.mainFormat;
    if (topic.payload.format == PayloadFormat.unknown && free(DocNodeEditorModel.payloadFormat)) {
      topic.payload.format = format;
    }
    var schema = observed.schema;
    if (topic.payload.schema == null &&
        schema != null &&
        topic.payload.format == PayloadFormat.json &&
        !node.editedFields.any((key) => key.startsWith(DocNodeEditorModel.schemaPrefix))) {
      topic.payload.schema = _withoutRanges(schema);
    }
    var qos = observed.mainQos;
    if (topic.qos == null && qos != null && free(DocNodeEditorModel.qos)) {
      topic.qos = MqttQos.values[qos];
    }
    var retain = observedRetain(observed, isMqtt5: isMqtt5);
    if (topic.retain == RetainMode.unknown && free(DocNodeEditorModel.retain)) {
      topic.retain = retain;
    }
    var interval = observed.interval;
    if (topic.interval.kind == IntervalKind.unknown && free(DocNodeEditorModel.intervalKind)) {
      topic.interval.kind = interval.kind;
    }
    if (topic.interval.nominalMs == null &&
        interval.kind == IntervalKind.periodic &&
        free(DocNodeEditorModel.nominalInterval)) {
      topic.interval.nominalMs = interval.medianMs;
    }
    if (topic.interval.staleAfterMs == null &&
        interval.medianMs != null &&
        interval.kind == IntervalKind.periodic &&
        free(DocNodeEditorModel.staleAfter)) {
      topic.interval.staleAfterMs = interval.medianMs! * 3;
    }
    if (keepExamples &&
        topic.payload.examples.isEmpty &&
        observed.lastPayload != null &&
        free(DocNodeEditorModel.examples)) {
      topic.payload.examples.add(
          DocExample(payload: observed.lastPayload!, topic: observed.lastTopic, capturedAt: observed.lastPayloadAt));
    }
    if (isMqtt5) {
      var contentType = _most(observed.contentTypes);
      if (topic.mqtt5.contentType == null && contentType != null && free(DocNodeEditorModel.contentType)) {
        topic.mqtt5.contentType = contentType;
      }
      if (topic.mqtt5.userProperties.isEmpty && free(DocNodeEditorModel.userProperties)) {
        topic.mqtt5.userProperties = [
          for (var key in observed.userPropertyKeys.keys.toList()..sort()) DocUserProperty(key: key)
        ];
      }
    }
    for (var parameter in node.parameters) {
      parameter.examples = observed.parameterValues[parameter.name] ?? parameter.examples;
    }
  }

  static String? _most(Map<String, int> counts) {
    String? best;
    for (var entry in counts.entries) {
      if (best == null || entry.value > counts[best]!) {
        best = entry.key;
      }
    }
    return best;
  }

  // ---------- applying the review ----------

  static void apply(TopicDocumentation documentation, DiscoveryResult result, DiscoverySettings settings,
      {required bool isMqtt5}) {
    for (var entry in result.matched.entries) {
      entry.key
        ..observed = entry.value
        ..review = DocReviewState.none;
      prefill(entry.key, entry.value, isMqtt5: isMqtt5, keepExamples: settings.keepExamples);
    }
    for (var item in result.changed) {
      for (var difference in item.differences.where((difference) => difference.adopt)) {
        difference.applyTo(item.node);
      }
      // the marks stay until the user opens the topic
      item.node.review =
          item.differences.any((difference) => !difference.adopt) ? DocReviewState.changed : DocReviewState.none;
    }
    for (var node in result.notSeen) {
      node.review = DocReviewState.notSeen;
    }
    for (var item in result.added) {
      if (item.accept) {
        _add(documentation, result, item, settings, isMqtt5: isMqtt5);
      } else if (item.ignore) {
        var filter = ignoreFilterOf(item.path);
        if (!documentation.ignoreFilters.contains(filter)) {
          documentation.ignoreFilters.add(filter);
        }
      }
    }
    documentation
      ..discoverySettings = settings.copy()
      ..lastDiscoveryAt = result.to
      ..revision += 1
      ..sortNodes();
  }

  static void _add(TopicDocumentation documentation, DiscoveryResult result, NewItem item, DiscoverySettings settings,
      {required bool isMqtt5}) {
    if (item.isTemplate && !item.asTemplate) {
      for (var topic in item.detected.topics.toList()..sort()) {
        if (documentation.nodeAt(topic) == null && DocPath.validate(topic) == null) {
          _addNode(documentation, DocNode(path: topic, topic: TopicSpec()), result.analyzer.observe([topic]), settings,
              isMqtt5: isMqtt5);
        }
      }
      return;
    }
    var path = item.path;
    if (DocPath.validate(path) != null || _conflicts(documentation, path, item.collapses)) {
      return;
    }
    var observed = item.observed;
    if (item.names.isNotEmpty) {
      observed.parameterValues = {
        for (var entry in observed.parameterValues.entries) item.names[entry.key] ?? entry.key: entry.value
      };
    }
    if (item.collapses.isNotEmpty) {
      var kept = item.collapses.first;
      for (var other in item.collapses.skip(1)) {
        documentation.nodes.remove(other);
      }
      var old = kept.path;
      kept.path = path;
      DocumentationService.syncParameters(kept, oldPath: old);
      _applyPatterns(kept, item);
      kept
        ..observed = observed
        ..review = DocReviewState.added;
      prefill(kept, observed, isMqtt5: isMqtt5, keepExamples: settings.keepExamples);
      return;
    }
    var node = DocNode(path: path, topic: TopicSpec());
    DocumentationService.syncParameters(node);
    _applyPatterns(node, item);
    _addNode(documentation, node, observed, settings, isMqtt5: isMqtt5);
  }

  static void _applyPatterns(DocNode node, NewItem item) {
    for (var parameter in node.parameters) {
      var original =
          item.names.entries.where((entry) => entry.value == parameter.name).map((entry) => entry.key).firstOrNull ??
              parameter.name;
      parameter.pattern ??= item.detected.patterns[original];
    }
  }

  static void _addNode(
      TopicDocumentation documentation, DocNode node, ObservedTopic observed, DiscoverySettings settings,
      {required bool isMqtt5}) {
    DocumentationService.syncParameters(node);
    node
      ..observed = observed
      ..review = DocReviewState.added;
    prefill(node, observed, isMqtt5: isMqtt5, keepExamples: settings.keepExamples);
    documentation.nodes.add(node);
  }
}
