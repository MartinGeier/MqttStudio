import 'dart:convert';
import 'dart:typed_data';
import 'package:mqttstudio/common/utils/payload_decoder.dart';
import 'package:mqttstudio/protocol/protocol_profile.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_rules.dart';

// the message types of Sparkplug B (specification 3.0 §4.1)
class SpbMessageType {
  static const String nBirth = 'NBIRTH';
  static const String nDeath = 'NDEATH';
  static const String nData = 'NDATA';
  static const String nCmd = 'NCMD';
  static const String dBirth = 'DBIRTH';
  static const String dDeath = 'DDEATH';
  static const String dData = 'DDATA';
  static const String dCmd = 'DCMD';
  static const String state = 'STATE';

  static const List<String> node = [nBirth, nDeath, nData, nCmd];
  static const List<String> device = [dBirth, dDeath, dData, dCmd];

  static bool isBirth(String type) => type == nBirth || type == dBirth;

  static bool isDeath(String type) => type == nDeath || type == dDeath;

  static bool isData(String type) => type == nData || type == dData;

  static bool isCommand(String type) => type == nCmd || type == dCmd;

  // the birth that defines the metrics and aliases of a data or command message
  static String birthOf(String type) => device.contains(type) ? dBirth : nBirth;
}

// Recognizes and interprets Sparkplug B messages (doc/sparkplug-design.md §5): the Protobuf payloads of edge nodes and
// devices, with metric names from the last birth when a message sends aliases, and the JSON or text STATE of host
// applications. Like VDA 5050 it only reads; protocol violations are SparkplugChecker's.
class SparkplugProfile implements ProtocolProfile {
  static const String namespace = 'spBv1.0';
  static const String groupKey = 'groupId';
  static const String edgeNodeKey = 'edgeNodeId';
  static const String deviceKey = 'deviceId';
  static const String hostKey = 'hostId';
  // metrics a birth defines and the specification names
  static const String bdSeqMetric = 'bdSeq';
  static const String rebirthMetric = 'Node Control/Rebirth';
  // a table shows at most this many metrics or rows
  static const int maxRows = 500;

  @override
  String get id => 'sparkplug';

  @override
  String get name => 'Sparkplug';

  // spBv1.0/{group}/{type}/{edge node}[/{device}], spBv1.0/STATE/{host} (3.0) and STATE/{host} (2.2)
  @override
  ProtocolTopic? matchTopic(String topic) {
    var levels = topic.split('/');
    if (levels.length == 2 && levels[0] == SpbMessageType.state) {
      return ProtocolTopic(this, SpbMessageType.state, topic, {hostKey: levels[1]});
    }
    if (levels.isEmpty || levels[0] != namespace) {
      return null;
    }
    if (levels.length == 3 && levels[1] == SpbMessageType.state) {
      return ProtocolTopic(this, SpbMessageType.state, topic, {hostKey: levels[2]});
    }
    var nodeMessage = levels.length == 4 && SpbMessageType.node.contains(levels[2]);
    var deviceMessage = levels.length == 5 && SpbMessageType.device.contains(levels[2]);
    if (!nodeMessage && !deviceMessage) {
      return null;
    }
    return ProtocolTopic(this, levels[2], [levels[1], levels[3], if (deviceMessage) levels[4]].join('/'), {
      groupKey: levels[1],
      edgeNodeKey: levels[3],
      if (deviceMessage) deviceKey: levels[4],
    });
  }

  static String topicOf(String type, String group, String edgeNode, [String? device]) =>
      [namespace, group, type, edgeNode, if (device != null) device].join('/');

  // the topic of the birth that names the metrics of a node or device message
  static String birthTopicOf(ProtocolTopic topic) => topicOf(
    SpbMessageType.birthOf(topic.messageType),
    topic.parameters[groupKey]!,
    topic.parameters[edgeNodeKey]!,
    topic.parameters[deviceKey],
  );

  // the payload, null when data isn't a Sparkplug B payload
  static SpbPayload? payloadOf(Object? data) {
    if (data is! Uint8List) {
      return null;
    }
    var cached = _payloads[data];
    if (cached != null) {
      return cached.payload;
    }
    SpbPayload? payload;
    try {
      payload = _decompressed(SparkplugReader.read(data));
    } on FormatException {
      payload = null;
    }
    _payloads[data] = _Read(payload);
    return payload;
  }

  // a compressed payload carries the real one in its body (specification 3.0 §7.1); GZIP and DEFLATE in the zlib
  // format, as the Eclipse Tahu libraries write it
  static const String compressedUuid = 'SPBV1.0_COMPRESSED';

  static SpbPayload _decompressed(SpbPayload payload) {
    if (payload.uuid != compressedUuid || payload.body == null) {
      return payload;
    }
    var algorithm = payload.metric('algorithm')?.value;
    var inner = SparkplugReader.read(PayloadDecoding.gunzip(payload.body!));
    inner.compressedWith = algorithm is String ? algorithm : 'GZIP';
    return inner;
  }

  // births are read again for every data message that refers to them
  static final Expando<_Read> _payloads = Expando();

  // the metrics of a birth by alias
  static Map<int, SpbMetric> aliasesOf(SpbPayload birth) => {
    for (var metric in birth.metrics)
      if (metric.alias != null) metric.alias!: metric,
  };

  @override
  ProtocolChecker createChecker() => SparkplugChecker(this);

  @override
  Interpretation? interpret(ProtocolTopic topic, Object? data, {InterpretationContext context = const NoContext()}) {
    if (topic.messageType == SpbMessageType.state) {
      return _state(topic, data);
    }
    if (data is! Uint8List) {
      return null;
    }
    var payload = payloadOf(data);
    if (payload == null) {
      return _notSparkplug(data);
    }
    return _Builder(topic, payload, context).build();
  }

  Interpretation _notSparkplug(Uint8List data) {
    String reason;
    try {
      SparkplugReader.read(data);
      reason = '';
    } on FormatException catch (exc) {
      reason = exc.message;
    }
    return Interpretation(
      protocolVersion: 'B',
      summary: 'Not a Sparkplug B payload: $reason',
      level: InterpretationLevel.error,
      sections: [
        KeyValueSection('payload', 'Payload', [
          InterpretedValue('Error', reason, level: InterpretationLevel.error),
          InterpretedValue('Size', '${data.length} bytes'),
        ]),
      ],
    );
  }

  // 3.0 sends {"online": true, "timestamp": …}, 2.2 the text ONLINE or OFFLINE
  Interpretation? _state(ProtocolTopic topic, Object? data) {
    bool? online;
    int? timestamp;
    if (data is Map) {
      var value = data['online'];
      online = value is bool ? value : null;
      var time = data['timestamp'];
      timestamp = time is num ? time.toInt() : null;
    } else if (data is Uint8List) {
      var text = utf8.decode(data, allowMalformed: true).trim();
      online = text == 'ONLINE' ? true : (text == 'OFFLINE' ? false : null);
    }
    if (online == null) {
      return null;
    }
    var host = topic.parameters[hostKey]!;
    var status = online ? 'ONLINE' : 'OFFLINE';
    return Interpretation(
      protocolVersion: 'B',
      summary: 'Host $host | $status',
      level: online ? InterpretationLevel.none : InterpretationLevel.warning,
      sections: [
        KeyValueSection('state', 'Host application', [
          InterpretedValue('Host id', host),
          InterpretedValue('State', status, level: online ? InterpretationLevel.none : InterpretationLevel.warning),
          if (timestamp != null) InterpretedValue('Timestamp', formatTimestamp(timestamp)),
          InterpretedValue('Format', data is Map ? 'JSON (Sparkplug 3.0)' : 'Text (Sparkplug 2.2)'),
        ]),
      ],
    );
  }

  static String formatTimestamp(int millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toIso8601String();

  // one value as text, short enough for a table cell
  static String formatValue(SpbMetric metric) {
    if (metric.isNull) {
      return 'null';
    }
    return formatData(metric.value);
  }

  static String formatData(Object? value) {
    return switch (value) {
      null => '—',
      double number => _number(number),
      DateTime time => time.toIso8601String(),
      Uint8List bytes => '${bytes.length} bytes',
      List list => '[${list.take(8).map(formatData).join(', ')}${list.length > 8 ? ', … ${list.length} values' : ''}]',
      SpbDataSet dataSet => 'DataSet ${dataSet.rows.length} × ${dataSet.columns.length}',
      SpbTemplate template =>
        template.isDefinition == true
            ? 'Template definition (${template.metrics.length} members)'
            : 'Template ${template.templateRef ?? ''} (${template.metrics.length} members)',
      _ => '$value',
    };
  }

  static String _number(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toStringAsFixed(0);
    }
    var text = value.toStringAsPrecision(7);
    return text.contains('.') && !text.contains('e') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
  }

  // the engineering unit of a metric, from the usual property names
  static String? unitOf(SpbMetric metric) {
    for (var entry in metric.properties?.values.entries ?? const <MapEntry<String, SpbPropertyValue>>[]) {
      var key = entry.key.toLowerCase();
      if ((key == 'engunit' || key == 'unit' || key == 'engineeringunits') && entry.value.value is String) {
        return entry.value.value as String;
      }
    }
    return null;
  }
}

class _Read {
  final SpbPayload? payload;

  const _Read(this.payload);
}

class _Builder {
  final ProtocolTopic topic;
  final SpbPayload payload;
  final InterpretationContext context;
  final List<InterpretedSection> sections = [];
  final Map<String, double> values = {};
  var level = InterpretationLevel.none;
  // the birth's metrics by alias and by name, empty for a birth or when the birth wasn't received
  Map<int, SpbMetric> _byAlias = const {};
  Map<String, SpbMetric> _byName = const {};
  bool _birthMissing = false;

  _Builder(this.topic, this.payload, this.context);

  String get type => topic.messageType;

  String get edgeNode => topic.parameters[SparkplugProfile.edgeNodeKey]!;

  String? get device => topic.parameters[SparkplugProfile.deviceKey];

  // e.g. 'E1' or 'device D1 on E1'
  String get _who => device == null ? 'edge node $edgeNode' : 'device $device on $edgeNode';

  Interpretation build() {
    _readBirth();
    _header();
    if (payload.metrics.isNotEmpty) {
      _metrics();
    }
    var summary = _summary();
    return Interpretation(protocolVersion: 'B', summary: summary, level: level, sections: sections, values: values);
  }

  // data and commands send aliases and leave out data types and units; the birth has them
  void _readBirth() {
    if (SpbMessageType.isBirth(type) || SpbMessageType.isDeath(type)) {
      return;
    }
    var birth = SparkplugProfile.payloadOf(context.lastData(SparkplugProfile.birthTopicOf(topic)));
    if (birth == null) {
      _birthMissing = payload.metrics.any((metric) => metric.name == null && metric.alias != null);
      return;
    }
    _byAlias = SparkplugProfile.aliasesOf(birth);
    _byName = {
      for (var metric in birth.metrics)
        if (metric.name != null) metric.name!: metric,
    };
  }

  SpbMetric? _defined(SpbMetric metric) => metric.name != null ? _byName[metric.name] : _byAlias[metric.alias];

  // the name from the message, else from the birth, else the alias
  String nameOf(SpbMetric metric) =>
      metric.name ?? _byAlias[metric.alias]?.name ?? (metric.alias != null ? 'alias ${metric.alias}' : '');

  SpbDataType? typeOf(SpbMetric metric) => metric.type ?? _defined(metric)?.type;

  String? unitOf(SpbMetric metric) {
    var defined = _defined(metric);
    return SparkplugProfile.unitOf(metric) ?? (defined == null ? null : SparkplugProfile.unitOf(defined));
  }

  void _header() {
    var bdSeq = payload.metric(SparkplugProfile.bdSeqMetric)?.value;
    sections.add(
      KeyValueSection('header', 'Header', [
        InterpretedValue('Message type', '$type (${_meaning()})'),
        InterpretedValue('Group', topic.parameters[SparkplugProfile.groupKey]!),
        InterpretedValue('Edge node', edgeNode),
        if (device != null) InterpretedValue('Device', device!),
        if (payload.timestamp != null)
          InterpretedValue('Timestamp', SparkplugProfile.formatTimestamp(payload.timestamp!)),
        if (payload.seq != null) InterpretedValue('Sequence number', '${payload.seq}'),
        if (bdSeq != null) InterpretedValue('Birth/death sequence (bdSeq)', '$bdSeq'),
        if (payload.uuid != null) InterpretedValue('UUID', payload.uuid!),
        if (payload.compressedWith != null) InterpretedValue('Compression', payload.compressedWith!),
        if (payload.body != null) InterpretedValue('Body', '${payload.body!.length} bytes'),
        if (_birthMissing)
          InterpretedValue(
            'Metric names',
            'No ${SpbMessageType.birthOf(type)} received yet, metrics are shown by alias',
            level: InterpretationLevel.warning,
          ),
      ]),
    );
  }

  String _meaning() => switch (type) {
    SpbMessageType.nBirth => 'the edge node came online and defines its metrics',
    SpbMessageType.nDeath => 'the edge node went offline',
    SpbMessageType.nData => 'changed metrics of the edge node',
    SpbMessageType.nCmd => 'a command to the edge node',
    SpbMessageType.dBirth => 'the device came online and defines its metrics',
    SpbMessageType.dDeath => 'the device went offline',
    SpbMessageType.dData => 'changed metrics of the device',
    SpbMessageType.dCmd => 'a command to the device',
    _ => type,
  };

  void _metrics() {
    var rows = <InterpretedRow>[];
    for (var metric in payload.metrics.take(SparkplugProfile.maxRows)) {
      var dataType = typeOf(metric);
      var unit = unitOf(metric);
      var value = SparkplugProfile.formatValue(metric);
      rows.add(
        InterpretedRow([
          nameOf(metric),
          metric.alias == null ? '' : '${metric.alias}',
          dataType?.label ?? (metric.datatype == null ? '' : '${metric.datatype}'),
          unit == null ? value : '$value $unit',
          _details(metric),
        ], muted: metric.isHistorical),
      );
      _chartValue(metric);
      _nested(metric);
    }
    var title = payload.metrics.length > SparkplugProfile.maxRows
        ? 'Metrics (first ${SparkplugProfile.maxRows} of ${payload.metrics.length})'
        : 'Metrics (${payload.metrics.length})';
    sections.add(TableSection('metrics', title, const ['Name', 'Alias', 'Type', 'Value', 'Details'], rows));
  }

  String _details(SpbMetric metric) {
    var details = <String>[
      if (metric.timestamp != null && metric.timestamp != payload.timestamp)
        SparkplugProfile.formatTimestamp(metric.timestamp!),
      if (metric.isHistorical) 'historical',
      if (metric.isTransient) 'transient',
      for (var entry in metric.properties?.values.entries ?? const <MapEntry<String, SpbPropertyValue>>[])
        if (SparkplugProfile.unitOf(metric) == null ||
            !['engunit', 'unit', 'engineeringunits'].contains(entry.key.toLowerCase()))
          '${entry.key}=${entry.value.isNull ? 'null' : SparkplugProfile.formatData(entry.value.value)}',
      if (metric.metadata?.contentType != null) metric.metadata!.contentType!,
      if (metric.metadata?.fileName != null) metric.metadata!.fileName!,
    ];
    return details.join(', ');
  }

  void _chartValue(SpbMetric metric) {
    var value = metric.value;
    if (metric.isNull || metric.isHistorical) {
      return;
    }
    var name = nameOf(metric);
    if (value is num) {
      values[name] = value.toDouble();
    } else if (value is BigInt) {
      values[name] = value.toDouble();
    } else if (value is bool) {
      values[name] = value ? 1 : 0;
    }
  }

  // data sets and templates get a table of their own
  void _nested(SpbMetric metric) {
    var value = metric.value;
    var name = nameOf(metric);
    if (value is SpbDataSet) {
      sections.add(
        TableSection('dataset:$name', 'DataSet $name', value.columns, [
          for (var row in value.rows.take(SparkplugProfile.maxRows))
            InterpretedRow([for (var cell in row) SparkplugProfile.formatData(cell)]),
        ]),
      );
    } else if (value is SpbTemplate) {
      sections.add(
        TableSection(
          'template:$name',
          'Template $name${value.templateRef == null ? '' : ' (${value.templateRef})'}',
          const ['Member', 'Type', 'Value'],
          [
            for (var member in value.metrics.take(SparkplugProfile.maxRows))
              InterpretedRow([member.name ?? '', member.type?.label ?? '', SparkplugProfile.formatValue(member)]),
            for (var parameter in value.parameters)
              InterpretedRow([
                '${parameter.name} (parameter)',
                SpbDataType.of(parameter.type)?.label ?? '',
                SparkplugProfile.formatData(parameter.value),
              ], muted: true),
          ],
        ),
      );
    }
  }

  String _summary() {
    var count = payload.metrics.length;
    var metrics = '$count ${count == 1 ? 'metric' : 'metrics'}';
    switch (type) {
      case SpbMessageType.nBirth:
        var bdSeq = payload.metric(SparkplugProfile.bdSeqMetric)?.value;
        return [
          'BIRTH',
          _who,
          metrics,
          if (bdSeq != null) 'bdSeq $bdSeq',
          if (payload.seq != null) 'seq ${payload.seq}',
        ].join(' | ');
      case SpbMessageType.dBirth:
        return ['BIRTH', _who, metrics, if (payload.seq != null) 'seq ${payload.seq}'].join(' | ');
      case SpbMessageType.nDeath:
        level = InterpretationLevel.warning;
        var bdSeq = payload.metric(SparkplugProfile.bdSeqMetric)?.value;
        return ['DEATH', _who, if (bdSeq != null) 'bdSeq $bdSeq'].join(' | ');
      case SpbMessageType.dDeath:
        level = InterpretationLevel.warning;
        return ['DEATH', _who, if (payload.seq != null) 'seq ${payload.seq}'].join(' | ');
      case SpbMessageType.nCmd || SpbMessageType.dCmd:
        return ['COMMAND to ${device ?? edgeNode}', _list()].join(' | ');
      default:
        return [device ?? edgeNode, _list(), if (payload.seq != null) 'seq ${payload.seq}'].join(' | ');
    }
  }

  // the first metrics as name = value
  String _list() {
    if (payload.metrics.isEmpty) {
      return 'no metrics';
    }
    var shown = payload.metrics
        .take(3)
        .map((metric) {
          var unit = unitOf(metric);
          return '${nameOf(metric)} = ${SparkplugProfile.formatValue(metric)}${unit == null ? '' : ' $unit'}';
        })
        .join(', ');
    return payload.metrics.length > 3 ? '$shown, … (+${payload.metrics.length - 3})' : shown;
  }
}
