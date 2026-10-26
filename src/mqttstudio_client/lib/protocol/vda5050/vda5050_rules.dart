import 'dart:convert';
import 'package:mqttstudio/protocol/protocol_profile.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_profile.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_reader.dart';

// the ids of the VDA 5050 protocol rules (doc/vda5050-design.md §9.3)
class Vda5050Rule {
  static const String headerDiffers = 'vda5050.headerDiffers';
  static const String headerIdOutOfOrder = 'vda5050.headerIdOutOfOrder';
  static const String headerIdGap = 'vda5050.headerIdGap';
  static const String timestampSkew = 'vda5050.timestampSkew';
  static const String orderStructure = 'vda5050.orderStructure';
  static const String orderUpdate = 'vda5050.orderUpdate';
  static const String orderUpdateContent = 'vda5050.orderUpdateContent';
  static const String duplicateActionId = 'vda5050.duplicateActionId';
  static const String responseWithoutRequest = 'vda5050.responseWithoutRequest';
  static const String unansweredRequest = 'vda5050.unansweredRequest';
  static const String visualizationAheadOfState = 'vda5050.visualizationAheadOfState';
  static const String heartbeatMissing = 'vda5050.heartbeatMissing';

  static const List<String> all = [
    headerDiffers, headerIdOutOfOrder, headerIdGap, timestampSkew, orderStructure, orderUpdate, orderUpdateContent, //
    duplicateActionId, responseWithoutRequest, unansweredRequest, visualizationAheadOfState, heartbeatMissing,
  ];
}

class _OrderSeen {
  final int updateId;
  final String? lastBaseNodeId;
  final int? lastBaseSequenceId;
  // the order as sent, to see whether a repeated update id has another content
  final String content;

  _OrderSeen(this.updateId, this.lastBaseNodeId, this.lastBaseSequenceId, this.content);
}

// what the checker knows about one robot
class _Device {
  // the robot's state topic, for findings that come from a tick
  String? stateTopic;
  int? lastStateHeaderId;
  // the order the robot reported last, to tell a new order from one that began before the check
  String? lastStateOrderId;
  DateTime? lastStateAt;
  // the last connection state, null before the first connection message
  String? connectionState;
  // the silence since lastStateAt is reported already
  bool reportedSilence = false;
  final Map<String, _OrderSeen> orders = {};
  String? currentOrderId;
  final Set<String> cancelledOrders = {};
  // requests the robot made, with when they were first seen
  final Map<String, DateTime> requests = {};
  final Set<String> answered = {};
  final Set<String> reportedUnanswered = {};
}

// Checks the VDA 5050 protocol over one check run (doc/vda5050-design.md §9.3): header against topic, header ids,
// timestamps, the structure and updates of orders, duplicate action ids and, for 3.0, requests and responses and the
// visualization's reference to a state.
class Vda5050Checker extends ProtocolChecker {
  static const Duration maxSkew = Duration(seconds: 5);
  static const Duration answerWithin = Duration(seconds: 10);
  // state comes at least every 30 s; a little more before it counts as missing
  static const Duration heartbeat = Duration(seconds: 35);

  final Vda5050Profile profile;
  final Map<String, int> _lastHeaderIds = {};
  final Map<String, _Device> _devices = {};

  Vda5050Checker(this.profile);

  @override
  List<ProtocolFinding> check(String topic, ProtocolTopic match, Object? data, DateTime receivedAt,
      {bool snapshot = false}) {
    if (!Vda5050Profile.hasHeader(data)) {
      return const [];
    }
    var json = (data as Map).map((key, value) => MapEntry('$key', value));
    var findings = <ProtocolFinding>[];
    var version = Vda5050Profile.versionOf(match, json);
    var message = Vda5050Reader.read(match.messageType, json);
    if (message == null) {
      return const [];
    }
    var device = _devices.putIfAbsent(match.deviceKey, () => _Device());
    _header(topic, match, message.header, receivedAt, findings, snapshot: snapshot);
    switch (message) {
      case VdaOrder order:
        _order(device, order, version, json, findings);
      case VdaInstantActions instant:
        if (instant.actions.any((action) => action.actionType == 'cancelOrder') && device.currentOrderId != null) {
          device.cancelledOrders.add(device.currentOrderId!);
        }
      case VdaConnection connection:
        device.connectionState = connection.connectionState;
      case VdaState state:
        device
          ..stateTopic = topic
          ..lastStateHeaderId = state.header.headerId
          ..lastStateOrderId = state.orderId
          ..lastStateAt = receivedAt
          ..reportedSilence = false;
        for (var id in [
          ...state.zoneRequests.map((request) => request.requestId),
          ...state.edgeRequests.map((request) => request.requestId),
        ]) {
          device.requests.putIfAbsent(id, () => receivedAt);
        }
      case VdaResponses responses:
        for (var response in responses.responses) {
          device.answered.add(response.requestId);
          if (!device.requests.containsKey(response.requestId)) {
            findings.add(ProtocolFinding(Vda5050Rule.responseWithoutRequest, ProtocolSeverity.warning,
                'Response to ${response.requestId}, which the robot never requested',
                key: response.requestId));
          }
        }
      case VdaVisualization visualization:
        var reference = visualization.referenceStateHeaderId;
        var lastState = device.lastStateHeaderId;
        if (version.isV3 && reference != null && lastState != null && reference > lastState) {
          findings.add(ProtocolFinding(Vda5050Rule.visualizationAheadOfState, ProtocolSeverity.warning,
              'Refers to state $reference, the last state was $lastState'));
        }
      default:
        break;
    }
    return findings;
  }

  @override
  List<(String, ProtocolFinding)> tick(DateTime now) {
    var findings = <(String, ProtocolFinding)>[];
    for (var device in _devices.values) {
      _silence(device, now, findings);
      for (var entry in device.requests.entries) {
        var id = entry.key;
        if (device.answered.contains(id) ||
            device.reportedUnanswered.contains(id) ||
            now.difference(entry.value) < answerWithin ||
            device.stateTopic == null) {
          continue;
        }
        device.reportedUnanswered.add(id);
        findings.add((
          device.stateTopic!,
          ProtocolFinding(Vda5050Rule.unansweredRequest, ProtocolSeverity.warning,
              'Request $id has no response after ${answerWithin.inSeconds} s',
              key: id)
        ));
      }
    }
    return findings;
  }

  // a robot that is ONLINE must send state at least every 30 s; offline, broken or hibernating it may be silent
  void _silence(_Device device, DateTime now, List<(String, ProtocolFinding)> findings) {
    var last = device.lastStateAt;
    var connected =
        device.connectionState == null || device.connectionState == VdaConnectionState.online;
    if (last == null || device.reportedSilence || !connected || now.difference(last) <= heartbeat) {
      return;
    }
    device.reportedSilence = true;
    findings.add((
      device.stateTopic!,
      ProtocolFinding(Vda5050Rule.heartbeatMissing, ProtocolSeverity.error,
          'No state for more than ${heartbeat.inSeconds} s while the robot is ${device.connectionState ?? 'connected'}')
    ));
  }

  void _header(String topic, ProtocolTopic match, VdaHeader header, DateTime receivedAt, List<ProtocolFinding> findings,
      {required bool snapshot}) {
    var differences = [
      if (header.manufacturer != match.parameters[Vda5050Profile.manufacturerKey])
        'manufacturer ${header.manufacturer}',
      if (header.serialNumber != match.parameters[Vda5050Profile.serialNumberKey])
        'serial number ${header.serialNumber}',
      if (_major(header.version) != null &&
          _major(header.version) != int.tryParse(match.parameters[Vda5050Profile.majorVersionKey]!.substring(1)))
        'version ${header.version}',
    ];
    if (differences.isNotEmpty) {
      findings.add(ProtocolFinding(Vda5050Rule.headerDiffers, ProtocolSeverity.error,
          'The header says ${differences.join(', ')}, the topic ${match.deviceKey}'));
    }
    var last = _lastHeaderIds[topic];
    var id = header.headerId;
    if (last != null) {
      if (id <= last) {
        findings.add(ProtocolFinding(
            Vda5050Rule.headerIdOutOfOrder, ProtocolSeverity.warning, 'Header id $id after $last (a restart?)'));
      } else if (id > last + 1) {
        var missing = id - last - 1;
        findings.add(ProtocolFinding(Vda5050Rule.headerIdGap, ProtocolSeverity.warning,
            '$missing ${missing == 1 ? 'header id is' : 'header ids are'} missing between $last and $id'));
      }
    }
    _lastHeaderIds[topic] = id;
    // a retained message sent on subscribing is as old as it is, e.g. the connection message
    var skew = header.timestamp.difference(receivedAt);
    if (!snapshot && header.timestamp.millisecondsSinceEpoch > 0 && skew.abs() > maxSkew) {
      findings.add(ProtocolFinding(Vda5050Rule.timestampSkew, ProtocolSeverity.warning,
          'The timestamp is ${(skew.inMilliseconds.abs() / 1000).toStringAsFixed(1)} s '
          '${skew.isNegative ? 'behind' : 'ahead of'} the time it was received'));
    }
  }

  static int? _major(String version) => int.tryParse(version.split('.').first);

  void _order(_Device device, VdaOrder order, VdaVersion version, Map<String, Object?> json, List<ProtocolFinding> findings) {
    _structure(order, version, findings);
    var actionIds = <String>{};
    var duplicates = <String>{};
    for (var action in [
      for (var node in order.nodes) ...node.actions,
      for (var edge in order.edges) ...edge.actions,
    ]) {
      if (!actionIds.add(action.actionId)) {
        duplicates.add(action.actionId);
      }
    }
    if (duplicates.isNotEmpty) {
      findings.add(ProtocolFinding(Vda5050Rule.duplicateActionId, ProtocolSeverity.error,
          'Action ids used twice in order ${order.orderId}: ${duplicates.join(', ')}'));
    }

    var content = jsonEncode([json['nodes'], json['edges']]);
    var released = order.nodes.where((node) => node.released).toList()
      ..sort((a, b) => a.sequenceId.compareTo(b.sequenceId));
    var seen = _OrderSeen(order.orderUpdateId, released.lastOrNull?.nodeId, released.lastOrNull?.sequenceId, content);
    var previous = device.orders[order.orderId];
    if (previous == null) {
      // the first update the check sees may belong to an order that began before; only a robot that reported another
      // order shows that this one is new
      var isNew = device.lastStateOrderId != null && device.lastStateOrderId != order.orderId;
      if (version.isV3 && order.orderUpdateId != 0 && isNew) {
        findings.add(ProtocolFinding(Vda5050Rule.orderUpdateContent, ProtocolSeverity.error,
            'Order ${order.orderId} starts with update id ${order.orderUpdateId} instead of 0'));
      }
    } else if (order.orderUpdateId < previous.updateId) {
      findings.add(ProtocolFinding(Vda5050Rule.orderUpdate, ProtocolSeverity.error,
          'Order ${order.orderId}: update ${order.orderUpdateId} after update ${previous.updateId}'));
      return;
    } else if (order.orderUpdateId == previous.updateId) {
      if (version.isV3 && previous.content != content) {
        findings.add(ProtocolFinding(Vda5050Rule.orderUpdateContent, ProtocolSeverity.error,
            'Order ${order.orderId}: update ${order.orderUpdateId} sent again with another content'));
      }
      return;
    } else {
      var first = ([...order.nodes]..sort((a, b) => a.sequenceId.compareTo(b.sequenceId))).firstOrNull;
      if (first != null &&
          previous.lastBaseNodeId != null &&
          (first.nodeId != previous.lastBaseNodeId || first.sequenceId != previous.lastBaseSequenceId)) {
        findings.add(ProtocolFinding(Vda5050Rule.orderUpdate, ProtocolSeverity.error,
            'Order ${order.orderId}: update ${order.orderUpdateId} starts at ${first.nodeId} (${first.sequenceId}), '
            'the base ended at ${previous.lastBaseNodeId} (${previous.lastBaseSequenceId})'));
      }
      if (version.isV3 && device.cancelledOrders.contains(order.orderId)) {
        findings.add(ProtocolFinding(Vda5050Rule.orderUpdateContent, ProtocolSeverity.error,
            'Order ${order.orderId} is updated after it was cancelled'));
      }
    }
    device.orders[order.orderId] = seen;
    device.currentOrderId = order.orderId;
  }

  // nodes and edges alternate with continuous sequence ids, the base comes before the horizon and, in 2.x, every edge
  // connects the nodes next to it
  void _structure(VdaOrder order, VdaVersion version, List<ProtocolFinding> findings) {
    var problems = <String>[];
    var nodes = [...order.nodes]..sort((a, b) => a.sequenceId.compareTo(b.sequenceId));
    var edges = [...order.edges]..sort((a, b) => a.sequenceId.compareTo(b.sequenceId));
    if (nodes.any((node) => node.sequenceId.isOdd)) {
      problems.add('a node has an odd sequence id');
    }
    if (edges.any((edge) => edge.sequenceId.isEven)) {
      problems.add('an edge has an even sequence id');
    }
    if (nodes.isNotEmpty && edges.length != nodes.length - 1) {
      problems.add('${nodes.length} nodes need ${nodes.length - 1} edges, there are ${edges.length}');
    }
    var sequence = [...nodes.map((node) => node.sequenceId), ...edges.map((edge) => edge.sequenceId)]..sort();
    for (var i = 1; i < sequence.length; i++) {
      if (sequence[i] != sequence[i - 1] + 1) {
        problems.add('the sequence jumps from ${sequence[i - 1]} to ${sequence[i]}');
        break;
      }
    }
    var elements = [
      ...nodes.map((node) => (node.sequenceId, node.released)),
      ...edges.map((edge) => (edge.sequenceId, edge.released)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var horizonStarted = false;
    for (var (sequenceId, released) in elements) {
      if (!released) {
        horizonStarted = true;
      } else if (horizonStarted) {
        problems.add('the released element $sequenceId follows an unreleased one');
        break;
      }
    }
    if (!version.isV3) {
      var bySequence = {for (var node in nodes) node.sequenceId: node.nodeId};
      for (var edge in edges) {
        var start = bySequence[edge.sequenceId - 1];
        var end = bySequence[edge.sequenceId + 1];
        if ((start != null && edge.startNodeId != null && edge.startNodeId != start) ||
            (end != null && edge.endNodeId != null && edge.endNodeId != end)) {
          problems.add('edge ${edge.edgeId} doesn\'t connect $start and $end');
          break;
        }
      }
    }
    if (problems.isNotEmpty) {
      findings.add(ProtocolFinding(Vda5050Rule.orderStructure, ProtocolSeverity.error,
          'Order ${order.orderId}#${order.orderUpdateId}: ${problems.join('; ')}'));
    }
  }
}
