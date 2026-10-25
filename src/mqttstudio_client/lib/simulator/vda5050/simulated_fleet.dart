import 'dart:async';
import 'dart:math';
import 'package:clock/clock.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_writer.dart';
import 'package:mqttstudio/simulator/engine/placeholders.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/model/vda5050_source.dart';
import 'package:mqttstudio/simulator/vda5050/fleet_controller.dart';
import 'package:mqttstudio/simulator/vda5050/fleet_layout.dart';
import 'package:mqttstudio/simulator/vda5050/robot_fault.dart';
import 'package:mqttstudio/simulator/vda5050/simulated_robot.dart';

// sends one VDA 5050 message; the runner encodes it and hands it to the SimulatorPublisher
typedef VdaPublish = void Function(String topic, Map<String, Object?> json, MqttQos qos, bool retain);

class _ScheduledClear {
  final SimulatedRobot robot;
  final String errorType;
  final DateTime at;

  _ScheduledClear(this.robot, this.errorType, this.at);
}

// The robots of one VDA 5050 device and the fleet control that drives them (doc/vda5050-design.md §10). A timer
// moves everything forward every 100 ms and publishes what changed: state on every event and as heartbeat,
// visualization at its interval. QoS and retain follow the specification: connection with QoS 1 and retained, the
// rest with QoS 0.
class SimulatedFleet {
  static const Duration tickInterval = Duration(milliseconds: 100);
  static const int skippedHeaderIds = 5;
  // msg/s of a robot beside its visualization: state on events and the fleet's orders
  static const double eventRate = 2;

  final SimulatedDevice device;
  final Vda5050Source source;
  final FleetLayout layout;
  final Vda5050Writer writer;
  final List<SimulatedRobot> robots = [];
  final VdaPublish _publish;
  final Random _random;
  // called after every message, for the statistics
  final void Function()? onPublished;
  late final FleetController controller;

  Timer? _timer;
  DateTime _lastTick = clock.now();
  final Map<SimulatedRobot, DateTime> _nextVisualization = {};
  final Set<SimulatedRobot> _brokenOrderPending = {};
  final Set<SimulatedRobot> _unansweredPending = {};
  final Map<SimulatedRobot, VdaOrder> _lastOrder = {};
  final List<_ScheduledClear> _clears = [];
  int _instantActionCounter = 0;
  int _unknownRequestCounter = 0;

  SimulatedFleet(this.device, this._publish, this._random, {this.onPublished})
      : source = device.vda5050!,
        layout = FleetLayout.grid(device.vda5050!),
        writer = Vda5050Writer(device.vda5050!.version) {
    controller = FleetController(this, _random);
    var free = layout.nodes.values.where((node) => !node.charging).toList()..shuffle(_random);
    var index = 0;
    for (var n in device.instanceNumbers) {
      robots.add(SimulatedRobot(
        instance: n,
        serialNumber: Placeholders.resolve(source.serialNumber, instance: n, deviceName: device.name),
        topicPrefix: Placeholders.resolve(source.topicPrefix, instance: n, deviceName: device.name),
        source: source,
        layout: layout,
        random: _random,
        start: free[index++ % free.length],
        stateOfCharge: (60 + _random.nextDouble() * 40).roundToDouble(),
      ));
    }
  }

  // estimated msg/s of a device, for the rate limit (simulator §7.2)
  static double rateOf(SimulatedDevice device) {
    var source = device.vda5050;
    if (source == null) {
      return 0;
    }
    var visualization = source.visualizationMs > 0 ? 1000 / source.visualizationMs : 0;
    return device.instanceCount * (visualization + eventRate);
  }

  bool get isRunning => _timer != null;

  int get sent => robots.fold(0, (sum, robot) => sum + robot.sent);

  SimulatedRobot? robotOf(int instance) => robots.where((robot) => robot.instance == instance).firstOrNull;

  void start() {
    var now = clock.now();
    _lastTick = now;
    for (var robot in robots) {
      robot.startup(now);
      _sendConnection(robot, VdaConnectionState.online, now);
      if (source.factsheet) {
        _send(robot, _factsheet(robot, now));
      }
      if (layout.zoneSet != null) {
        _send(robot, VdaZoneSetMessage(header: robot.header(VdaTopic.zoneSet, now, fromRobot: false), zoneSet: layout.zoneSet!));
        robot.hasZoneSet = true;
      }
    }
    _publishDue(now);
    _timer = Timer.periodic(tickInterval, (_) => _tick());
  }

  // goodbye: the robots that are connected say OFFLINE, as after a coordinated disconnect
  void stop({bool goodbye = true}) {
    _timer?.cancel();
    _timer = null;
    if (!goodbye) {
      return;
    }
    var now = clock.now();
    for (var robot in robots) {
      if (robot.isOnline || robot.connectionState == VdaConnectionState.hibernating) {
        robot.connectionState = VdaConnectionState.offline;
        _sendConnection(robot, VdaConnectionState.offline, now);
      }
    }
  }

  void _tick() {
    var now = clock.now();
    var seconds = now.difference(_lastTick).inMicroseconds / 1e6;
    _lastTick = now;
    for (var robot in robots) {
      robot.tick(now, seconds);
    }
    controller.tick(now);
    _randomFaults(now, seconds);
    _publishDue(now);
  }

  void _publishDue(DateTime now) {
    var heartbeat = Duration(seconds: source.stateHeartbeatSec);
    for (var robot in robots) {
      if (!robot.isOnline) {
        continue;
      }
      if (robot.stateDirty || robot.lastStateAt == null || now.difference(robot.lastStateAt!) >= heartbeat) {
        var header = robot.header(VdaTopic.state, now);
        _send(robot, robot.buildState(header, now));
        robot
          ..stateDirty = false
          ..lastStateAt = now
          ..lastStateHeaderId = header.headerId;
      }
      if (source.visualizationMs > 0) {
        var next = _nextVisualization[robot];
        if (next == null || !now.isBefore(next)) {
          _send(robot, robot.buildVisualization(robot.header(VdaTopic.visualization, now)));
          _nextVisualization[robot] = now.add(Duration(milliseconds: source.visualizationMs));
        }
      }
    }
  }

  void _send(SimulatedRobot robot, VdaMessage message,
      {MqttQos qos = MqttQos.atMostOnce, bool retain = false, void Function(Map<String, Object?> json)? change}) {
    var json = writer.toJson(message);
    change?.call(json);
    _publish('${robot.topicPrefix}/${message.topic}', json, qos, retain);
    robot
      ..sent += 1
      ..lastPublishedAt = clock.now();
    onPublished?.call();
  }

  void _sendConnection(SimulatedRobot robot, String state, DateTime now) => _send(
      robot, VdaConnection(header: robot.header(VdaTopic.connection, now), connectionState: state),
      qos: MqttQos.atLeastOnce, retain: true);

  VdaFactsheet _factsheet(SimulatedRobot robot, DateTime now) => VdaFactsheet(
        header: robot.header(VdaTopic.factsheet, now),
        seriesName: 'MQTT Studio simulated robot',
        seriesDescription: 'Simulated by the MQTT Studio simulator',
        kinematics: 'DIFFERENTIAL',
        robotClass: 'CARRIER',
        maximumLoadMass: 1000,
        localizationTypes: ['NATURAL'],
        navigationTypes: ['VIRTUAL_LINE_GUIDED'],
        minimumSpeed: 0,
        maximumSpeed: source.speed,
        maximumAcceleration: 0.5,
        maximumDeceleration: 0.5,
        minimumHeight: 0.3,
        maximumHeight: 1.5,
        width: 0.8,
        length: 1.2,
        minimumOrderInterval: 0.5,
        minimumStateInterval: 0.1,
        actions: [
          for (var type in ['pick', 'drop', 'startCharging'])
            VdaFactsheetAction(type, ['NODE'], pauseAllowed: true, cancelAllowed: true),
          for (var type in ['startPause', 'stopPause', 'cancelOrder'])
            VdaFactsheetAction(type, ['INSTANT']),
        ],
      );

  // ---------- the fleet control's messages ----------

  void sendOrder(SimulatedRobot robot, VdaOrder order, DateTime now) {
    order.header = robot.header(VdaTopic.order, now, fromRobot: false);
    var broken = _brokenOrderPending.remove(robot);
    _send(robot, order, change: broken ? _breakSequence : null);
    _lastOrder[robot] = order;
    robot.receiveOrder(order, now);
  }

  // edges no longer between their nodes: a gap in the sequence ids
  static void _breakSequence(Map<String, Object?> json) {
    for (var edge in (json['edges'] as List? ?? const [])) {
      if (edge is Map) {
        edge['sequenceId'] = ((edge['sequenceId'] as int?) ?? 0) + 2;
      }
    }
  }

  void _sendInstantAction(SimulatedRobot robot, String actionType, DateTime now) {
    var action = VdaAction(actionId: 'ia${++_instantActionCounter}', actionType: actionType);
    _send(robot,
        VdaInstantActions(header: robot.header(VdaTopic.instantActions, now, fromRobot: false), actions: [action]));
    robot.applyInstantAction(action, now);
  }

  void sendResponse(SimulatedRobot robot, String requestId, String grantType, DateTime now) {
    _send(
        robot,
        VdaResponses(
            header: robot.header(VdaTopic.responses, now, fromRobot: false),
            responses: [VdaResponse(requestId: requestId, grantType: grantType)]));
    robot.answerRequest(requestId, grantType);
  }

  // the unanswered request fault applies to the robot's next request
  bool takeUnansweredRequest(SimulatedRobot robot) => _unansweredPending.remove(robot);

  // ---------- faults (§10.4) ----------

  bool isFaultAvailable(SimulatedRobot robot, RobotFault fault) {
    if (fault.v3Only && !source.version.isV3) {
      return false;
    }
    return switch (fault) {
      RobotFault.connectionBroken || RobotFault.offline || RobotFault.hibernate => robot.isOnline,
      RobotFault.reconnect => !robot.isOnline,
      RobotFault.cancelOrder => !robot.isIdle,
      RobotFault.lowerOrderUpdate => (_lastOrder[robot]?.orderUpdateId ?? 0) > 0,
      RobotFault.unansweredRequest => source.usesRequests,
      RobotFault.clearErrors => robot.errors.isNotEmpty || robot.emergencyStop != VdaEmergencyStop.none || robot.fieldViolation,
      _ => true,
    };
  }

  // whether a toggled fault is on
  bool isFaultActive(SimulatedRobot robot, RobotFault fault) => switch (fault) {
        RobotFault.emergencyStop => robot.emergencyStop != VdaEmergencyStop.none,
        RobotFault.fieldViolation => robot.fieldViolation,
        RobotFault.pause => robot.paused,
        RobotFault.clockSkew => robot.clockSkew,
        RobotFault.wrongSerialNumber => robot.wrongSerialNumber,
        _ => false,
      };

  void inject(SimulatedRobot robot, RobotFault fault) {
    var now = clock.now();
    switch (fault) {
      case RobotFault.warning:
        robot.addError('simulatedWarning', VdaErrorLevel.warning, 'Simulated warning');
      case RobotFault.urgent:
        robot.addError('simulatedUrgent', VdaErrorLevel.urgent, 'Simulated urgent error');
      case RobotFault.critical:
        robot.addError('simulatedCritical', VdaErrorLevel.critical, 'Simulated critical error');
      case RobotFault.fatal:
        robot.addError('simulatedFatal', VdaErrorLevel.fatal, 'Simulated fatal error');
      case RobotFault.emergencyStop:
        robot.emergencyStop =
            robot.emergencyStop == VdaEmergencyStop.none ? VdaEmergencyStop.manual : VdaEmergencyStop.none;
      case RobotFault.fieldViolation:
        robot.fieldViolation = !robot.fieldViolation;
      case RobotFault.pause:
        _sendInstantAction(robot, robot.paused ? 'stopPause' : 'startPause', now);
      case RobotFault.lowBattery:
        robot.stateOfCharge = 5;
      case RobotFault.cancelOrder:
        controller.forget(robot);
        _sendInstantAction(robot, 'cancelOrder', now);
      case RobotFault.clearErrors:
        robot.clearErrors();
      case RobotFault.connectionBroken:
        _changeConnection(robot, VdaConnectionState.connectionBroken, now);
      case RobotFault.offline:
        _changeConnection(robot, VdaConnectionState.offline, now);
      case RobotFault.hibernate:
        _changeConnection(robot, VdaConnectionState.hibernating, now);
      case RobotFault.reconnect:
        _changeConnection(robot, VdaConnectionState.online, now);
        robot.startup(now);
      case RobotFault.skipHeaderIds:
        robot.skipHeaderIds(skippedHeaderIds);
      case RobotFault.clockSkew:
        robot.clockSkew = !robot.clockSkew;
      case RobotFault.wrongSerialNumber:
        robot.wrongSerialNumber = !robot.wrongSerialNumber;
      case RobotFault.brokenOrder:
        _brokenOrderPending.add(robot);
      case RobotFault.lowerOrderUpdate:
        _resendLowerUpdate(robot, now);
      case RobotFault.responseWithoutRequest:
        _send(
            robot,
            VdaResponses(header: robot.header(VdaTopic.responses, now, fromRobot: false), responses: [
              VdaResponse(requestId: '${robot.serialNumber}-unknown${++_unknownRequestCounter}', grantType: VdaGrantType.granted)
            ]));
      case RobotFault.unansweredRequest:
        _unansweredPending.add(robot);
    }
    robot.stateDirty = true;
    _publishDue(now);
  }

  // a broken connection is published by the simulation as the broker would publish the last will (§10.5)
  void _changeConnection(SimulatedRobot robot, String state, DateTime now) {
    robot.connectionState = state;
    _sendConnection(robot, state, now);
  }

  // the last order sent again, with an update id lower than the one sent before
  void _resendLowerUpdate(SimulatedRobot robot, DateTime now) {
    var order = _lastOrder[robot];
    if (order == null || order.orderUpdateId == 0) {
      return;
    }
    var copy = VdaOrder(
        header: robot.header(VdaTopic.order, now, fromRobot: false),
        orderId: order.orderId,
        orderUpdateId: order.orderUpdateId - 1,
        nodes: order.nodes,
        edges: order.edges);
    _send(robot, copy);
  }

  // random warnings and fatal errors that clear themselves after 20 to 60 s
  void _randomFaults(DateTime now, double seconds) {
    for (var clear in _clears.where((clear) => !now.isBefore(clear.at)).toList()) {
      clear.robot.removeError(clear.errorType);
      _clears.remove(clear);
    }
    if (source.randomFaultsPerHour <= 0) {
      return;
    }
    var chance = source.randomFaultsPerHour * seconds / 3600;
    for (var robot in robots.where((robot) => robot.isOnline)) {
      if (_random.nextDouble() >= chance) {
        continue;
      }
      var fatal = _random.nextDouble() < 0.3;
      var type = fatal ? 'randomFatal' : 'randomWarning';
      robot.addError(type, fatal ? VdaErrorLevel.fatal : VdaErrorLevel.warning,
          fatal ? 'Random fatal error of the simulation' : 'Random warning of the simulation');
      _clears.add(_ScheduledClear(robot, type, now.add(Duration(seconds: 20 + _random.nextInt(41)))));
    }
  }
}
