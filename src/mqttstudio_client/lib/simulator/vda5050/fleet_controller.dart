import 'dart:math';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/simulator/vda5050/fleet_layout.dart';
import 'package:mqttstudio/simulator/vda5050/simulated_fleet.dart';
import 'package:mqttstudio/simulator/vda5050/simulated_robot.dart';

// The route of a robot's current order. Node i of the path has the sequence id 2i, the edge after it 2i + 1.
class _Plan {
  final String orderId;
  List<String> path;
  final String target;
  final bool toCharger;
  // index of the last released node
  int baseEnd;
  int updateId = 0;
  // the actions of the nodes, by path index
  final Map<int, List<VdaAction>> actions;
  DateTime? waitingSince;

  _Plan(this.orderId, this.path, this.target, this.toCharger, this.baseEnd, this.actions);
}

class _PendingResponse {
  final SimulatedRobot robot;
  final String requestId;
  final String zoneId;
  DateTime dueAt;
  bool queueFirst;
  bool queuedSent = false;

  _PendingResponse(this.robot, this.requestId, this.zoneId, this.dueAt, this.queueFirst);
}

// The simulation's fleet control (doc/vda5050-design.md §10.3): sends idle robots an order to a random node, or to a
// charging station when their battery is low, releases the route a few nodes at a time with order updates, keeps
// two robots off the same nodes and, for 3.0, answers zone requests.
class FleetController {
  static const int firstBase = 3;
  static const int baseStep = 2;
  static const double chargeBelow = 20;
  static const Duration replanAfter = Duration(seconds: 10);
  static const Duration retryAfter = Duration(seconds: 2);
  static const Duration unansweredFor = Duration(seconds: 15);

  final SimulatedFleet fleet;
  final Random _random;
  final Map<SimulatedRobot, _Plan> _plans = {};
  final Map<SimulatedRobot, DateTime> _idleUntil = {};
  final Map<String, _PendingResponse> _pending = {};
  int _orderCounter = 0;
  int _actionCounter = 0;

  FleetController(this.fleet, this._random);

  FleetLayout get _layout => fleet.layout;

  void tick(DateTime now) {
    for (var robot in fleet.robots) {
      if (!robot.isOnline) {
        continue;
      }
      var plan = _plans[robot];
      if (robot.isIdle) {
        _plans.remove(robot);
        var until = _idleUntil.putIfAbsent(robot, () => now.add(_idleTime()));
        if (now.isBefore(until)) {
          continue;
        }
        _idleUntil.remove(robot);
        if (!_newOrder(robot, now)) {
          _idleUntil[robot] = now.add(retryAfter);
        }
      } else if (plan != null) {
        _extendBase(robot, plan, now);
      }
    }
    _answerRequests(now);
  }

  // the robot's order was cancelled; it gets a new one once it is idle
  void forget(SimulatedRobot robot) => _plans.remove(robot);

  Duration _idleTime() {
    var source = fleet.source;
    var seconds = source.minIdleSec + _random.nextDouble() * max(0, source.maxIdleSec - source.minIdleSec);
    return Duration(milliseconds: (seconds * 1000).round());
  }

  Set<String> _reservedByOthers(SimulatedRobot robot) => {
        for (var other in fleet.robots)
          if (other != robot) ...other.reservedNodes,
      };

  bool _newOrder(SimulatedRobot robot, DateTime now) {
    var blocked = _reservedByOthers(robot);
    var toCharger = robot.stateOfCharge < chargeBelow && !robot.charging;
    var path = toCharger ? _routeToCharger(robot, blocked) : null;
    if (path == null) {
      toCharger = false;
      path = _routeToRandomNode(robot.lastNodeId, blocked);
    }
    if (path == null) {
      return false;
    }
    var plan = _Plan('${robot.serialNumber}-o${++_orderCounter}', path, path.last, toCharger,
        min(firstBase - 1, path.length - 1), {});
    _addActions(plan, 1, robot.loads.isNotEmpty);
    _plans[robot] = plan;
    fleet.sendOrder(robot, _buildOrder(plan, 0), now);
    return true;
  }

  List<String>? _routeToCharger(SimulatedRobot robot, Set<String> blocked) {
    List<String>? best;
    for (var node in _layout.nodes.values.where((node) => node.charging && !blocked.contains(node.id))) {
      var path = _layout.route(robot.lastNodeId, node.id, blocked: blocked);
      if (path != null && path.length > 1 && (best == null || path.length < best.length)) {
        best = path;
      }
    }
    return best;
  }

  // a route of the configured length to a node that isn't a charging station, else any route that can be found
  List<String>? _routeToRandomNode(String from, Set<String> blocked) {
    var source = fleet.source;
    var targets = _layout.nodes.values
        .where((node) => !node.charging && node.id != from && !blocked.contains(node.id))
        .map((node) => node.id)
        .toList()
      ..shuffle(_random);
    List<String>? fallback;
    for (var target in targets.take(30)) {
      var path = _layout.route(from, target, blocked: blocked);
      if (path == null) {
        continue;
      }
      if (path.length >= source.minOrderNodes && path.length <= source.maxOrderNodes) {
        return path;
      }
      fallback ??= path;
    }
    return fallback;
  }

  // random pick and drop actions from the path index on; a charging trip ends with startCharging
  void _addActions(_Plan plan, int fromIndex, bool loaded) {
    var source = fleet.source;
    for (var i = fromIndex; i < plan.path.length; i++) {
      plan.actions.remove(i);
      var last = i == plan.path.length - 1;
      if (plan.toCharger && last) {
        plan.actions[i] = [VdaAction(actionId: _nextActionId(), actionType: 'startCharging', blockingType: VdaBlockingType.hard)];
      } else if (!plan.toCharger && _random.nextDouble() < source.actionProbability) {
        plan.actions[i] = [
          VdaAction(
            actionId: _nextActionId(),
            actionType: loaded ? 'drop' : 'pick',
            blockingType: VdaBlockingType.hard,
            parameters: [VdaActionParameter('loadType', 'EPAL')],
          )
        ];
        loaded = !loaded;
      }
    }
  }

  String _nextActionId() => 'a${++_actionCounter}';

  // the order or update from the path index on: the base up to baseEnd, then the horizon. The stitching node of an
  // update carries no actions, they were sent with the update before.
  VdaOrder _buildOrder(_Plan plan, int fromIndex) {
    var last = min(plan.path.length - 1, plan.baseEnd + fleet.source.horizonNodes);
    var nodes = <VdaNode>[];
    var edges = <VdaEdge>[];
    for (var i = fromIndex; i <= last; i++) {
      var node = _layout[plan.path[i]];
      nodes.add(VdaNode(
        nodeId: node.id,
        sequenceId: 2 * i,
        released: i <= plan.baseEnd,
        position: VdaNodePosition(x: node.x, y: node.y, mapId: fleet.source.mapId),
        actions: i == fromIndex && fromIndex > 0 ? [] : [...?plan.actions[i]],
      ));
      if (i < last) {
        edges.add(VdaEdge(
          edgeId: '${plan.path[i]}_${plan.path[i + 1]}',
          sequenceId: 2 * i + 1,
          released: i + 1 <= plan.baseEnd,
          startNodeId: plan.path[i],
          endNodeId: plan.path[i + 1],
        ));
      }
    }
    return VdaOrder(orderId: plan.orderId, orderUpdateId: plan.updateId, nodes: nodes, edges: edges);
  }

  // releases the next nodes once the robot is one node before the end of its base
  void _extendBase(SimulatedRobot robot, _Plan plan, DateTime now) {
    if (plan.baseEnd >= plan.path.length - 1 || robot.lastNodeSequenceId ~/ 2 < plan.baseEnd - 1) {
      return;
    }
    var newBaseEnd = min(plan.baseEnd + baseStep, plan.path.length - 1);
    var blocked = _reservedByOthers(robot);
    if (plan.path.sublist(plan.baseEnd + 1, newBaseEnd + 1).any(blocked.contains)) {
      plan.waitingSince ??= now;
      if (now.difference(plan.waitingSince!) >= replanAfter) {
        _replan(robot, plan, blocked, now);
      }
      return;
    }
    plan.waitingSince = null;
    var stitch = plan.baseEnd;
    plan
      ..baseEnd = newBaseEnd
      ..updateId += 1;
    fleet.sendOrder(robot, _buildOrder(plan, stitch), now);
  }

  // another robot stands in the way: drive around it, or somewhere else
  void _replan(SimulatedRobot robot, _Plan plan, Set<String> blocked, DateTime now) {
    var from = plan.path[plan.baseEnd];
    var rest = _layout.route(from, plan.target, blocked: blocked) ?? (plan.toCharger ? null : _routeToRandomNode(from, blocked));
    plan.waitingSince = now;
    if (rest == null || rest.length < 2) {
      return;
    }
    plan.path = [...plan.path.sublist(0, plan.baseEnd + 1), ...rest.skip(1)];
    plan.actions.removeWhere((index, _) => index > plan.baseEnd);
    _addActions(plan, plan.baseEnd + 1, robot.loads.isNotEmpty);
  }

  // ---------- zone requests (3.0) ----------

  void _answerRequests(DateTime now) {
    for (var robot in fleet.robots) {
      for (var request in robot.zoneRequests) {
        if (request.requestStatus != VdaRequestStatus.requested || _pending.containsKey(request.requestId)) {
          continue;
        }
        var delay = fleet.takeUnansweredRequest(robot)
            ? unansweredFor
            : Duration(milliseconds: 500 + _random.nextInt(1500));
        _pending[request.requestId] =
            _PendingResponse(robot, request.requestId, request.zoneId, now.add(delay), _random.nextDouble() < 0.25);
      }
    }
    for (var pending in _pending.values.toList()) {
      var stillAsked = pending.robot.zoneRequests
          .any((request) => request.requestId == pending.requestId && request.requestStatus == VdaRequestStatus.requested);
      if (!stillAsked) {
        _pending.remove(pending.requestId);
        continue;
      }
      if (now.isBefore(pending.dueAt) || !pending.robot.isOnline) {
        continue;
      }
      var occupied = fleet.robots.any((other) =>
          other != pending.robot &&
          other.zoneRequests
              .any((request) => request.zoneId == pending.zoneId && request.requestStatus == VdaRequestStatus.granted));
      if (occupied || pending.queueFirst) {
        if (!pending.queuedSent) {
          fleet.sendResponse(pending.robot, pending.requestId, VdaGrantType.queued, now);
          pending.queuedSent = true;
        }
        pending
          ..queueFirst = false
          ..dueAt = now.add(Duration(milliseconds: 1000 + _random.nextInt(2000)));
        continue;
      }
      _pending.remove(pending.requestId);
      fleet.sendResponse(pending.robot, pending.requestId, VdaGrantType.granted, now);
    }
  }
}
