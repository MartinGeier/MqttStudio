import 'dart:typed_data';
import 'package:mqttstudio/protocol/protocol_profile.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_profile.dart';

// The rules of Sparkplug B that one stream of messages shows (doc/sparkplug-design.md §6): sequence numbers, the
// birth/death session of edge nodes and devices, and metrics that the birth doesn't define. A check that starts while
// a node is online has missed its birth, so the session rules wait for the next birth.
class SparkplugRules {
  static const String payload = 'sparkplug.payload';
  static const String seqMissing = 'sparkplug.seqMissing';
  static const String seqGap = 'sparkplug.seqGap';
  static const String timestampMissing = 'sparkplug.timestampMissing';
  static const String bdSeqMissing = 'sparkplug.bdSeqMissing';
  static const String bdSeqMismatch = 'sparkplug.bdSeqMismatch';
  static const String afterDeath = 'sparkplug.afterDeath';
  static const String deviceNotBorn = 'sparkplug.deviceNotBorn';
  static const String datatypeMissing = 'sparkplug.datatypeMissing';
  static const String duplicateAlias = 'sparkplug.duplicateAlias';
  static const String unknownMetric = 'sparkplug.unknownMetric';
  static const String datatypeMismatch = 'sparkplug.datatypeMismatch';
}

class _Session {
  // null until the check sees a birth
  Map<String, SpbMetric>? byName;
  Map<int, SpbMetric>? byAlias;

  void define(SpbPayload birth) {
    byName = {
      for (var metric in birth.metrics)
        if (metric.name != null) metric.name!: metric,
    };
    byAlias = SparkplugProfile.aliasesOf(birth);
  }

  bool get known => byName != null;

  SpbMetric? find(SpbMetric metric) => metric.name != null ? byName![metric.name] : byAlias![metric.alias];
}

class _EdgeNode {
  int? lastSeq;
  int? bdSeq;
  // null: unknown, the check started while the node was online
  bool? online;
  final _Session session = _Session();
  final Map<String, _Session> devices = {};
  // devices whose death the check saw, until their next birth
  final Set<String> deadDevices = {};
}

class SparkplugChecker extends ProtocolChecker {
  final SparkplugProfile profile;
  final Map<String, _EdgeNode> _nodes = {};

  SparkplugChecker(this.profile);

  @override
  List<ProtocolFinding> check(
    String topic,
    ProtocolTopic match,
    Object? data,
    DateTime receivedAt, {
    bool snapshot = false,
  }) {
    if (match.messageType == SpbMessageType.state) {
      return const [];
    }
    if (data is! Uint8List) {
      return [
        ProtocolFinding(SparkplugRules.payload, ProtocolSeverity.error, 'The payload is JSON or text, not Protobuf'),
      ];
    }
    var payload = SparkplugProfile.payloadOf(data);
    if (payload == null) {
      return [
        ProtocolFinding(SparkplugRules.payload, ProtocolSeverity.error, 'The payload is not a Sparkplug B payload'),
      ];
    }
    var type = match.messageType;
    var nodeKey = '${match.parameters[SparkplugProfile.groupKey]}/${match.parameters[SparkplugProfile.edgeNodeKey]}';
    var node = _nodes.putIfAbsent(nodeKey, _EdgeNode.new);
    var device = match.parameters[SparkplugProfile.deviceKey];
    var findings = <ProtocolFinding>[];
    void add(String rule, ProtocolSeverity severity, String detail, {String key = ''}) =>
        findings.add(ProtocolFinding(rule, severity, detail, key: key));

    if (type != SpbMessageType.nDeath && !SpbMessageType.isCommand(type) && payload.timestamp == null) {
      add(SparkplugRules.timestampMissing, ProtocolSeverity.warning, '$type without a payload timestamp');
    }
    _checkSeq(type, payload, node, add);

    switch (type) {
      case SpbMessageType.nBirth:
        var bdSeq = payload.metric(SparkplugProfile.bdSeqMetric);
        if (bdSeq == null) {
          add(SparkplugRules.bdSeqMissing, ProtocolSeverity.error, 'NBIRTH without the bdSeq metric');
        }
        node
          ..bdSeq = _int(bdSeq?.value)
          ..online = true
          ..devices.clear()
          ..deadDevices.clear();
        _checkBirth(payload, add);
        node.session.define(payload);
      case SpbMessageType.nDeath:
        var bdSeq = _int(payload.metric(SparkplugProfile.bdSeqMetric)?.value);
        if (bdSeq == null) {
          add(SparkplugRules.bdSeqMissing, ProtocolSeverity.error, 'NDEATH without the bdSeq metric');
        } else if (node.bdSeq != null && node.online == true && bdSeq != node.bdSeq) {
          add(
            SparkplugRules.bdSeqMismatch,
            ProtocolSeverity.warning,
            'NDEATH has bdSeq $bdSeq, the NBIRTH had ${node.bdSeq}; it belongs to another session',
          );
        }
        node
          ..online = false
          ..lastSeq = null;
      case SpbMessageType.dBirth:
        _checkAlive(type, node, add);
        _checkBirth(payload, add);
        node.devices.putIfAbsent(device!, _Session.new).define(payload);
        node.deadDevices.remove(device);
      case SpbMessageType.dDeath:
        _checkAlive(type, node, add);
        node.deadDevices.add(device!);
        node.devices.remove(device);
      case SpbMessageType.nData:
        _checkAlive(type, node, add);
        _checkMetrics(type, payload, node.session, add);
      case SpbMessageType.dData:
        _checkAlive(type, node, add);
        var session = node.devices[device];
        if (node.deadDevices.contains(device) || (session == null && node.online == true)) {
          add(
            SparkplugRules.deviceNotBorn,
            ProtocolSeverity.error,
            'DDATA from device $device before its DBIRTH${node.deadDevices.contains(device) ? ' (after its DDEATH)' : ''}',
          );
        }
        if (session != null) {
          _checkMetrics(type, payload, session, add);
        }
    }
    return findings;
  }

  static int? _int(Object? value) => value is int ? value : (value is BigInt ? value.toInt() : null);

  // NBIRTH starts the count at any value, every following message of the node adds one, after 255 comes 0
  void _checkSeq(
    String type,
    SpbPayload payload,
    _EdgeNode node,
    void Function(String, ProtocolSeverity, String, {String key}) add,
  ) {
    if (type == SpbMessageType.nDeath || SpbMessageType.isCommand(type)) {
      return;
    }
    var seq = payload.seq;
    if (seq == null) {
      add(SparkplugRules.seqMissing, ProtocolSeverity.error, '$type without a sequence number');
      return;
    }
    var last = node.lastSeq;
    if (type != SpbMessageType.nBirth && last != null && seq != (last + 1) % 256) {
      add(
        SparkplugRules.seqGap,
        ProtocolSeverity.warning,
        'Sequence number $seq after ${node.lastSeq}, expected ${(last + 1) % 256}: messages were lost or reordered',
      );
    }
    node.lastSeq = seq % 256;
  }

  void _checkAlive(String type, _EdgeNode node, void Function(String, ProtocolSeverity, String, {String key}) add) {
    if (node.online == false) {
      add(
        SparkplugRules.afterDeath,
        ProtocolSeverity.error,
        '$type while the edge node is dead (after NDEATH, before NBIRTH)',
      );
    }
  }

  void _checkBirth(SpbPayload birth, void Function(String, ProtocolSeverity, String, {String key}) add) {
    var aliases = <int>{};
    for (var metric in birth.metrics) {
      var name = metric.name ?? 'alias ${metric.alias}';
      if (metric.datatype == null) {
        add(
          SparkplugRules.datatypeMissing,
          ProtocolSeverity.error,
          'Metric $name has no data type in the birth',
          key: name,
        );
      }
      if (metric.alias != null && !aliases.add(metric.alias!)) {
        add(
          SparkplugRules.duplicateAlias,
          ProtocolSeverity.error,
          'Alias ${metric.alias} is used twice ($name)',
          key: '${metric.alias}',
        );
      }
    }
  }

  // data must use metrics the birth defined, with their data types
  void _checkMetrics(
    String type,
    SpbPayload payload,
    _Session session,
    void Function(String, ProtocolSeverity, String, {String key}) add,
  ) {
    if (!session.known) {
      return;
    }
    for (var metric in payload.metrics) {
      var name = metric.name ?? 'alias ${metric.alias}';
      var defined = session.find(metric);
      if (defined == null) {
        add(
          SparkplugRules.unknownMetric,
          ProtocolSeverity.error,
          '$type has metric $name that the birth does not define',
          key: name,
        );
      } else if (metric.datatype != null && defined.datatype != null && metric.datatype != defined.datatype) {
        add(
          SparkplugRules.datatypeMismatch,
          ProtocolSeverity.error,
          'Metric ${defined.name ?? name} is ${metric.type?.label ?? metric.datatype}, the birth says ${defined.type?.label ?? defined.datatype}',
          key: name,
        );
      }
    }
  }
}
