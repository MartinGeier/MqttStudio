import 'dart:math';
import 'dart:ui' as ui;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/protocol/vda5050/fleet_state.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';

// Status colors of robots and zones from the theme, no new tokens (doc/vda5050-design.md V11)
class FleetStyle {
  static Color colorOf(BuildContext context, VehicleStatus status) {
    var theme = Theme.of(context);
    return switch (status) {
      VehicleStatus.offline || VehicleStatus.connectionBroken => theme.custom.disconnectedColor,
      VehicleStatus.error => theme.colorScheme.error,
      VehicleStatus.warning => theme.custom.warning,
      VehicleStatus.driving => theme.custom.connectedColor,
      VehicleStatus.hibernating || VehicleStatus.idle || VehicleStatus.unknown => theme.custom.watermark,
    };
  }

  // V11: ONLINE green, OFFLINE and a broken connection red, hibernating and no connection message grey
  static Color connectionColorOf(BuildContext context, String? connectionState) {
    var custom = Theme.of(context).custom;
    return switch (connectionState) {
      VdaConnectionState.online => custom.connectedColor,
      VdaConnectionState.offline || VdaConnectionState.connectionBroken => custom.disconnectedColor,
      _ => custom.watermark,
    };
  }

  static Color zoneColorOf(BuildContext context, String zoneType) {
    var theme = Theme.of(context);
    return switch (zoneType) {
      VdaZoneType.blocked => theme.colorScheme.error,
      VdaZoneType.speedLimit => theme.custom.warning,
      _ => theme.colorScheme.primary,
    };
  }
}

// One map of the fleet in meters (doc/vda5050-design.md §8, V8): grid, zones, the robots, and only for the selected
// robot its trail, order and paths, so the lines stay readable. Pan by dragging, zoom with the wheel; it fits everything
// until the user moves it.
class FleetCanvas<M> extends StatefulWidget {
  final FleetState<M> fleet;
  final String mapId;
  final String? selectedRobot;
  final bool showZones;
  final bool showLegend;
  final void Function(VehicleState<M> vehicle) onSelect;

  const FleetCanvas({
    Key? key,
    required this.fleet,
    required this.mapId,
    required this.selectedRobot,
    required this.showZones,
    this.showLegend = true,
    required this.onSelect,
  }) : super(key: key);

  @override
  State<FleetCanvas<M>> createState() => FleetCanvasState<M>();
}

class FleetCanvasState<M> extends State<FleetCanvas<M>> {
  // with its margin to the edge
  static const double legendWidth = 230;
  // meters at the center of the canvas and pixels per meter; null while the canvas fits itself
  Offset? _center;
  double? _scale;
  double _startScale = 1;
  Size _size = Size.zero;

  // fits all robots, order nodes and zones of the map again, and keeps fitting
  void fit() => setState(() {
    _center = null;
    _scale = null;
  });

  @override
  void didUpdateWidget(covariant FleetCanvas<M> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mapId != widget.mapId || oldWidget.showLegend != widget.showLegend) {
      _center = null;
      _scale = null;
    }
  }

  (Offset, double) _view(Size size) {
    if (_center != null && _scale != null) {
      return (_center!, _scale!);
    }
    var bounds = widget.fleet.boundsOf(widget.mapId) ?? Rectangle<double>(-5, -5, 10, 10);
    // at least 10 m, and a margin so robots at the edge stay whole
    var width = max(bounds.width, 10.0) + 4;
    var height = max(bounds.height, 10.0) + 4;
    // a wide map fits the robots left of the legend; in a narrow one that leaves too little, the legend can be hidden
    var legend = widget.showLegend && size.width >= 3 * legendWidth ? legendWidth : 0.0;
    var scale = min((size.width - legend) / width, size.height / height);
    scale = scale.isFinite && scale > 0 ? scale : 20;
    var center = Offset(bounds.left + bounds.width / 2 + legend / 2 / scale, bounds.top + bounds.height / 2);
    return (center, scale);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        var (center, scale) = _view(_size);
        var theme = Theme.of(context);
        var painter = FleetPainter<M>(
          fleet: widget.fleet,
          mapId: widget.mapId,
          selectedRobot: widget.selectedRobot,
          showZones: widget.showZones,
          center: center,
          scale: scale,
          colors: FleetPainterColors.of(context),
          labelStyle: theme.textTheme.labelSmall!,
          gridLabel: (step) => 'fleetview.grid.label'.tr(args: [_formatMeters(step)]),
        );
        return ClipRect(
          child: Listener(
            onPointerSignal: (event) => _onPointerSignal(event, center, scale),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => _onTap(painter, details.localPosition),
              onScaleStart: (_) {
                _center = center;
                _scale = scale;
                _startScale = scale;
              },
              onScaleUpdate: (details) => setState(() {
                _scale = (_startScale * details.scale).clamp(0.5, 2000.0);
                _center = _center! - Offset(details.focalPointDelta.dx, -details.focalPointDelta.dy) / _scale!;
              }),
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: painter)),
                  if (widget.showLegend) Positioned(right: 12, bottom: 12, child: FleetLegend()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _formatMeters(double step) => step >= 1 ? step.toStringAsFixed(0) : step.toString();

  // the wheel zooms around the pointer
  void _onPointerSignal(PointerSignalEvent event, Offset center, double scale) {
    if (event is! PointerScrollEvent) {
      return;
    }
    var factor = exp(-event.scrollDelta.dy / 400);
    var newScale = (scale * factor).clamp(0.5, 2000.0);
    var pointer = FleetPainter.toWorld(event.localPosition, _size, center, scale);
    setState(() {
      _scale = newScale;
      // the point under the pointer stays where it is
      _center = pointer - (pointer - center) * (scale / newScale);
    });
  }

  void _onTap(FleetPainter<M> painter, Offset position) {
    var vehicle = painter.robotAt(position, _size);
    if (vehicle != null) {
      widget.onSelect(vehicle);
    }
  }
}

// the kinds of lines on the map, drawn the same in the legend
enum FleetLine { trail, order, horizon, plannedPath, intermediatePath }

// a node of the selected robot's order
enum FleetNode { reached, ahead, horizon }

class FleetPainterColors {
  final Color grid;
  final Color label;
  final Color hint;
  final Color order;
  final Color selection;
  final Color outline;
  final Color Function(VehicleStatus status) statusOf;
  final Color Function(String zoneType) zoneOf;

  static FleetPainterColors of(BuildContext context) {
    var theme = Theme.of(context);
    return FleetPainterColors(
      grid: theme.dividerColor,
      label: theme.textTheme.bodySmall!.color ?? Colors.black87,
      hint: theme.hintColor,
      order: theme.colorScheme.primary,
      selection: theme.colorScheme.secondary,
      outline: Colors.black54,
      statusOf: (status) => FleetStyle.colorOf(context, status),
      zoneOf: (type) => FleetStyle.zoneColorOf(context, type),
    );
  }

  const FleetPainterColors({
    required this.grid,
    required this.label,
    required this.hint,
    required this.order,
    required this.selection,
    required this.outline,
    required this.statusOf,
    required this.zoneOf,
  });
}

class FleetPainter<M> extends CustomPainter {
  // a robot is drawn this long in meters, but never smaller than minRobotSize pixels
  static const double robotLength = 0.8;
  static const double minRobotSize = 14;
  static const List<double> gridSteps = [0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500];

  final FleetState<M> fleet;
  final String mapId;
  final String? selectedRobot;
  final bool showZones;
  final Offset center;
  final double scale;
  final FleetPainterColors colors;
  final TextStyle labelStyle;
  final String Function(double step) gridLabel;

  FleetPainter({
    required this.fleet,
    required this.mapId,
    required this.selectedRobot,
    required this.showZones,
    required this.center,
    required this.scale,
    required this.colors,
    required this.labelStyle,
    required this.gridLabel,
  });

  // VDA 5050 maps have y pointing up
  static Offset toScreen(double x, double y, Size size, Offset center, double scale) =>
      Offset(size.width / 2 + (x - center.dx) * scale, size.height / 2 - (y - center.dy) * scale);

  static Offset toWorld(Offset position, Size size, Offset center, double scale) =>
      Offset(center.dx + (position.dx - size.width / 2) / scale, center.dy - (position.dy - size.height / 2) / scale);

  Offset _screen(Size size, double x, double y) => toScreen(x, y, size, center, scale);

  double get _robotSize => max(robotLength * scale, minRobotSize);

  List<VehicleState<M>> get _onMap => fleet.vehicles.where((vehicle) => vehicle.position?.mapId == mapId).toList();

  VehicleState<M>? robotAt(Offset position, Size size) {
    VehicleState<M>? nearest;
    var nearestDistance = max(_robotSize, 16.0);
    for (var vehicle in _onMap) {
      var robot = vehicle.position!;
      var distance = (_screen(size, robot.x, robot.y) - position).distance;
      if (distance <= nearestDistance) {
        nearest = vehicle;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    if (showZones) {
      for (var zoneSet in fleet.zoneSetsOf(mapId)) {
        for (var zone in zoneSet.zones) {
          _paintZone(canvas, size, zone);
        }
      }
    }
    var vehicles = _onMap;
    var selected = selectedRobot == null ? null : fleet.vehicle(selectedRobot!);
    if (selected != null) {
      _paintTrail(canvas, size, selected);
      _paintOrder(canvas, size, selected);
      if (selected.position?.mapId == mapId) {
        _paintPaths(canvas, size, selected);
      }
    }
    for (var vehicle in vehicles) {
      _paintRobot(canvas, size, vehicle, vehicle.deviceKey == selectedRobot);
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    var step = gridSteps.firstWhere((step) => step * scale >= 40, orElse: () => gridSteps.last);
    var paint = Paint()
      ..color = colors.grid
      ..strokeWidth = 1;
    var topLeft = toWorld(Offset.zero, size, center, scale);
    var bottomRight = toWorld(Offset(size.width, size.height), size, center, scale);
    for (var x = (topLeft.dx / step).floor() * step; x <= bottomRight.dx; x += step) {
      var screenX = _screen(size, x, 0).dx;
      canvas.drawLine(Offset(screenX, 0), Offset(screenX, size.height), paint);
    }
    for (var y = (bottomRight.dy / step).floor() * step; y <= topLeft.dy; y += step) {
      var screenY = _screen(size, 0, y).dy;
      canvas.drawLine(Offset(0, screenY), Offset(size.width, screenY), paint);
    }
    _paintText(canvas, gridLabel(step), Offset(8, size.height - 20), colors.hint);
  }

  void _paintZone(Canvas canvas, Size size, VdaZone zone) {
    if (zone.vertices.length < 3) {
      return;
    }
    var path = Path()..addPolygon([for (var vertex in zone.vertices) _screen(size, vertex.x, vertex.y)], true);
    var color = colors.zoneOf(zone.zoneType);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    var bounds = path.getBounds();
    _paintText(canvas, '${zone.zoneId} · ${zone.zoneType}', bounds.topLeft + Offset(4, 4), color);
  }

  void _paintTrail(Canvas canvas, Size size, VehicleState<M> vehicle) {
    drawLine(canvas, FleetLine.trail, [
      for (var point in vehicle.trail)
        if (point.mapId == mapId) _screen(size, point.x, point.y),
    ], colors);
  }

  // the robot's last order: base edges solid, horizon edges dashed, reached nodes filled
  void _paintOrder(Canvas canvas, Size size, VehicleState<M> vehicle) {
    var order = vehicle.order;
    if (order == null) {
      return;
    }
    var nodes = order.nodes.where((node) => node.position?.mapId == mapId).toList()
      ..sort((a, b) => a.sequenceId.compareTo(b.sequenceId));
    var edges = {for (var edge in order.edges) edge.sequenceId: edge};
    var reached = vehicle.state?.orderId == order.orderId ? vehicle.state!.lastNodeSequenceId : -1;
    for (var i = 0; i + 1 < nodes.length; i++) {
      var from = _screen(size, nodes[i].position!.x, nodes[i].position!.y);
      var to = _screen(size, nodes[i + 1].position!.x, nodes[i + 1].position!.y);
      var released = edges[nodes[i].sequenceId + 1]?.released ?? nodes[i + 1].released;
      drawLine(canvas, released ? FleetLine.order : FleetLine.horizon, [from, to], colors);
    }
    for (var node in nodes) {
      var kind = !node.released
          ? FleetNode.horizon
          : node.sequenceId <= reached
          ? FleetNode.reached
          : FleetNode.ahead;
      drawNode(canvas, _screen(size, node.position!.x, node.position!.y), kind, colors);
    }
  }

  // 3.0: the planned path dotted, the intermediate path thin
  void _paintPaths(Canvas canvas, Size size, VehicleState<M> vehicle) {
    var planned = vehicle.plannedPath;
    if (planned != null) {
      drawLine(canvas, FleetLine.plannedPath, [
        for (var point in planned.controlPoints) _screen(size, point.x, point.y),
      ], colors);
    }
    var intermediate = vehicle.intermediatePath;
    if (intermediate != null) {
      drawLine(canvas, FleetLine.intermediatePath, [
        for (var point in intermediate.polyline) _screen(size, point.x, point.y),
      ], colors);
    }
  }

  void _paintRobot(Canvas canvas, Size size, VehicleState<M> vehicle, bool selected) {
    var position = vehicle.position!;
    var at = _screen(size, position.x, position.y);
    var length = _robotSize;
    if (selected) {
      canvas.drawCircle(
        at,
        length * 0.75,
        Paint()
          ..color = colors.selection
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    // screen angles turn the other way, y points down
    drawRobot(canvas, at, length, -position.theta, vehicle.status, colors);
    _paintText(canvas, vehicle.serialNumber, at + Offset(length / 2 + 4, -6), colors.label);
  }

  // the trail is where the robot drove, the order where it is sent, the paths (3.0) where it plans to drive
  static void drawLine(Canvas canvas, FleetLine line, List<Offset> points, FleetPainterColors colors) {
    if (points.length < 2) {
      return;
    }
    var paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    switch (line) {
      case FleetLine.trail:
        paint
          ..color = colors.hint
          ..strokeWidth = 1.5;
        canvas.drawPoints(ui.PointMode.polygon, points, paint);
      case FleetLine.order:
        paint
          ..color = colors.order
          ..strokeWidth = 3;
        canvas.drawPoints(ui.PointMode.polygon, points, paint);
      case FleetLine.horizon:
        paint
          ..color = colors.order
          ..strokeWidth = 2;
        _dashed(canvas, points, paint, 6, 4);
      case FleetLine.plannedPath:
        paint
          ..color = colors.selection
          ..strokeWidth = 2.5;
        _dashed(canvas, points, paint, 0.5, 5);
      case FleetLine.intermediatePath:
        paint
          ..color = colors.selection
          ..strokeWidth = 1.5;
        canvas.drawPoints(ui.PointMode.polygon, points, paint);
    }
  }

  static void drawNode(Canvas canvas, Offset at, FleetNode node, FleetPainterColors colors) {
    var color = node == FleetNode.horizon ? colors.hint : colors.order;
    canvas.drawCircle(at, 4, Paint()..color = node == FleetNode.reached ? color : Colors.white);
    canvas.drawCircle(
      at,
      4,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  // a triangle pointing along angle (radians, counterclockwise on screen); a robot that isn't connected is only an
  // outline, so it doesn't look like one that reports an error
  static void drawRobot(
    Canvas canvas,
    Offset at,
    double length,
    double angle,
    VehicleStatus status,
    FleetPainterColors colors,
  ) {
    Offset corner(double along, double across) =>
        at + Offset(cos(angle) * along - sin(angle) * across, sin(angle) * along + cos(angle) * across);
    var triangle = Path()
      ..addPolygon([corner(length / 2, 0), corner(-length / 2, length / 3), corner(-length / 2, -length / 3)], true);
    var color = colors.statusOf(status);
    if (status == VehicleStatus.offline || status == VehicleStatus.connectionBroken) {
      canvas.drawPath(triangle, Paint()..color = Colors.white);
      canvas.drawPath(
        triangle,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      return;
    }
    canvas.drawPath(triangle, Paint()..color = color);
    canvas.drawPath(
      triangle,
      Paint()
        ..color = colors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  static void _dashed(Canvas canvas, List<Offset> points, Paint paint, double dash, double gap) {
    for (var i = 0; i + 1 < points.length; i++) {
      var from = points[i];
      var delta = points[i + 1] - from;
      var length = delta.distance;
      if (length == 0) {
        continue;
      }
      var direction = delta / length;
      for (var start = 0.0; start < length; start += dash + gap) {
        canvas.drawLine(from + direction * start, from + direction * min(start + dash, length), paint);
      }
    }
  }

  void _paintText(Canvas canvas, String text, Offset at, Color color) {
    var painter = TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(color: color),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  // repaints on every rebuild; the view model notifies at most twice a second
  @override
  bool shouldRepaint(covariant FleetPainter<M> oldDelegate) => true;
}

// What the robots' colors and the selected robot's lines mean, in the corner of the map
class FleetLegend extends StatelessWidget {
  const FleetLegend({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var colors = FleetPainterColors.of(context);
    var style = theme.textTheme.labelSmall;
    Widget row(void Function(Canvas canvas, Size size) paint, String key) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 32, height: 14, child: CustomPaint(painter: _SamplePainter(paint))),
          SizedBox(width: 8),
          Text('fleetview.legend.$key'.tr(), style: style),
        ],
      ),
    );
    Widget robot(VehicleStatus status, String key) =>
        row((canvas, size) => FleetPainter.drawRobot(canvas, size.center(Offset.zero), 12, 0, status, colors), key);
    Widget line(FleetLine kind, String key) => row(
      (canvas, size) => FleetPainter.drawLine(canvas, kind, [Offset(2, 7), Offset(size.width - 2, 7)], colors),
      key,
    );
    Widget node(FleetNode kind, String key) =>
        row((canvas, size) => FleetPainter.drawNode(canvas, size.center(Offset.zero), kind, colors), key);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.canvasColor.withValues(alpha: 0.9),
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          robot(VehicleStatus.driving, 'driving'),
          robot(VehicleStatus.idle, 'standing'),
          robot(VehicleStatus.warning, 'warning'),
          robot(VehicleStatus.error, 'error'),
          robot(VehicleStatus.offline, 'offline'),
          SizedBox(height: 4),
          Text('fleetview.legend.selected'.tr(), style: style!.copyWith(color: theme.hintColor)),
          line(FleetLine.trail, 'trail'),
          line(FleetLine.order, 'order'),
          line(FleetLine.horizon, 'horizon'),
          node(FleetNode.reached, 'reached'),
          node(FleetNode.ahead, 'ahead'),
          line(FleetLine.plannedPath, 'plannedpath'),
          line(FleetLine.intermediatePath, 'intermediatepath'),
        ],
      ),
    );
  }
}

class _SamplePainter extends CustomPainter {
  final void Function(Canvas canvas, Size size) sample;

  _SamplePainter(this.sample);

  @override
  void paint(Canvas canvas, Size size) => sample(canvas, size);

  @override
  bool shouldRepaint(covariant _SamplePainter oldDelegate) => false;
}
