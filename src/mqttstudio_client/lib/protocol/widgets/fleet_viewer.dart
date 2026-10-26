import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/protocol/vda5050/fleet_state.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/protocol/widgets/fleet_canvas.dart';
import 'package:provider/provider.dart';

// The Fleet view mode of the topic viewer (doc/vda5050-design.md §8): every VDA 5050 robot in a table and on its map.
// A robot is selected through its last state, so the detail view shows it.
class FleetViewer extends StatefulWidget {
  // the table takes the width of its columns, at most this share of the view; the map gets the rest
  static const double maxTableShare = 0.55;

  const FleetViewer({Key? key}) : super(key: key);

  @override
  State<FleetViewer> createState() => _FleetViewerState();
}

class _FleetViewerState extends State<FleetViewer> {
  final _canvasKey = GlobalKey<FleetCanvasState<ReceivedMqttMessage>>();
  final _tableScroll = ScrollController();
  final _tableHorizontalScroll = ScrollController();

  @override
  void dispose() {
    _tableScroll.dispose();
    _tableHorizontalScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var viewmodel = context.watch<MessageViewerViewmodel>();
    var fleet = viewmodel.fleet;
    if (fleet.isEmpty) {
      return Expanded(
        child: Center(
          child: Text(
            'fleetview.empty'.tr(),
            style: Theme.of(context).textTheme.titleMedium!.copyWith(color: Theme.of(context).hintColor),
          ),
        ),
      );
    }
    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * FleetViewer.maxTableShare),
              child: _buildTable(context, viewmodel),
            ),
            VerticalDivider(width: 1),
            Expanded(child: _buildMap(context, viewmodel, fleet)),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(BuildContext context, MessageViewerViewmodel viewmodel) {
    var theme = Theme.of(context);
    var now = viewmodel.statsReference;
    var selected = viewmodel.selectedRobot;
    var vehicles = viewmodel.sortedVehicles;
    // robots of one manufacturer are told apart by their serial numbers, the table stays narrow
    var oneManufacturer = vehicles.map((vehicle) => vehicle.manufacturer).toSet().length == 1;
    var columns = [
      for (var column in FleetColumn.values)
        DataColumn(
          label: Text('fleetview.column.${column.name}'.tr()),
          numeric: column == FleetColumn.charge || column == FleetColumn.age,
          onSort: (_, ascending) => viewmodel.sortFleet(column, ascending),
        ),
    ];
    // in a narrow view the last columns lie outside, the horizontal scrollbar shows that
    return Scrollbar(
      controller: _tableHorizontalScroll,
      thumbVisibility: true,
      notificationPredicate: (notification) => notification.depth == 1,
      child: Scrollbar(
        controller: _tableScroll,
        child: SingleChildScrollView(
          controller: _tableScroll,
          child: SingleChildScrollView(
            controller: _tableHorizontalScroll,
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              sortColumnIndex: viewmodel.fleetSortColumn.index,
              sortAscending: viewmodel.fleetSortAscending,
              headingRowHeight: 36,
              dataRowMinHeight: 28,
              dataRowMaxHeight: 32,
              horizontalMargin: 12,
              columnSpacing: 12,
              headingTextStyle: theme.textTheme.labelLarge!.copyWith(color: theme.hintColor),
              columns: columns,
              rows: [
                for (var vehicle in vehicles)
                  DataRow(
                    selected: vehicle.deviceKey == selected,
                    onSelectChanged: (_) => viewmodel.selectRobot(vehicle),
                    cells: [
                      for (var column in FleetColumn.values)
                        DataCell(_buildCell(context, vehicle, column, now, oneManufacturer)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCell(
    BuildContext context,
    VehicleState<ReceivedMqttMessage> vehicle,
    FleetColumn column,
    DateTime now,
    bool oneManufacturer,
  ) {
    var theme = Theme.of(context);
    var state = vehicle.state;
    var none = Text('—', style: TextStyle(color: theme.hintColor));
    switch (column) {
      case FleetColumn.robot:
        return Tooltip(
          message: vehicle.name,
          child: Text(
            oneManufacturer ? vehicle.serialNumber : vehicle.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      case FleetColumn.version:
        return Text(vehicle.version);
      case FleetColumn.connection:
        return _buildConnection(context, vehicle);
      case FleetColumn.mode:
        return state == null ? none : Text(state.operatingMode);
      case FleetColumn.driving:
        return state == null ? none : _buildDriving(context, vehicle, state);
      case FleetColumn.charge:
        return state == null ? none : _buildCharge(context, state.powerSupply);
      case FleetColumn.order:
        return state == null || state.orderId.isEmpty
            ? Text(state?.lastNodeId ?? '')
            : Text('${state.orderId}#${state.orderUpdateId} · ${state.lastNodeId}');
      case FleetColumn.errors:
        return _buildErrors(context, vehicle);
      case FleetColumn.requests:
        return vehicle.openRequests == 0 ? Text('') : Text('${vehicle.openRequests}');
      case FleetColumn.age:
        var age = vehicle.stateAge(now);
        return age == null
            ? none
            : Text(_formatAge(age), style: TextStyle(color: vehicle.isStale(now) ? theme.hintColor : null));
    }
  }

  // a dot in the color of the connection state; the state is written out only when it isn't ONLINE, to save space
  Widget _buildConnection(BuildContext context, VehicleState<ReceivedMqttMessage> vehicle) {
    var state = vehicle.connectionState;
    return Tooltip(
      message: state ?? 'fleetview.noconnection.tooltip'.tr(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusDot(color: FleetStyle.connectionColorOf(context, state)),
          if (state != null && state != VdaConnectionState.online) ...[SizedBox(width: 6), Text(state)],
        ],
      ),
    );
  }

  Widget _buildDriving(BuildContext context, VehicleState<ReceivedMqttMessage> vehicle, VdaState state) {
    var theme = Theme.of(context);
    var (icon, key) = state.paused == true
        ? (Icons.pause, 'fleetview.paused.tooltip')
        : state.driving
        ? (Icons.play_arrow, 'fleetview.driving.tooltip')
        : (Icons.stop, 'fleetview.standing.tooltip');
    return Tooltip(
      message: key.tr(),
      child: Icon(
        icon,
        size: 18,
        color: state.driving && state.paused != true ? theme.custom.connectedColor : theme.hintColor,
      ),
    );
  }

  Widget _buildCharge(BuildContext context, VdaPowerSupply power) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (power.charging)
          Tooltip(
            message: 'fleetview.charging.tooltip'.tr(),
            child: Icon(Icons.bolt, size: 16, color: Theme.of(context).custom.connectedColor),
          ),
        Text('${power.stateOfCharge.round()} %'),
      ],
    );
  }

  Widget _buildErrors(BuildContext context, VehicleState<ReceivedMqttMessage> vehicle) {
    var level = vehicle.highestErrorLevel;
    if (level == null) {
      return Text('');
    }
    var error = VehicleState.isErrorLevel(level);
    var theme = Theme.of(context);
    var color = error ? theme.colorScheme.error : theme.custom.warning;
    return Tooltip(
      message: level,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(error ? Icons.error : Icons.warning_amber, size: 16, color: color),
          SizedBox(width: 4),
          Text('${vehicle.state!.errors.length}', style: TextStyle(color: color)),
        ],
      ),
    );
  }

  static String _formatAge(Duration age) {
    if (age.inSeconds < 60) {
      return '${age.inSeconds} s';
    }
    if (age.inMinutes < 60) {
      return '${age.inMinutes} min';
    }
    return '${age.inHours} h';
  }

  Widget _buildMap(BuildContext context, MessageViewerViewmodel viewmodel, FleetState<ReceivedMqttMessage> fleet) {
    var mapId = viewmodel.fleetMap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMapBar(context, viewmodel, fleet, mapId),
        Divider(height: 1),
        Expanded(
          child: mapId == null
              ? Center(
                  child: Text('fleetview.nomap'.tr(), style: TextStyle(color: Theme.of(context).hintColor)),
                )
              : FleetCanvas<ReceivedMqttMessage>(
                  key: _canvasKey,
                  fleet: fleet,
                  mapId: mapId,
                  selectedRobot: viewmodel.selectedRobot,
                  showZones: viewmodel.showZones,
                  showLegend: viewmodel.showFleetLegend,
                  onSelect: viewmodel.selectRobot,
                ),
        ),
      ],
    );
  }

  Widget _buildMapBar(
    BuildContext context,
    MessageViewerViewmodel viewmodel,
    FleetState<ReceivedMqttMessage> fleet,
    String? mapId,
  ) {
    var maps = fleet.maps;
    var hasZones = mapId != null && fleet.zoneSetsOf(mapId).isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Text('fleetview.map.label'.tr(), style: Theme.of(context).textTheme.titleSmall),
          SizedBox(width: 8),
          // disabled controls say why: one map only, or no zone set received for it
          Tooltip(
            message: maps.length > 1 ? 'fleetview.map.tooltip'.tr() : 'fleetview.map.single.tooltip'.tr(),
            child: DropdownButton<String>(
              isDense: true,
              value: mapId,
              onChanged: maps.length > 1 ? (value) => viewmodel.fleetMap = value : null,
              items: [for (var map in maps) DropdownMenuItem(value: map, child: Text(map))],
            ),
          ),
          SizedBox(width: 16),
          Tooltip(
            message: hasZones ? 'fleetview.zones.tooltip'.tr() : 'fleetview.zones.none.tooltip'.tr(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: hasZones && viewmodel.showZones,
                  onChanged: hasZones ? (value) => viewmodel.showZones = value ?? true : null,
                ),
                Text('fleetview.zones.label'.tr()),
              ],
            ),
          ),
          Spacer(),
          IconButton(
            tooltip: viewmodel.showFleetLegend
                ? 'fleetview.legend.hide.tooltip'.tr()
                : 'fleetview.legend.show.tooltip'.tr(),
            isSelected: viewmodel.showFleetLegend,
            onPressed: mapId == null ? null : () => viewmodel.showFleetLegend = !viewmodel.showFleetLegend,
            icon: Icon(Icons.legend_toggle),
          ),
          IconButton(
            tooltip: 'fleetview.fit.tooltip'.tr(),
            onPressed: mapId == null ? null : () => _canvasKey.currentState?.fit(),
            icon: Icon(Icons.fit_screen),
          ),
        ],
      ),
    );
  }
}

// a status color with an outline, the light grey of idle robots stays visible
class _StatusDot extends StatelessWidget {
  final Color color;

  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).hintColor),
      ),
    );
  }
}
