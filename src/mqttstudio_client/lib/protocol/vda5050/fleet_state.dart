import 'dart:math';
import 'package:mqttstudio/protocol/protocol_profile.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_profile.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_reader.dart';

// what the fleet view shows a robot as, from its connection, errors and driving (doc/vda5050-design.md V11)
enum VehicleStatus { offline, connectionBroken, hibernating, error, warning, driving, idle, unknown }

class TrailPoint {
  final String mapId;
  final double x;
  final double y;

  const TrailPoint(this.mapId, this.x, this.y);
}

// What the fleet view knows about one robot: the last message of each kind it cares about. M is the message the
// robot's messages came in, so the view can select it.
class VehicleState<M> {
  static const int maxTrail = 200;
  // a state older than this is stale, like the documentation check's heartbeat (doc/vda5050-design.md §9.3)
  static const Duration staleAfter = Duration(seconds: 35);

  // the topic without the message type
  final String deviceKey;
  final String manufacturer;
  final String serialNumber;
  // as in the last header, e.g. '3.0.0'
  String version = '';
  VdaConnection? connection;
  M? connectionMessage;
  VdaState? state;
  M? stateMessage;
  DateTime? stateReceivedAt;
  VdaVisualization? visualization;
  DateTime? visualizationReceivedAt;
  VdaOrder? order;
  final List<TrailPoint> trail = [];

  VehicleState(this.deviceKey, this.manufacturer, this.serialNumber);

  String get name => '$manufacturer $serialNumber';

  // the newer of the state's and the visualization's position
  VdaPosition? get position {
    var fromState = state?.position;
    var fromVisualization = visualization?.position;
    if (fromVisualization == null) {
      return fromState;
    }
    if (fromState == null || stateReceivedAt == null) {
      return fromVisualization;
    }
    return visualizationReceivedAt!.isAfter(stateReceivedAt!) ? fromVisualization : fromState;
  }

  // 3.0 paths: the newer of the state's and the visualization's
  VdaPlannedPath? get plannedPath => _newer(state?.plannedPath, visualization?.plannedPath);

  VdaIntermediatePath? get intermediatePath => _newer(state?.intermediatePath, visualization?.intermediatePath);

  T? _newer<T>(T? fromState, T? fromVisualization) {
    if (fromVisualization == null || (fromState != null && !visualizationReceivedAt!.isAfter(stateReceivedAt!))) {
      return fromState;
    }
    return fromVisualization;
  }

  String? get connectionState => connection?.connectionState;

  bool get isOnline => connectionState == null || connectionState == VdaConnectionState.online;

  // the highest level of the errors the robot reports, null without errors
  String? get highestErrorLevel {
    var errors = state?.errors ?? const <VdaError>[];
    if (errors.isEmpty) {
      return null;
    }
    return errors.map((error) => error.errorLevel).reduce((a, b) => _errorRank(a) >= _errorRank(b) ? a : b);
  }

  static int _errorRank(String level) => switch (level) {
    VdaErrorLevel.fatal => 3,
    VdaErrorLevel.critical => 2,
    VdaErrorLevel.urgent => 1,
    _ => 0,
  };

  static bool isErrorLevel(String level) => _errorRank(level) >= 2;

  // zone and edge requests the robot still waits for (3.0)
  int get openRequests {
    var state = this.state;
    if (state == null) {
      return 0;
    }
    return state.zoneRequests.where((request) => request.requestStatus == VdaRequestStatus.requested).length +
        state.edgeRequests.where((request) => request.requestStatus == VdaRequestStatus.requested).length;
  }

  VehicleStatus get status {
    switch (connectionState) {
      case VdaConnectionState.offline:
        return VehicleStatus.offline;
      case VdaConnectionState.connectionBroken:
        return VehicleStatus.connectionBroken;
      case VdaConnectionState.hibernating:
        return VehicleStatus.hibernating;
    }
    var state = this.state;
    if (state == null) {
      return VehicleStatus.unknown;
    }
    var level = highestErrorLevel;
    if (level != null) {
      return isErrorLevel(level) ? VehicleStatus.error : VehicleStatus.warning;
    }
    return state.driving && state.paused != true ? VehicleStatus.driving : VehicleStatus.idle;
  }

  Duration? stateAge(DateTime now) => stateReceivedAt == null ? null : now.difference(stateReceivedAt!);

  bool isStale(DateTime now) => (stateAge(now) ?? Duration.zero) > staleAfter;

  void _addTrail(VdaPosition? position) {
    if (position == null) {
      return;
    }
    var last = trail.isEmpty ? null : trail.last;
    if (last != null && last.mapId == position.mapId && last.x == position.x && last.y == position.y) {
      return;
    }
    trail.add(TrailPoint(position.mapId, position.x, position.y));
    if (trail.length > maxTrail) {
      trail.removeAt(0);
    }
  }
}

// Folds VDA 5050 messages into one VehicleState per robot, robots of every version in one fleet (doc/vda5050-design.md
// §8). It only reads; messages that aren't VDA 5050 or can't be read are skipped.
class FleetState<M> {
  final Map<String, VehicleState<M>> _vehicles = {};
  // the zone sets per map and zone set id, the last one sent to any robot (3.0)
  final Map<String, Map<String, VdaZoneSet>> _zoneSets = {};

  // the message types the fleet view needs
  static const Set<String> fleetTypes = {
    VdaTopic.connection,
    VdaTopic.state,
    VdaTopic.visualization,
    VdaTopic.order,
    VdaTopic.zoneSet,
  };

  // a robot shows up in the fleet with one of these
  static bool showsRobot(ProtocolTopic match) =>
      match.profile is Vda5050Profile &&
      (match.messageType == VdaTopic.connection ||
          match.messageType == VdaTopic.state ||
          match.messageType == VdaTopic.visualization);

  List<VehicleState<M>> get vehicles => _vehicles.values.toList();

  bool get isEmpty => _vehicles.isEmpty;

  VehicleState<M>? vehicle(String deviceKey) => _vehicles[deviceKey];

  List<VdaZoneSet> zoneSetsOf(String mapId) => _zoneSets[mapId]?.values.toList() ?? const [];

  void clear() {
    _vehicles.clear();
    _zoneSets.clear();
  }

  // returns false when the message changes nothing in the fleet
  bool add(ProtocolTopic match, Object? data, DateTime receivedAt, M message) {
    if (match.profile is! Vda5050Profile ||
        !fleetTypes.contains(match.messageType) ||
        !Vda5050Profile.hasHeader(data)) {
      return false;
    }
    var json = (data as Map).map((key, value) => MapEntry('$key', value));
    var read = Vda5050Reader.read(match.messageType, json);
    if (read == null) {
      return false;
    }
    if (read is VdaZoneSetMessage) {
      var zoneSet = read.zoneSet;
      _zoneSets.putIfAbsent(zoneSet.mapId, () => {})[zoneSet.zoneSetId] = zoneSet;
      return true;
    }
    var vehicle = _vehicles[match.deviceKey];
    if (vehicle == null) {
      // an order alone doesn't make a robot, it may be addressed to one that never answers
      if (read is VdaOrder) {
        return false;
      }
      vehicle = _vehicles[match.deviceKey] = VehicleState<M>(
        match.deviceKey,
        match.parameters[Vda5050Profile.manufacturerKey] ?? '',
        match.parameters[Vda5050Profile.serialNumberKey] ?? '',
      );
    }
    if (read.header.version.isNotEmpty) {
      vehicle.version = read.header.version;
    }
    switch (read) {
      case VdaConnection connection:
        vehicle.connection = connection;
        vehicle.connectionMessage = message;
      case VdaState state:
        vehicle.state = state;
        vehicle.stateMessage = message;
        vehicle.stateReceivedAt = receivedAt;
        vehicle._addTrail(state.position);
      case VdaVisualization visualization:
        vehicle.visualization = visualization;
        vehicle.visualizationReceivedAt = receivedAt;
        vehicle._addTrail(visualization.position);
      case VdaOrder order:
        vehicle.order = order;
      default:
        return false;
    }
    return true;
  }

  // the maps of the fleet: where robots are, orders lead and zones lie, most robots first
  List<String> get maps {
    var robots = <String, int>{};
    for (var vehicle in _vehicles.values) {
      var mapId = vehicle.position?.mapId;
      if (mapId != null) {
        robots[mapId] = (robots[mapId] ?? 0) + 1;
      }
      for (var node in vehicle.order?.nodes ?? const <VdaNode>[]) {
        var nodeMap = node.position?.mapId;
        if (nodeMap != null) {
          robots.putIfAbsent(nodeMap, () => 0);
        }
      }
    }
    for (var mapId in _zoneSets.keys) {
      robots.putIfAbsent(mapId, () => 0);
    }
    int byRobots(String a, String b) {
      var count = robots[b]!.compareTo(robots[a]!);
      return count != 0 ? count : a.compareTo(b);
    }

    return robots.keys.toList()..sort(byRobots);
  }

  // everything worth seeing on a map: positions, trails, order nodes and zones; null when the map is empty
  Rectangle<double>? boundsOf(String mapId) {
    double? minX, minY, maxX, maxY;
    void include(double x, double y) {
      minX = min(minX ?? x, x);
      minY = min(minY ?? y, y);
      maxX = max(maxX ?? x, x);
      maxY = max(maxY ?? y, y);
    }

    for (var vehicle in _vehicles.values) {
      var position = vehicle.position;
      if (position != null && position.mapId == mapId) {
        include(position.x, position.y);
      }
      for (var node in vehicle.order?.nodes ?? const <VdaNode>[]) {
        if (node.position?.mapId == mapId) {
          include(node.position!.x, node.position!.y);
        }
      }
    }
    for (var zoneSet in zoneSetsOf(mapId)) {
      for (var zone in zoneSet.zones) {
        for (var vertex in zone.vertices) {
          include(vertex.x, vertex.y);
        }
      }
    }
    if (minX == null) {
      return null;
    }
    return Rectangle(minX!, minY!, maxX! - minX!, maxY! - minY!);
  }
}
