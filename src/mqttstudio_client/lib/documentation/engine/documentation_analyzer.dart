import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:mqttstudio/common/utils/payload_utils.dart';
import 'package:mqttstudio/documentation/engine/doc_path.dart';
import 'package:mqttstudio/documentation/engine/schema_inferrer.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';

// The format of one payload and its parsed value
class ClassifiedPayload {
  final PayloadFormat format;
  final String? text;
  final double? number;
  final Object? json;

  const ClassifiedPayload(this.format, {this.text, this.number, this.json});

  static const int maxParseLength = 64 * 1024;

  static ClassifiedPayload of(Uint8List payload) {
    if (payload.isEmpty) {
      return const ClassifiedPayload(PayloadFormat.empty, text: '');
    }
    if (_isImage(payload)) {
      return const ClassifiedPayload(PayloadFormat.image);
    }
    String text;
    try {
      text = utf8.decode(payload);
    } on FormatException {
      return const ClassifiedPayload(PayloadFormat.binary);
    }
    var trimmed = text.trim();
    var lower = trimmed.toLowerCase();
    if (lower == 'true' || lower == 'false') {
      return ClassifiedPayload(PayloadFormat.boolean, text: text);
    }
    var number = double.tryParse(trimmed);
    if (number != null) {
      return ClassifiedPayload(PayloadFormat.number, text: text, number: number);
    }
    if ((trimmed.startsWith('{') || trimmed.startsWith('[')) && payload.length <= maxParseLength) {
      try {
        return ClassifiedPayload(PayloadFormat.json, text: text, json: jsonDecode(trimmed));
      } on FormatException {
        // text that only looks like JSON
      }
    }
    if (PayloadUtils.tryParseCoordinates(trimmed) != null) {
      return ClassifiedPayload(PayloadFormat.gnss, text: text);
    }
    return ClassifiedPayload(PayloadFormat.string, text: text);
  }

  static bool _isImage(Uint8List bytes) =>
      (bytes.length >= 4 && bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 && bytes[3] == 71) ||
      (bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255);
}

// What discovery keeps of one concrete topic: about 1 KB plus the last payload (§5.7)
class _TopicState {
  static const int intervalSamples = 32;

  int messages = 0;
  int live = 0;
  DateTime? firstSeen;
  DateTime? lastSeen;
  final Map<int, int> qosCounts = {};
  int retainedSnapshot = 0;
  int retainedLive = 0;
  int sizeMin = 0;
  int sizeMax = 0;
  int sizeTotal = 0;
  final Map<String, int> formats = {};
  double? numericMin;
  double? numericMax;
  bool numbersAreBits = true;
  // the most recent inter-arrival times in microseconds, a ring
  final List<int> intervals = [];
  int intervalCount = 0;
  int? lastOffsetMicros;
  int? lastPayloadHash;
  bool repeatedPayload = false;
  SchemaInferrer? schema;
  final Map<String, int> userPropertyKeys = {};
  final Map<String, int> contentTypes = {};
  String? lastPayload;
  DateTime? lastPayloadAt;

  void addInterval(int micros) {
    if (intervals.length < intervalSamples) {
      intervals.add(micros);
    } else {
      intervals[intervalCount % intervalSamples] = micros;
    }
    intervalCount++;
  }
}

// Collects per-topic statistics from discovered messages (doc/documentation-design.md §5.3) and merges them into the
// ObservedTopic of a documented topic or template. Retained snapshot messages count, but are no intervals.
class DocumentationAnalyzer {
  static const int defaultMaxTopics = 100000;

  final DiscoverySource source;
  final String? sourceName;
  final bool inferSchemas;
  final int maxTopics;
  final Map<String, _TopicState> _topics = {};
  DateTime? _from;
  DateTime? _to;
  int messages = 0;
  // messages of topics that came after maxTopics was reached
  int skipped = 0;

  DocumentationAnalyzer(
      {this.source = DiscoverySource.live,
      this.sourceName,
      this.inferSchemas = true,
      this.maxTopics = defaultMaxTopics});

  int get topicCount => _topics.length;

  bool get topicLimitReached => skipped > 0;

  Iterable<String> get topics => _topics.keys;

  DateTime? get from => _from;

  DateTime? get to => _to;

  bool hasSeen(String topic) => _topics.containsKey(topic);

  // receivedAt is the wall time of the message, offsetMicros of the message the time since the discovery started
  void add(RecordedMessage message, DateTime receivedAt) {
    var state = _topics[message.topic];
    if (state == null) {
      if (_topics.length >= maxTopics) {
        skipped++;
        return;
      }
      state = _topics[message.topic] = _TopicState();
    }
    messages++;
    _from ??= receivedAt;
    _to = receivedAt;
    _addTo(state, message, receivedAt);
  }

  // the connection was lost: the next message of every topic starts a new interval
  void markGap() {
    for (var state in _topics.values) {
      state.lastOffsetMicros = null;
    }
  }

  // sets the end of the observed time, e.g. when discovery stops with no message for a while
  void finish(DateTime at) {
    _from ??= at;
    if (_to == null || at.isAfter(_to!)) {
      _to = at;
    }
  }

  void _addTo(_TopicState state, RecordedMessage message, DateTime receivedAt) {
    state.messages++;
    state.firstSeen ??= receivedAt;
    state.lastSeen = receivedAt;
    var qos = message.qos.index;
    state.qosCounts.update(qos, (count) => count + 1, ifAbsent: () => 1);
    var size = message.payloadLength;
    state.sizeMin = state.messages == 1 ? size : min(state.sizeMin, size);
    state.sizeMax = max(state.sizeMax, size);
    state.sizeTotal += size;

    if (message.snapshot) {
      state.retainedSnapshot++;
    } else {
      state.live++;
      if (message.retain) {
        state.retainedLive++;
      }
      var last = state.lastOffsetMicros;
      if (last != null) {
        state.addInterval(max(0, message.offsetMicros - last));
      }
      state.lastOffsetMicros = message.offsetMicros;
    }

    var hash = Object.hashAll(message.payload);
    if (state.lastPayloadHash == hash) {
      state.repeatedPayload = true;
    }
    state.lastPayloadHash = hash;

    var payload = ClassifiedPayload.of(message.payload);
    state.formats.update(payload.format.name, (count) => count + 1, ifAbsent: () => 1);
    var number = payload.number;
    if (number != null) {
      state.numericMin = state.numericMin == null ? number : min(state.numericMin!, number);
      state.numericMax = state.numericMax == null ? number : max(state.numericMax!, number);
      if (number != 0 && number != 1) {
        state.numbersAreBits = false;
      }
    }
    if (inferSchemas && payload.format == PayloadFormat.json) {
      (state.schema ??= SchemaInferrer()).add(payload.json);
    }
    var properties = message.properties;
    if (properties != null) {
      for (var key in properties.userProperties.map((property) => property.key).toSet()) {
        state.userPropertyKeys.update(key, (count) => count + 1, ifAbsent: () => 1);
      }
      var contentType = properties.contentType;
      if (contentType != null && contentType.isNotEmpty) {
        state.contentTypes.update(contentType, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    var text = payload.text;
    state.lastPayload = text == null
        ? null
        : text.length > ObservedTopic.maxPayloadLength
            ? text.substring(0, ObservedTopic.maxPayloadLength)
            : text;
    state.lastPayloadAt = receivedAt;
  }

  // the observation of the given concrete topics as one documented topic; template names the parameters
  ObservedTopic observe(Iterable<String> topics, {DocPath? template}) {
    var states = [
      for (var topic in topics)
        if (_topics[topic] != null) (topic, _topics[topic]!)
    ];
    var from = _from ?? DateTime.now();
    var to = _to ?? from;
    var observed = ObservedTopic(source: source, sourceName: sourceName, from: from, to: to);
    if (states.isEmpty) {
      return observed;
    }
    var instances = states.map((entry) => entry.$1).toList()..sort();
    observed
      ..instanceCount = instances.length
      ..instances = instances.take(ObservedTopic.maxInstances).toList()
      ..parameterValues = _parameterValues(instances, template);

    var intervals = <int>[];
    var live = 0;
    var repeated = false;
    var bits = true;
    var sizeTotal = 0;
    SchemaInferrer? schema;
    DateTime? lastAt;
    for (var (topic, state) in states) {
      observed.messages += state.messages;
      live += state.live;
      observed.retainedSnapshot += state.retainedSnapshot;
      observed.retainedLive += state.retainedLive;
      for (var entry in state.qosCounts.entries) {
        observed.qosCounts.update(entry.key, (count) => count + entry.value, ifAbsent: () => entry.value);
      }
      for (var entry in state.formats.entries) {
        observed.formats.update(entry.key, (count) => count + entry.value, ifAbsent: () => entry.value);
      }
      _addCounts(observed.userPropertyKeys, state.userPropertyKeys);
      _addCounts(observed.contentTypes, state.contentTypes);
      observed.firstSeen = _earlier(observed.firstSeen, state.firstSeen);
      observed.lastSeen = _later(observed.lastSeen, state.lastSeen);
      observed.sizeMin = identical(state, states.first.$2) ? state.sizeMin : min(observed.sizeMin, state.sizeMin);
      observed.sizeMax = max(observed.sizeMax, state.sizeMax);
      sizeTotal += state.sizeTotal;
      if (state.numericMin != null) {
        observed.numericMin =
            observed.numericMin == null ? state.numericMin : min(observed.numericMin!, state.numericMin!);
        observed.numericMax =
            observed.numericMax == null ? state.numericMax : max(observed.numericMax!, state.numericMax!);
      }
      bits = bits && state.numbersAreBits;
      repeated = repeated || state.repeatedPayload;
      intervals.addAll(state.intervals);
      if (state.schema != null) {
        (schema ??= SchemaInferrer()).merge(state.schema!);
      }
      if (state.lastPayloadAt != null && (lastAt == null || state.lastPayloadAt!.isAfter(lastAt))) {
        lastAt = state.lastPayloadAt;
        observed
          ..lastPayload = state.lastPayload
          ..lastTopic = topic
          ..lastPayloadAt = state.lastPayloadAt;
      }
    }
    observed.sizeAverage = observed.messages == 0 ? 0 : sizeTotal / observed.messages;
    if (schema != null) {
      observed
        ..schema = schema.build()
        ..fieldPresence = schema.presence();
    }
    _numbersAsBoolean(observed, bits);
    observed.interval = _interval(intervals, live, repeated, to.difference(from));
    return observed;
  }

  // a number topic that only ever sent 0 and 1 is a boolean (§5.3)
  static void _numbersAsBoolean(ObservedTopic observed, bool bits) {
    var numbers = observed.formats[PayloadFormat.number.name] ?? 0;
    if (bits && numbers >= 10 && observed.formats.length == 1) {
      observed.formats = {PayloadFormat.boolean.name: numbers};
    }
  }

  static ObservedInterval _interval(List<int> intervals, int live, bool repeated, Duration observed) {
    var rate = observed.inMicroseconds <= 0 ? 0.0 : live * Duration.microsecondsPerSecond / observed.inMicroseconds;
    if (intervals.isEmpty) {
      return ObservedInterval(kind: IntervalKind.unknown, rate: rate);
    }
    intervals.sort();
    int percentile(double p) => intervals[min(intervals.length - 1, (p * (intervals.length - 1)).round())];
    int ms(int micros) => (micros / 1000).round();
    var median = percentile(0.5);
    var p10 = percentile(0.1);
    var p90 = percentile(0.9);
    IntervalKind kind;
    if (live < 3) {
      kind = IntervalKind.unknown;
    } else if (intervals.length >= 5 && median > 0 && (p90 - p10) / median < 0.4) {
      kind = IntervalKind.periodic;
    } else if (!repeated) {
      kind = IntervalKind.onChange;
    } else {
      kind = IntervalKind.event;
    }
    return ObservedInterval(
        kind: kind,
        medianMs: ms(median),
        p10Ms: ms(p10),
        p90Ms: ms(p90),
        minMs: ms(intervals.first),
        maxMs: ms(intervals.last),
        rate: rate);
  }

  static Map<String, List<String>> _parameterValues(List<String> topics, DocPath? template) {
    var result = <String, Set<String>>{};
    if (template == null || !template.hasParameters) {
      return {};
    }
    for (var topic in topics) {
      var values = template.match(topic);
      if (values == null) {
        continue;
      }
      for (var entry in values.entries) {
        var set = result.putIfAbsent(entry.key, () => {});
        if (set.length < ObservedTopic.maxParameterValues) {
          set.add(entry.value);
        }
      }
    }
    return {for (var entry in result.entries) entry.key: entry.value.toList()..sort()};
  }

  static void _addCounts(Map<String, int> into, Map<String, int> from) {
    for (var entry in from.entries) {
      into.update(entry.key, (count) => count + entry.value, ifAbsent: () => entry.value);
    }
  }

  static DateTime? _earlier(DateTime? a, DateTime? b) => a == null ? b : (b == null || a.isBefore(b) ? a : b);

  static DateTime? _later(DateTime? a, DateTime? b) => a == null ? b : (b == null || a.isAfter(b) ? a : b);
}
