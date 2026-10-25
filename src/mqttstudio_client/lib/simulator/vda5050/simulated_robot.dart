import 'dart:math';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/simulator/model/vda5050_source.dart';
import 'package:mqttstudio/simulator/vda5050/fleet_layout.dart';

class _ActionRun {
  final VdaAction action;
  final int nodeSequenceId;
  String status = VdaActionStatus.waiting;
  String? result;
  DateTime? endsAt;
  // left of a running action while it is paused
  Duration? remaining;

  _ActionRun(this.action, this.nodeSequenceId);

  bool get isActive =>
      status == VdaActionStatus.initializing || status == VdaActionStatus.running || status == VdaActionStatus.paused;

  bool get isOpen => status != VdaActionStatus.finished && status != VdaActionStatus.failed;
}

// One simulated VDA 5050 robot: it drives the released part of its order node by node, runs the actions at the
// nodes, uses and charges its battery and answers instant actions (doc/vda5050-design.md §10.3). It knows nothing
// about MQTT; SimulatedFleet publishes what it builds.
class SimulatedRobot {
  static const Duration actionInitializing = Duration(milliseconds: 500);
  static const Duration startupTime = Duration(seconds: 2);
  static const double chargedEnough = 80;
  static const double lowBattery = 10;
  static const String lowBatteryError = 'batteryLow';
  static const int maxInstantActionStates = 10;

  final int instance;
  final String serialNumber;
  // vda5050/v3/MQTTStudio/SIM-1
  final String topicPrefix;
  final Vda5050Source source;
  final FleetLayout layout;
  final Random _random;

  String connectionState = VdaConnectionState.online;
  String operatingMode = VdaOperatingMode.automatic;
  DateTime? _startupUntil;

  double x;
  double y;
  double theta = 0;
  String lastNodeId;
  int lastNodeSequenceId = 0;
  double distanceSinceLastNode = 0;
  bool driving = false;
  double currentSpeed = 0;
  double stateOfCharge;
  bool charging = false;
  double localizationScore;

  String orderId = '';
  int orderUpdateId = 0;
  final List<VdaNode> _nodes = [];
  final List<VdaEdge> _edges = [];
  VdaEdge? _edge;
  double _edgeFromX = 0;
  double _edgeFromY = 0;
  double _edgeLength = 0;
  double _edgeProgress = 0;
  String? _cancelActionId;
  final List<_ActionRun> _actions = [];
  final List<VdaActionState> instantActionStates = [];
  final List<VdaError> errors = [];
  bool paused = false;
  String emergencyStop = VdaEmergencyStop.none;
  bool fieldViolation = false;
  List<Map<String, Object?>> loads = [];
  final List<VdaZoneRequest> zoneRequests = [];
  bool hasZoneSet = false;
  int _requestCounter = 0;
  int _loadCounter = 0;

  // protocol faults
  bool clockSkew = false;
  bool wrongSerialNumber = false;
  int _headerSkip = 0;
  final Map<String, int> _headerIds = {};

  // what was sent, for the robot's row in the simulator tab (simulator D29)
  int sent = 0;
  DateTime? lastPublishedAt;
  DateTime? lastStateAt;
  int lastStateHeaderId = 0;
  // the state changed and is sent with the next tick
  bool stateDirty = true;

  SimulatedRobot({
    required this.instance,
    required this.serialNumber,
    required this.topicPrefix,
    required this.source,
    required this.layout,
    required Random random,
    required LayoutNode start,
    required this.stateOfCharge,
  })  : _random = random,
        x = start.x,
        y = start.y,
        lastNodeId = start.id,
        localizationScore = 0.9 + random.nextDouble() * 0.1;

  bool get isOnline => connectionState == VdaConnectionState.online;

  bool get isOnEdge => _edge != null;

  bool get hasFatalError =>
      errors.any((error) => error.errorLevel == VdaErrorLevel.fatal || error.errorLevel == VdaErrorLevel.critical);

  bool get hasHardActionRunning =>
      _actions.any((run) => run.isActive && run.action.blockingType == VdaBlockingType.hard);

  // why the robot can't drive right now; null when it can
  String? get blockedBy {
    if (!isOnline) {
      return 'connection';
    }
    if (operatingMode == VdaOperatingMode.startup) {
      return 'startup';
    }
    if (paused) {
      return 'paused';
    }
    if (emergencyStop != VdaEmergencyStop.none || fieldViolation) {
      return 'safety';
    }
    if (hasFatalError) {
      return 'error';
    }
    if (hasHardActionRunning) {
      return 'action';
    }
    if (stateOfCharge <= 0) {
      return 'battery';
    }
    return null;
  }

  List<VdaNode> get remainingNodes => _nodes.where((node) => node.sequenceId > lastNodeSequenceId).toList();

  List<VdaEdge> get remainingEdges => _edges.where((edge) => edge.sequenceId > lastNodeSequenceId).toList();

  // the sequence id of the last released node, the end of the base
  int get lastBaseSequenceId => _nodes
      .where((node) => node.released)
      .fold(lastNodeSequenceId, (last, node) => max(last, node.sequenceId));

  bool get hasOpenActions => _actions.any((run) => run.isOpen && run.nodeSequenceId <= lastNodeSequenceId);

  // nothing left to drive or to do
  bool get isIdle => !isOnEdge && remainingNodes.isEmpty && !hasOpenActions;

  // standing at the end of the base while the horizon goes on
  bool get waitsForBase => !isOnEdge && lastNodeSequenceId == lastBaseSequenceId && remainingNodes.isNotEmpty;

  // the nodes no other robot may enter: where it stands or drives to and the rest of its base
  Set<String> get reservedNodes => {
        lastNodeId,
        for (var node in remainingNodes)
          if (node.released) node.nodeId,
      };

  int get openRequests => zoneRequests.where((request) => request.requestStatus == VdaRequestStatus.requested).length;

  void startup(DateTime now) {
    if (source.version.isV3) {
      operatingMode = VdaOperatingMode.startup;
      _startupUntil = now.add(startupTime);
    } else {
      operatingMode = VdaOperatingMode.automatic;
    }
    stateDirty = true;
  }

  // the header of the next message on the topic. Messages of the fleet control carry the robot's name but none of
  // the robot's protocol faults.
  VdaHeader header(String topic, DateTime now, {bool fromRobot = true}) {
    var id = _headerIds[topic] ?? 0;
    if (fromRobot && topic == VdaTopic.state && _headerSkip > 0) {
      id += _headerSkip;
      _headerSkip = 0;
    }
    _headerIds[topic] = id + 1;
    return VdaHeader(
      headerId: id,
      timestamp: fromRobot && clockSkew ? now.add(const Duration(seconds: 10)) : now,
      version: source.version.protocolVersion,
      manufacturer: source.manufacturer,
      serialNumber: fromRobot && wrongSerialNumber ? '$serialNumber-X' : serialNumber,
    );
  }

  void skipHeaderIds(int count) => _headerSkip += count;

  // ---------- orders and instant actions ----------

  // a new order replaces the current one; an update with the same order id continues it from its first node, the
  // stitching node
  void receiveOrder(VdaOrder order, DateTime now) {
    if (order.nodes.isEmpty) {
      return;
    }
    if (order.orderId != orderId) {
      orderId = order.orderId;
      _nodes
        ..clear()
        ..addAll(order.nodes);
      _edges
        ..clear()
        ..addAll(order.edges);
      _actions
        ..clear()
        ..addAll(_runsOf(order.nodes));
      lastNodeSequenceId = order.nodes.first.sequenceId;
      lastNodeId = order.nodes.first.nodeId;
      _startNodeActions(lastNodeSequenceId, now);
    } else {
      var stitch = order.nodes.first.sequenceId;
      _nodes.removeWhere((node) => node.sequenceId > stitch);
      _edges.removeWhere((edge) => edge.sequenceId > stitch);
      _actions.removeWhere((run) => run.nodeSequenceId > stitch && run.status == VdaActionStatus.waiting);
      var added = order.nodes.skip(1).toList();
      _nodes.addAll(added);
      _edges.addAll(order.edges);
      _actions.addAll(_runsOf(added));
    }
    orderUpdateId = order.orderUpdateId;
    stateDirty = true;
  }

  static Iterable<_ActionRun> _runsOf(List<VdaNode> nodes) => [
        for (var node in nodes)
          for (var action in node.actions) _ActionRun(action, node.sequenceId)
      ];

  void applyInstantAction(VdaAction action, DateTime now) {
    var state = VdaActionState(actionId: action.actionId, actionType: action.actionType, status: VdaActionStatus.finished);
    switch (action.actionType) {
      case 'startPause':
        paused = true;
      case 'stopPause':
        paused = false;
      case 'cancelOrder':
        if (isOnEdge) {
          // the robot stops at the next node
          _cancelActionId = action.actionId;
          state.status = VdaActionStatus.running;
        } else {
          _cancelOrder();
        }
      default:
        state
          ..status = VdaActionStatus.failed
          ..result = 'not supported by the simulation';
    }
    instantActionStates.add(state);
    if (instantActionStates.length > maxInstantActionStates) {
      instantActionStates.removeAt(0);
    }
    stateDirty = true;
  }

  void _cancelOrder() {
    _nodes.removeWhere((node) => node.sequenceId > lastNodeSequenceId);
    _edges.removeWhere((edge) => edge.sequenceId > lastNodeSequenceId);
    for (var run in _actions.where((run) => run.isOpen)) {
      run
        ..status = VdaActionStatus.failed
        ..result = 'order cancelled';
      if (run.action.actionType == 'startCharging') {
        charging = false;
      }
    }
    zoneRequests.clear();
    stateDirty = true;
  }

  // ---------- errors ----------

  void addError(String type, String level, String description) {
    errors.removeWhere((error) => error.errorType == type);
    errors.add(VdaError(
      errorType: type,
      errorLevel: level,
      description: description,
      references: [VdaReference('nodeId', lastNodeId)],
    ));
    stateDirty = true;
  }

  void removeError(String type) {
    var before = errors.length;
    errors.removeWhere((error) => error.errorType == type);
    if (errors.length != before) {
      stateDirty = true;
    }
  }

  void clearErrors() {
    errors.clear();
    emergencyStop = VdaEmergencyStop.none;
    fieldViolation = false;
    stateDirty = true;
  }

  // ---------- zone requests (3.0) ----------

  void answerRequest(String requestId, String grantType) {
    for (var request in zoneRequests.where((request) => request.requestId == requestId)) {
      request.requestStatus = switch (grantType) {
        VdaGrantType.granted => VdaRequestStatus.granted,
        VdaGrantType.revoked || VdaGrantType.rejected => VdaRequestStatus.revoked,
        _ => request.requestStatus,
      };
      stateDirty = true;
    }
    if (grantType == VdaGrantType.rejected || grantType == VdaGrantType.revoked) {
      zoneRequests.removeWhere((request) => request.requestId == requestId);
    }
  }

  // ---------- time ----------

  void tick(DateTime now, double seconds) {
    if (!isOnline) {
      _setDriving(false, 0);
      return;
    }
    if (_startupUntil != null && !now.isBefore(_startupUntil!)) {
      _startupUntil = null;
      operatingMode = VdaOperatingMode.automatic;
      stateDirty = true;
    }
    _advanceActions(now);
    if (charging) {
      stateOfCharge = min(100, stateOfCharge + source.chargePerHour * seconds / 3600);
    }
    if (!isOnEdge) {
      _startNextEdge();
    }
    if (isOnEdge) {
      _drive(seconds, now);
    } else {
      _setDriving(false, 0);
    }
    if (stateOfCharge < lowBattery && !charging) {
      if (!errors.any((error) => error.errorType == lowBatteryError)) {
        addError(lowBatteryError, VdaErrorLevel.warning, 'Battery below $lowBattery %');
      }
    } else {
      removeError(lowBatteryError);
    }
  }

  void _setDriving(bool value, double speed) {
    if (driving != value) {
      driving = value;
      stateDirty = true;
    }
    currentSpeed = speed;
  }

  void _startNextEdge() {
    if (blockedBy != null) {
      return;
    }
    var edge = _edges.where((edge) => edge.sequenceId == lastNodeSequenceId + 1 && edge.released).firstOrNull;
    var target = _nodeAt(lastNodeSequenceId + 2);
    if (edge == null || target == null || !target.released || target.position == null) {
      return;
    }
    if (!_mayEnter(target.position!)) {
      return;
    }
    _edge = edge;
    _edgeFromX = x;
    _edgeFromY = y;
    _edgeLength = sqrt(pow(target.position!.x - x, 2) + pow(target.position!.y - y, 2));
    _edgeProgress = 0;
    theta = atan2(target.position!.y - y, target.position!.x - x);
    stateDirty = true;
  }

  // a release zone needs a granted request before the robot drives into it (3.0 with requests)
  bool _mayEnter(VdaNodePosition target) {
    if (!source.usesRequests) {
      return true;
    }
    var zone = layout.releaseZoneAt(target.x, target.y);
    if (zone == null || zone.contains(x, y)) {
      return true;
    }
    var request = zoneRequests.where((request) => request.zoneId == zone.zoneId).firstOrNull;
    if (request == null) {
      _requestCounter++;
      zoneRequests.add(VdaZoneRequest(
          requestId: '$serialNumber-r$_requestCounter', zoneId: zone.zoneId, zoneSetId: FleetLayout.zoneSetId));
      stateDirty = true;
      return false;
    }
    return request.requestStatus == VdaRequestStatus.granted;
  }

  void _drive(double seconds, DateTime now) {
    if (blockedBy != null) {
      _setDriving(false, 0);
      return;
    }
    var edge = _edge!;
    var speed = min(source.speed, edge.maximumSpeed ?? double.infinity);
    speed = min(speed, layout.speedLimitAt(x, y) ?? double.infinity);
    var step = speed * seconds;
    _edgeProgress = min(_edgeLength, _edgeProgress + step);
    var target = _nodeAt(edge.sequenceId + 1)!.position!;
    var t = _edgeLength == 0 ? 1.0 : _edgeProgress / _edgeLength;
    x = _edgeFromX + (target.x - _edgeFromX) * t;
    y = _edgeFromY + (target.y - _edgeFromY) * t;
    distanceSinceLastNode += step;
    stateOfCharge = max(0, stateOfCharge - source.batteryPerHour * seconds / 3600);
    _setDriving(true, speed);
    if (_edgeProgress >= _edgeLength) {
      _arrive(edge, now);
    }
  }

  void _arrive(VdaEdge edge, DateTime now) {
    var node = _nodeAt(edge.sequenceId + 1)!;
    var leftZone = layout.releaseZoneAt(_edgeFromX, _edgeFromY);
    x = node.position!.x;
    y = node.position!.y;
    lastNodeId = node.nodeId;
    lastNodeSequenceId = node.sequenceId;
    distanceSinceLastNode = 0;
    _edge = null;
    if (leftZone != null && !leftZone.contains(x, y)) {
      zoneRequests.removeWhere((request) => request.zoneId == leftZone.zoneId);
    }
    _startNodeActions(node.sequenceId, now);
    if (_cancelActionId != null) {
      _cancelOrder();
      for (var state in instantActionStates.where((state) => state.actionId == _cancelActionId)) {
        state.status = VdaActionStatus.finished;
      }
      _cancelActionId = null;
    }
    stateDirty = true;
  }

  VdaNode? _nodeAt(int sequenceId) => _nodes.where((node) => node.sequenceId == sequenceId).firstOrNull;

  void _startNodeActions(int sequenceId, DateTime now) {
    for (var run in _actions.where((run) => run.nodeSequenceId == sequenceId && run.status == VdaActionStatus.waiting)) {
      run
        ..status = VdaActionStatus.initializing
        ..endsAt = now.add(actionInitializing);
      stateDirty = true;
    }
  }

  void _advanceActions(DateTime now) {
    for (var run in _actions) {
      if (paused && run.status == VdaActionStatus.running) {
        run
          ..status = VdaActionStatus.paused
          ..remaining = run.endsAt?.difference(now);
        stateDirty = true;
        continue;
      }
      if (!paused && run.status == VdaActionStatus.paused) {
        run
          ..status = VdaActionStatus.running
          ..endsAt = now.add(run.remaining ?? Duration.zero);
        stateDirty = true;
        continue;
      }
      if (run.status == VdaActionStatus.initializing && !now.isBefore(run.endsAt!)) {
        _run(run, now);
      } else if (run.status == VdaActionStatus.running && _isDone(run, now)) {
        _finish(run);
      }
    }
  }

  void _run(_ActionRun run, DateTime now) {
    var seconds = source.minActionSec + _random.nextDouble() * max(0, source.maxActionSec - source.minActionSec);
    run
      ..status = VdaActionStatus.running
      ..endsAt = now.add(Duration(milliseconds: (seconds * 1000).round()));
    if (run.action.actionType == 'startCharging') {
      charging = true;
    }
    stateDirty = true;
  }

  bool _isDone(_ActionRun run, DateTime now) => run.action.actionType == 'startCharging'
      ? stateOfCharge >= chargedEnough
      : !now.isBefore(run.endsAt!);

  void _finish(_ActionRun run) {
    run.status = VdaActionStatus.finished;
    switch (run.action.actionType) {
      case 'pick':
        _loadCounter++;
        loads = [
          {'loadId': '$serialNumber-L$_loadCounter', 'loadType': 'EPAL', 'loadPosition': 'front'}
        ];
        run.result = 'picked $serialNumber-L$_loadCounter';
      case 'drop':
        loads = [];
      case 'startCharging':
        charging = false;
    }
    stateDirty = true;
  }

  // ---------- messages ----------

  VdaPosition get position => VdaPosition(
        x: _round(x),
        y: _round(y),
        theta: _theta,
        mapId: source.mapId,
        localized: true,
        localizationScore: _round(localizationScore, 2),
      );

  VdaVelocity get velocity => VdaVelocity(vx: _round(currentSpeed), vy: 0, omega: 0);

  VdaState buildState(VdaHeader header, DateTime now) {
    var v3 = source.version.isV3;
    return VdaState(
      header: header,
      maps: [VdaMapInfo(mapId: source.mapId, mapVersion: '1')],
      zoneSets: v3 && hasZoneSet ? [VdaZoneSetInfo(zoneSetId: FleetLayout.zoneSetId, mapId: source.mapId)] : null,
      orderId: orderId,
      orderUpdateId: orderUpdateId,
      lastNodeId: lastNodeId,
      lastNodeSequenceId: lastNodeSequenceId,
      nodeStates: [
        for (var node in remainingNodes)
          VdaNodeState(nodeId: node.nodeId, sequenceId: node.sequenceId, released: node.released, position: node.position)
      ],
      edgeStates: [
        for (var edge in remainingEdges)
          VdaEdgeState(edgeId: edge.edgeId, sequenceId: edge.sequenceId, released: edge.released)
      ],
      plannedPath: v3 && remainingNodes.isNotEmpty ? _plannedPath() : null,
      intermediatePath: v3 && isOnEdge ? _intermediatePath(now) : null,
      position: position,
      velocity: velocity,
      loads: loads,
      driving: driving,
      paused: paused,
      newBaseRequest: waitsForBase,
      zoneRequests: v3 ? [for (var request in zoneRequests) request] : null,
      distanceSinceLastNode: _round(distanceSinceLastNode),
      actionStates: [
        for (var run in _actions)
          VdaActionState(
              actionId: run.action.actionId, actionType: run.action.actionType, status: run.status, result: run.result)
      ],
      instantActionStates: instantActionStates,
      powerSupply: VdaPowerSupply(
        stateOfCharge: _round(stateOfCharge, 1),
        charging: charging,
        batteryVoltage: _round(24 + stateOfCharge / 100 * 4, 2),
        batteryCurrent: v3 ? (charging ? 30 : (driving ? -12 : -1)) : null,
        range: _round(stateOfCharge / 100 * 8000, 0),
      ),
      operatingMode: operatingMode,
      errors: errors,
      safetyState: VdaSafetyState(activeEmergencyStop: emergencyStop, fieldViolation: fieldViolation),
    );
  }

  VdaVisualization buildVisualization(VdaHeader header) => VdaVisualization(
        header: header,
        referenceStateHeaderId: source.version.isV3 ? lastStateHeaderId : null,
        position: position,
        velocity: velocity,
      );

  // from where the robot is along the released nodes still ahead
  VdaPlannedPath _plannedPath() => VdaPlannedPath(controlPoints: [
        VdaPoint(_round(x), _round(y)),
        for (var node in remainingNodes)
          if (node.released && node.position != null) VdaPoint(node.position!.x, node.position!.y)
      ]);

  // the end of the current edge, with the time the robot gets there
  VdaIntermediatePath _intermediatePath(DateTime now) {
    var target = _nodeAt(_edge!.sequenceId + 1)!.position!;
    var speed = currentSpeed > 0 ? currentSpeed : source.speed;
    var seconds = (_edgeLength - _edgeProgress) / speed;
    return VdaIntermediatePath(polyline: [
      VdaPathPoint(x: _round(x), y: _round(y), theta: _theta, eta: now),
      VdaPathPoint(
          x: target.x,
          y: target.y,
          theta: _theta,
          eta: now.add(Duration(milliseconds: (seconds * 1000).round()))),
    ]);
  }

  // rounding could push π past the schema's maximum of 3.14159265359
  double get _theta => _round(theta, 4).clamp(-pi, pi);

  static double _round(double value, [int digits = 3]) {
    var factor = pow(10, digits);
    return (value * factor).roundToDouble() / factor;
  }
}
