import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/simulator/sparkplug/simulated_edge_node.dart';
import 'package:mqttstudio/simulator/sparkplug/sparkplug_fault.dart';

// The Faults menu of a simulated edge node in two columns: session events on the left, protocol faults on the right
// (doc/sparkplug-design.md §10.5), laid out like the robots' RobotFaultMenu. Toggled faults that are on show a check
// mark. Selecting an item closes the menu with its fault.
class SparkplugFaultMenu extends PopupMenuEntry<SparkplugFault> {
  static const double itemHeight = 36;
  static const double columnWidth = 260;
  // two columns and the divider between them; the popup has to be given this width
  static const double width = 2 * columnWidth + 1;

  final SimulatedEdgeNode node;

  const SparkplugFaultMenu({Key? key, required this.node}) : super(key: key);

  @override
  double get height => itemHeight * 9;

  @override
  bool represents(SparkplugFault? value) => false;

  @override
  State<SparkplugFaultMenu> createState() => _SparkplugFaultMenuState();
}

class _SparkplugFaultMenuState extends State<SparkplugFaultMenu> {
  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildColumn(context, SparkplugFaultGroup.session),
          VerticalDivider(width: 1),
          _buildColumn(context, SparkplugFaultGroup.protocol),
        ],
      ),
    );
  }

  Widget _buildColumn(BuildContext context, SparkplugFaultGroup group) {
    var theme = Theme.of(context);
    return SizedBox(
      width: SparkplugFaultMenu.columnWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 28,
            padding: EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.bottomLeft,
            child: Text(
              'sparkplugsim.faultgroup.${group.name}'.tr(),
              style: theme.textTheme.labelLarge!.copyWith(color: theme.hintColor),
            ),
          ),
          for (var fault in SparkplugFault.values.where((fault) => fault.group == group)) _buildItem(context, fault),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, SparkplugFault fault) {
    var theme = Theme.of(context);
    var enabled = widget.node.isFaultAvailable(fault);
    var active = fault.toggle && widget.node.isFaultActive(fault);
    var rule = fault.rule;
    return Tooltip(
      message: rule == null
          ? 'sparkplugsim.fault.norule.tooltip'.tr()
          : 'sparkplugsim.fault.rule.tooltip'.tr(args: [rule]),
      child: InkWell(
        onTap: enabled ? () => Navigator.of(context).pop(fault) : null,
        child: Container(
          height: SparkplugFaultMenu.itemHeight,
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(width: 28, child: active ? Icon(Icons.check, size: 18) : null),
              Expanded(
                child: Text(
                  'sparkplugsim.fault.${fault.name}'.tr(),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium!.copyWith(color: enabled ? null : theme.disabledColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
