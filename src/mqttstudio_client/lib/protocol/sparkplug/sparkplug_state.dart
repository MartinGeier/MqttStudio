import 'package:mqttstudio/protocol/protocol_profile.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_profile.dart';

// online after a birth, offline after a death, unknown when only data was seen and the birth was missed
enum SparkplugStatus { online, offline, unknown }

// One metric of an edge node or device with its current value (doc/sparkplug-design.md §13.3). M is the message it
// last came in, so the view can select it.
class SparkplugMetricState<M> {
  final String name;
  int? alias;
  SpbDataType? type;
  String? unit;
  Object? value;
  bool isNull = false;
  // the properties of the birth as text, the unit left out
  Map<String, String> properties = const {};
  // the metric's own timestamp, else the payload's, milliseconds UTC
  int? timestamp;
  DateTime? receivedAt;
  M? message;
  // how often data changed the value
  int changes = 0;
  // sent by alias, but the birth that names it wasn't received
  final bool unknown;

  SparkplugMetricState(this.name, {this.alias, this.unknown = false});

  String get formattedValue => isNull ? 'null' : SparkplugProfile.formatData(value);
}

// An edge node (device null) or one of its devices
class SparkplugEntryState<M> {
  final String group;
  final String edgeNode;
  final String? device;
  SparkplugStatus status = SparkplugStatus.unknown;
  // since when it has its status
  DateTime? since;
  DateTime? lastAt;
  M? lastMessage;
  int messages = 0;
  final Map<String, SparkplugMetricState<M>> metrics = {};
  final Map<int, SparkplugMetricState<M>> _byAlias = {};

  SparkplugEntryState(this.group, this.edgeNode, [this.device]);

  // 'Plant1/Edge1' or 'Plant1/Edge1/Pump'
  String get key => device == null ? '$group/$edgeNode' : '$group/$edgeNode/$device';

  String get name => device ?? edgeNode;

  void _setStatus(SparkplugStatus status, DateTime at) {
    if (this.status != status || since == null) {
      this.status = status;
      since = at;
    }
  }

  SparkplugMetricState<M>? _find(SpbMetric metric) =>
      metric.name != null ? metrics[metric.name] : _byAlias[metric.alias];

  // a birth defines the metrics anew (V5)
  void _define(SpbPayload birth, DateTime at, M message) {
    metrics.clear();
    _byAlias.clear();
    for (var metric in birth.metrics) {
      var name = metric.name ?? 'alias ${metric.alias}';
      var state = SparkplugMetricState<M>(name, alias: metric.alias)
        ..type = metric.type
        ..unit = SparkplugProfile.unitOf(metric)
        ..properties = _properties(metric);
      _set(state, metric, birth, at, message, counting: false);
      metrics[name] = state;
      if (metric.alias != null) {
        _byAlias[metric.alias!] = state;
      }
    }
  }

  void _update(SpbPayload data, DateTime at, M message) {
    for (var metric in data.metrics) {
      var state = _find(metric);
      if (state == null) {
        // data the birth doesn't name: by alias it stays unknown until the next birth
        var name = metric.name ?? 'alias ${metric.alias}';
        state = metrics[name] = SparkplugMetricState<M>(name, alias: metric.alias, unknown: metric.name == null)
          ..type = metric.type;
        if (metric.alias != null) {
          _byAlias[metric.alias!] = state;
        }
      } else if (metric.datatype == null && state.type != null) {
        SparkplugReader.retype(metric, state.type!);
      }
      _set(state, metric, data, at, message, counting: true);
    }
  }

  static void _set(
    SparkplugMetricState state,
    SpbMetric metric,
    SpbPayload payload,
    DateTime at,
    Object? message, {
    required bool counting,
  }) {
    var before = state.formattedValue;
    state
      ..value = metric.value
      ..isNull = metric.isNull
      ..timestamp = metric.timestamp ?? payload.timestamp
      ..receivedAt = at
      ..message = message;
    if (counting && state.formattedValue != before) {
      state.changes++;
    }
  }

  static Map<String, String> _properties(SpbMetric metric) {
    var unit = SparkplugProfile.unitOf(metric);
    return {
      for (var entry in metric.properties?.values.entries ?? const <MapEntry<String, SpbPropertyValue>>[])
        if (unit == null || entry.value.value != unit)
          entry.key: entry.value.isNull ? 'null' : SparkplugProfile.formatData(entry.value.value),
    };
  }
}

class SparkplugNodeState<M> extends SparkplugEntryState<M> {
  int? bdSeq;
  int? lastSeq;
  // messages whose seq wasn't the previous one + 1
  int seqGaps = 0;
  final Map<String, SparkplugEntryState<M>> devices = {};

  SparkplugNodeState(String group, String edgeNode) : super(group, edgeNode);

  void _checkSeq(int? seq, {bool birth = false}) {
    if (seq == null) {
      return;
    }
    if (!birth && lastSeq != null && seq != (lastSeq! + 1) % 256) {
      seqGaps++;
    }
    lastSeq = seq % 256;
  }
}

class SparkplugHostState {
  final String hostId;
  bool online;
  int? timestamp;
  DateTime receivedAt;

  SparkplugHostState(this.hostId, this.online, this.timestamp, this.receivedAt);
}

// Folds Sparkplug messages into host applications, edge nodes, devices and their metrics with current values
// (doc/sparkplug-design.md §13.3), like FleetState for VDA 5050. It only reads; payloads that can't be read are skipped.
class SparkplugState<M> {
  final Map<String, SparkplugHostState> _hosts = {};
  final Map<String, SparkplugNodeState<M>> _nodes = {};

  List<SparkplugHostState> get hosts => _hosts.values.toList()..sort((a, b) => a.hostId.compareTo(b.hostId));

  // by group and edge node
  List<SparkplugNodeState<M>> get nodes => _nodes.values.toList()..sort((a, b) => a.key.compareTo(b.key));

  List<String> get groups => {for (var node in _nodes.values) node.group}.toList()..sort();

  bool get isEmpty => _nodes.isEmpty && _hosts.isEmpty;

  SparkplugNodeState<M>? node(String group, String edgeNode) => _nodes['$group/$edgeNode'];

  // an edge node or device by its key, 'Plant1/Edge1' or 'Plant1/Edge1/Pump'
  SparkplugEntryState<M>? entry(String key) {
    var node = _nodes[key];
    if (node != null) {
      return node;
    }
    var slash = key.lastIndexOf('/');
    return slash < 0 ? null : _nodes[key.substring(0, slash)]?.devices[key.substring(slash + 1)];
  }

  void clear() {
    _hosts.clear();
    _nodes.clear();
  }

  // returns false when the message changes nothing
  bool add(ProtocolTopic match, Object? data, DateTime receivedAt, M message) {
    if (match.profile is! SparkplugProfile) {
      return false;
    }
    if (match.messageType == SpbMessageType.state) {
      return _addState(match, data, receivedAt);
    }
    var payload = SparkplugProfile.payloadOf(data);
    if (payload == null) {
      return false;
    }
    var group = match.parameters[SparkplugProfile.groupKey]!;
    var edgeNode = match.parameters[SparkplugProfile.edgeNodeKey]!;
    var node = _nodes.putIfAbsent('$group/$edgeNode', () => SparkplugNodeState<M>(group, edgeNode));
    var deviceId = match.parameters[SparkplugProfile.deviceKey];
    SparkplugEntryState<M> entry = deviceId == null
        ? node
        : node.devices.putIfAbsent(deviceId, () => SparkplugEntryState<M>(group, edgeNode, deviceId));
    entry
      ..lastAt = receivedAt
      ..lastMessage = message
      ..messages += 1;
    switch (match.messageType) {
      case SpbMessageType.nBirth:
        var bdSeq = payload.metric(SparkplugProfile.bdSeqMetric)?.value;
        node
          ..bdSeq = bdSeq is int ? bdSeq : null
          .._checkSeq(payload.seq, birth: true)
          .._setStatus(SparkplugStatus.online, receivedAt)
          .._define(payload, receivedAt, message);
      case SpbMessageType.nDeath:
        node
          ..lastSeq = null
          .._setStatus(SparkplugStatus.offline, receivedAt);
        for (var device in node.devices.values) {
          device._setStatus(SparkplugStatus.offline, receivedAt);
        }
      case SpbMessageType.nData:
        node
          .._checkSeq(payload.seq)
          .._update(payload, receivedAt, message);
        if (node.since == null) {
          node._setStatus(SparkplugStatus.unknown, receivedAt);
        }
      case SpbMessageType.dBirth:
        node._checkSeq(payload.seq);
        entry
          .._setStatus(SparkplugStatus.online, receivedAt)
          .._define(payload, receivedAt, message);
      case SpbMessageType.dDeath:
        node._checkSeq(payload.seq);
        entry._setStatus(SparkplugStatus.offline, receivedAt);
      case SpbMessageType.dData:
        node._checkSeq(payload.seq);
        entry._update(payload, receivedAt, message);
        if (entry.since == null) {
          entry._setStatus(SparkplugStatus.unknown, receivedAt);
        }
      default:
        // commands go to the edge node, they say nothing about its state
        entry.messages--;
        return false;
    }
    return true;
  }

  bool _addState(ProtocolTopic match, Object? data, DateTime receivedAt) {
    var interpretation = match.profile.interpret(match, data);
    if (interpretation == null) {
      return false;
    }
    var hostId = match.parameters[SparkplugProfile.hostKey]!;
    var online = interpretation.summary.endsWith('ONLINE');
    var timestamp = data is Map && data['timestamp'] is num ? (data['timestamp'] as num).toInt() : null;
    _hosts[hostId] = SparkplugHostState(hostId, online, timestamp, receivedAt);
    return true;
  }
}
