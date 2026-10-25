import 'dart:collection';
import 'dart:math';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/simulator/model/vda5050_source.dart';

class LayoutNode {
  final String id;
  final double x;
  final double y;
  final bool charging;

  const LayoutNode(this.id, this.x, this.y, {this.charging = false});
}

// The map simulated robots drive on: a grid of nodes connected to their neighbours, charging stations on the first
// row, and for 3.0 a zone set (doc/vda5050-design.md §10.3). A blocked zone removes the node under it from the grid.
class FleetLayout {
  static const String zoneSetId = 'sim-zones';

  final String mapId;
  final Map<String, LayoutNode> nodes;
  final Map<String, List<String>> neighbours;
  final VdaZoneSet? zoneSet;

  FleetLayout._(this.mapId, this.nodes, this.neighbours, this.zoneSet);

  // the zones are only built when the grid is large enough to keep it connected
  static bool hasRoomForZones(Vda5050Source source) => source.columns >= 4 && source.rows >= 3;

  // nodes robots can stand on when they start or drive to: all but the charging stations
  static int freeNodeCount(Vda5050Source source) {
    var blocked = source.usesZones && hasRoomForZones(source) ? 1 : 0;
    return source.columns * source.rows - blocked - min(source.chargingStations, source.columns);
  }

  factory FleetLayout.grid(Vda5050Source source) {
    var spacing = source.spacing;
    var zoneSet = source.usesZones && hasRoomForZones(source) ? _zones(source) : null;
    var blocked = zoneSet?.zones.where((zone) => zone.zoneType == VdaZoneType.blocked).toList() ?? [];
    var charging = _chargingColumns(source);
    var nodes = <String, LayoutNode>{};
    for (var row = 0; row < source.rows; row++) {
      for (var column = 0; column < source.columns; column++) {
        var x = column * spacing;
        var y = row * spacing;
        if (blocked.any((zone) => zone.contains(x, y))) {
          continue;
        }
        var id = nodeId(column, row);
        nodes[id] = LayoutNode(id, x, y, charging: row == 0 && charging.contains(column));
      }
    }
    var neighbours = <String, List<String>>{};
    for (var row = 0; row < source.rows; row++) {
      for (var column = 0; column < source.columns; column++) {
        var id = nodeId(column, row);
        if (!nodes.containsKey(id)) {
          continue;
        }
        neighbours[id] = [
          for (var (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)])
            if (nodes.containsKey(nodeId(column + dc, row + dr))) nodeId(column + dc, row + dr)
        ];
      }
    }
    return FleetLayout._(source.mapId, nodes, neighbours, zoneSet);
  }

  static String nodeId(int column, int row) => 'N$column-$row';

  // charging stations take the first and last column of row 0, then the ones between
  static Set<int> _chargingColumns(Vda5050Source source) {
    var count = min(source.chargingStations, source.columns);
    var columns = <int>[];
    for (var i = 0; columns.length < count; i++) {
      var column = i.isEven ? i ~/ 2 : source.columns - 1 - i ~/ 2;
      if (!columns.contains(column)) {
        columns.add(column);
      }
    }
    return columns.toSet();
  }

  static VdaZoneSet _zones(Vda5050Source source) {
    var s = source.spacing;
    VdaZone square(String id, String type, double cx, double cy, double half, Map<String, Object?> parameters,
            String descriptor) =>
        VdaZone(
          zoneId: id,
          zoneType: type,
          descriptor: descriptor,
          vertices: [
            VdaPoint(cx - half, cy - half),
            VdaPoint(cx + half, cy - half),
            VdaPoint(cx + half, cy + half),
            VdaPoint(cx - half, cy + half),
          ],
          parameters: parameters,
        );
    var top = (source.rows - 1) * s;
    var right = (source.columns - 1) * s;
    return VdaZoneSet(zoneSetId: zoneSetId, mapId: source.mapId, descriptor: 'MQTT Studio simulation', zones: [
      square('blocked-1', VdaZoneType.blocked, (source.columns ~/ 2) * s, (source.rows ~/ 2) * s, s * 0.4, {},
          'Blocked area'),
      VdaZone(
        zoneId: 'speed-1',
        zoneType: VdaZoneType.speedLimit,
        descriptor: 'Slow lane',
        vertices: [VdaPoint(-s / 2, top - s / 2), VdaPoint(right + s / 2, top - s / 2), VdaPoint(right + s / 2, top + s / 2), VdaPoint(-s / 2, top + s / 2)],
        parameters: {'maximumSpeed': _round(source.speed / 2)},
      ),
      square('release-1', VdaZoneType.release, right, s, s * 0.6, {'releaseLossBehavior': 'STOP'}, 'Release needed'),
    ]);
  }

  static double _round(double value) => (value * 1000).roundToDouble() / 1000;

  LayoutNode operator [](String id) => nodes[id]!;

  List<VdaZone> zonesOfType(String type) => zoneSet?.zones.where((zone) => zone.zoneType == type).toList() ?? [];

  VdaZone? releaseZoneAt(double x, double y) =>
      zonesOfType(VdaZoneType.release).where((zone) => zone.contains(x, y)).firstOrNull;

  // the slowest speed limit at the point, null outside speed limit zones
  double? speedLimitAt(double x, double y) {
    double? limit;
    for (var zone in zonesOfType(VdaZoneType.speedLimit)) {
      var maximum = zone.parameters['maximumSpeed'];
      if (maximum is num && zone.contains(x, y)) {
        limit = limit == null ? maximum.toDouble() : min(limit, maximum.toDouble());
      }
    }
    return limit;
  }

  // the shortest path from one node to another without the blocked nodes, both ends included; null if there is none
  List<String>? route(String from, String to, {Set<String> blocked = const {}}) {
    if (from == to) {
      return [from];
    }
    var previous = <String, String>{};
    var queue = Queue<String>()..add(from);
    var seen = {from};
    while (queue.isNotEmpty) {
      var node = queue.removeFirst();
      for (var next in neighbours[node] ?? const <String>[]) {
        if (seen.contains(next) || (blocked.contains(next) && next != to)) {
          continue;
        }
        seen.add(next);
        previous[next] = node;
        if (next == to) {
          var path = [to];
          while (path.last != from) {
            path.add(previous[path.last]!);
          }
          return path.reversed.toList();
        }
        queue.add(next);
      }
    }
    return null;
  }
}
