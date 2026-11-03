import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/simulator/vda5050/robot_fault.dart';
import 'package:mqttstudio/simulator/vda5050/simulated_fleet.dart';
import 'package:mqttstudio/simulator/vda5050/simulated_robot.dart';

// The Faults menu of a simulated robot in two columns: robot faults on the left, connection and protocol faults on
// the right (doc/vda5050-design.md §10.4). Toggled faults that are on show a check mark; all items keep the same
// indent. Selecting an item closes the menu with its fault.
class RobotFaultMenu extends PopupMenuEntry<RobotFault> {
  static const double itemHeight = 36;
  static const double columnWidth = 260;
  // two columns and the divider between them; the popup has to be given this width
  static const double width = 2 * columnWidth + 1;

  final SimulatedFleet fleet;
  final SimulatedRobot robot;

  const RobotFaultMenu({Key? key, required this.fleet, required this.robot}) : super(key: key);

  @override
  double get height => itemHeight * 13;

  @override
  bool represents(RobotFault? value) => false;

  @override
  State<RobotFaultMenu> createState() => _RobotFaultMenuState();
}

class _RobotFaultMenuState extends State<RobotFaultMenu> {
  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildColumn(context, [RobotFaultGroup.robot]),
        VerticalDivider(width: 1),
        _buildColumn(context, [RobotFaultGroup.connection, RobotFaultGroup.protocol]),
      ]),
    );
  }

  Widget _buildColumn(BuildContext context, List<RobotFaultGroup> groups) {
    var v3 = widget.fleet.source.version.isV3;
    return SizedBox(
      width: RobotFaultMenu.columnWidth,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var group in groups) ...[
          if (group != groups.first) Divider(height: 9),
          _buildHeader(context, group),
          for (var fault in RobotFault.values.where((fault) => fault.group == group))
            if (!fault.v3Only || v3) _buildItem(context, fault),
        ],
      ]),
    );
  }

  Widget _buildHeader(BuildContext context, RobotFaultGroup group) {
    var theme = Theme.of(context);
    return Container(
      height: 28,
      padding: EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.bottomLeft,
      child: Text('vda5050sim.faultgroup.${group.name}'.tr(),
          style: theme.textTheme.labelLarge!.copyWith(color: theme.hintColor)),
    );
  }

  Widget _buildItem(BuildContext context, RobotFault fault) {
    var theme = Theme.of(context);
    var enabled = widget.fleet.isFaultAvailable(widget.robot, fault);
    var active = fault.toggle && widget.fleet.isFaultActive(widget.robot, fault);
    return InkWell(
      onTap: enabled ? () => Navigator.of(context).pop(fault) : null,
      child: Container(
        height: RobotFaultMenu.itemHeight,
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          SizedBox(width: 28, child: active ? Icon(Icons.check, size: 18) : null),
          Expanded(
            child: Text('vda5050sim.fault.${fault.name}'.tr(),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium!.copyWith(color: enabled ? null : theme.disabledColor)),
          ),
        ]),
      ),
    );
  }
}
