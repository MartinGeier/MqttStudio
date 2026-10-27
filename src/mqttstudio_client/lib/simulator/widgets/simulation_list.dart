import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mqttstudio/common/widgets/fast_topic_chip.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/recorder/widgets/recorder_format.dart';
import 'package:mqttstudio/simulator/engine/generator_instances.dart';
import 'package:mqttstudio/simulator/engine/simulator_runner.dart';
import 'package:mqttstudio/simulator/engine/placeholders.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/simulator_viewmodel.dart';
import 'package:mqttstudio/simulator/sparkplug/simulated_edge_node.dart';
import 'package:mqttstudio/simulator/sparkplug/sparkplug_fault.dart';
import 'package:mqttstudio/simulator/widgets/sparkplug_fault_menu.dart';
import 'package:mqttstudio/simulator/widgets/simulator_dialogs.dart';
import 'package:mqttstudio/simulator/vda5050/robot_fault.dart';
import 'package:mqttstudio/simulator/vda5050/simulated_robot.dart';
import 'package:mqttstudio/simulator/widgets/robot_fault_menu.dart';
import 'package:mqttstudio/simulator/widgets/simulator_format.dart';
import 'package:provider/provider.dart';

// Column widths of the topic table, shared by the header and the rows
class _Columns {
  static const double status = 40;
  static const int topicFlex = 3;
  static const double generator = 150;
  static const double interval = 110;
  static const double qos = 110;
  static const double sent = 96;
  static const int payloadFlex = 2;
  static const double actions = 240;
  static const double indent = 60;
}

// The devices of the simulation with their topics, state and statistics
class SimulationList extends StatelessWidget {
  const SimulationList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<SimulatorViewmodel>();
    if (!vm.isProjectOpen) {
      return _buildWatermark(context, 'simulator.noproject.watermark'.tr());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kIsWeb) _buildWebHint(context),
        _buildHeader(context),
        Expanded(
          child: vm.devices.isEmpty
              ? _buildWatermark(context, 'simulator.nodevices.watermark'.tr())
              : ListView(children: [for (var device in vm.devices) ..._buildDevice(context, vm, device)]),
        ),
      ],
    );
  }

  Widget _buildWatermark(BuildContext context, String text) {
    var theme = Theme.of(context);
    return Center(child: Text(text, style: theme.textTheme.headlineMedium!.copyWith(color: theme.dividerColor)));
  }

  Widget _buildWebHint(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(4)),
      child: Row(children: [Icon(Icons.info), SizedBox(width: 12), Expanded(child: Text('simulator.webhint.label'.tr()))]),
    );
  }

  Widget _buildHeader(BuildContext context) {
    var style = Theme.of(context).textTheme.bodySmall;
    Widget label(String key, {TextAlign align = TextAlign.start}) => Text(key.tr(), style: style, textAlign: align);
    return Container(
      height: 36,
      padding: EdgeInsets.only(left: _Columns.indent, right: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))),
      child: Row(children: [
        SizedBox(width: _Columns.status),
        Expanded(flex: _Columns.topicFlex, child: label('simulator.column.topic')),
        SizedBox(width: _Columns.generator, child: label('simulator.column.generator')),
        SizedBox(width: _Columns.interval, child: label('simulator.column.interval')),
        SizedBox(width: _Columns.qos, child: label('simulator.column.qos')),
        SizedBox(width: _Columns.sent, child: label('simulator.column.sent', align: TextAlign.end)),
        SizedBox(width: 12),
        Expanded(flex: _Columns.payloadFlex, child: label('simulator.column.payload')),
        SizedBox(width: _Columns.actions),
      ]),
    );
  }

  List<Widget> _buildDevice(BuildContext context, SimulatorViewmodel vm, SimulatedDevice device) {
    if (device.isSparkplug) {
      var nodes = vm.sparkplugOf(device)?.nodes;
      return [
        _DeviceHeader(device: device),
        if (vm.isExpanded(device))
          if (nodes != null)
            for (var node in nodes) _EdgeNodeRow(device: device, node: node)
          else
            for (var n in device.instanceNumbers) _EdgeNodeRow(device: device, instance: n),
      ];
    }
    if (device.isVda5050) {
      var robots = vm.fleetOf(device)?.robots;
      return [
        _DeviceHeader(device: device),
        if (vm.isExpanded(device))
          if (robots != null)
            for (var robot in robots) _RobotRow(device: device, robot: robot)
          else
            for (var n in device.instanceNumbers) _RobotRow(device: device, instance: n),
      ];
    }
    if (device.isRecorded) {
      var topics = vm.recordedTopicsOf(device);
      return [
        _DeviceHeader(device: device),
        if (vm.isExpanded(device)) ...[
          if (topics.isEmpty) _buildNoTopics(context, 'simulator.recorded.notopics.label'),
          for (var topic in topics) _RecordedTopicRow(device: device, topic: topic),
        ],
      ];
    }
    return [
      _DeviceHeader(device: device),
      if (vm.isExpanded(device)) ...[
        if (device.topics.isEmpty) _buildNoTopics(context, 'simulator.notopics.label'),
        for (var topic in device.topics) _TopicRow(device: device, topic: topic),
      ],
    ];
  }

  Widget _buildNoTopics(BuildContext context, String key) {
    var theme = Theme.of(context);
    return Container(
      height: 48,
      padding: EdgeInsets.only(left: _Columns.indent + _Columns.status),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
      child: Text(key.tr(), style: theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor)),
    );
  }
}

class _DeviceHeader extends StatelessWidget {
  final SimulatedDevice device;

  const _DeviceHeader({required this.device});

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<SimulatorViewmodel>();
    var theme = Theme.of(context);
    var expanded = vm.isExpanded(device);
    var running = vm.runningCountOf(device);
    var selected = vm.selectedDeviceId == device.id;
    return Material(
      color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : theme.colorScheme.surface,
      child: InkWell(
        onTap: () => vm.selectDevice(device),
        child: Container(
          height: 56,
          padding: EdgeInsets.only(left: 4, right: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
          child: Row(children: [
            IconButton(
                onPressed: () => vm.toggleExpanded(device),
                icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
                tooltip: (expanded ? 'simulator.collapse.tooltip' : 'simulator.expand.tooltip').tr()),
            SizedBox(width: 8),
            if (!device.isGenerated)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tooltip(
                    message: 'simulator.${device.kind.name}.tooltip'.tr(),
                    child: Icon(
                        switch (device.kind) {
                          DeviceKind.recorded => Icons.history,
                          DeviceKind.sparkplug => Icons.hub,
                          _ => Icons.precision_manufacturing,
                        },
                        size: 20,
                        color: theme.unselectedWidgetColor)),
              ),
            Expanded(
              child: Row(children: [
                Flexible(child: Text(device.name, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
                SizedBox(width: 8),
                Chip(label: Text(SimulatorFormat.instances(device))),
                SizedBox(width: 8),
                Flexible(
                    child: Text(_caption(vm, running), style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
              ]),
            ),
            _buildActions(context, vm, running),
          ]),
        ),
      ),
    );
  }

  String _caption(SimulatorViewmodel vm, int running) {
    if (device.isRecorded) {
      return _recordedCaption(vm);
    }
    if (device.isVda5050) {
      return _vda5050Caption(vm);
    }
    if (device.isSparkplug) {
      return _sparkplugCaption(vm);
    }
    var total = device.topics.length;
    var errors = vm.errorCountOf(device);
    var stopped = total == 1 ? 'simulator.device.stopped.one'.tr() : 'simulator.device.stopped'.tr(args: ['$total']);
    var caption =
        running == 0 && errors == 0 ? stopped : 'simulator.running.label'.tr(args: ['$running', '$total']);
    return errors == 0 ? caption : '$caption · ${'simulator.device.errors'.tr(args: ['$errors'])}';
  }

  // Recorded · Line 1 · 2× · loop, or the position while playing, or why it stopped
  String _recordedCaption(SimulatorViewmodel vm) {
    var source = device.recorded;
    var stats = vm.deviceStatsOf(device);
    if (stats.issue != null) {
      return 'simulator.issue.${stats.issue!.name}'.tr(args: [stats.errorDetail]);
    }
    if (source == null) {
      return '';
    }
    var playback = source.playback;
    var parts = [
      'simulator.recorded.caption'.tr(args: [vm.recordingOf(device)?.name ?? source.recordingName]),
      RecorderFormat.speed(playback.speed),
      if (playback.loop) 'simulator.recorded.loop'.tr(),
    ];
    var position = vm.positionOf(device);
    var info = vm.recordingOf(device);
    if (vm.isRecordedRunning(device) && position != null) {
      parts.add(info == null
          ? RecorderFormat.clock(position)
          : '${RecorderFormat.clock(position)} / ${RecorderFormat.clock(info.footer.duration)}');
    } else if (info == null) {
      parts.add('simulator.recorded.missing'.tr());
    }
    return parts.join(' · ');
  }

  // VDA 5050 3.0 · vda5050/v3/MQTTStudio/SIM-{n}, or why it stopped
  String _vda5050Caption(SimulatorViewmodel vm) {
    var stats = vm.deviceStatsOf(device);
    if (stats.issue != null) {
      return 'simulator.issue.${stats.issue!.name}'.tr(args: [stats.errorDetail]);
    }
    var source = device.vda5050;
    if (source == null) {
      return '';
    }
    return [
      'VDA 5050 ${source.version.protocolVersion}',
      source.topicPrefix,
      if (vm.isRecordedRunning(device)) 'simulator.state.running'.tr(),
    ].join(' · ');
  }

  // Sparkplug B · spBv1.0/Plant1 · waits for host scada, or why it stopped
  String _sparkplugCaption(SimulatorViewmodel vm) {
    var stats = vm.deviceStatsOf(device);
    if (stats.issue != null) {
      return 'simulator.issue.${stats.issue!.name}'.tr(args: [stats.errorDetail]);
    }
    var source = device.sparkplug;
    if (source == null) {
      return '';
    }
    var host = source.primaryHostId;
    return [
      'Sparkplug B',
      'spBv1.0/${source.groupId}',
      if (host != null && host.isNotEmpty)
        (source.simulateHost ? 'sparkplugsim.hostsimulated.label' : 'sparkplugsim.hostwaits.label').tr(args: [host]),
      if (vm.isRecordedRunning(device)) 'simulator.state.running'.tr(),
    ].join(' · ');
  }

  Widget _buildActions(BuildContext context, SimulatorViewmodel vm, int running) {
    var canStartDevice = device.isGenerated ? running < device.topics.length : !vm.isRecordedRunning(device);
    var isRunning = device.isGenerated ? running > 0 : vm.isRecordedRunning(device);
    var subscription = vm.viewerSubscriptionOf(device);
    var subscribed = subscription != null && vm.isDeviceSubscribedInViewer(device);
    return Row(children: [
      if (subscription != null)
        IconButton(
            onPressed: subscribed ? null : () => vm.subscribeDeviceInViewer(device),
            icon: Icon(Icons.visibility),
            tooltip: subscribed
                ? 'simulator.subscribed.tooltip'.tr()
                : 'simulator.subscribe.tooltip'.tr(args: [subscription])),
      IconButton(
          onPressed: vm.canStart && canStartDevice ? () => vm.startDevice(device) : null,
          icon: Icon(Icons.play_arrow),
          color: Colors.green,
          tooltip: vm.isConnected ? 'simulator.startdevice.tooltip'.tr() : 'simulator.connectfirst.tooltip'.tr()),
      IconButton(
          onPressed: isRunning ? () => vm.stopDevice(device) : null,
          icon: Icon(Icons.stop),
          tooltip: 'simulator.stopdevice.tooltip'.tr()),
      IconButton(
          onPressed: () => SimulatorDialogs.editDevice(context, vm, device),
          icon: Icon(Icons.edit),
          tooltip: 'simulator.editdevice.tooltip'.tr()),
      IconButton(
          onPressed: () => vm.duplicateDevice(device),
          icon: Icon(Icons.copy),
          tooltip: 'simulator.duplicatedevice.tooltip'.tr()),
      IconButton(
          onPressed: () => SimulatorDialogs.deleteDevice(context, vm, device),
          icon: Icon(Icons.delete),
          tooltip: 'simulator.deletedevice.tooltip'.tr()),
    ]);
  }
}

class _TopicRow extends StatelessWidget {
  final SimulatedDevice device;
  final SimulatedTopic topic;

  const _TopicRow({required this.device, required this.topic});

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<SimulatorViewmodel>();
    var theme = Theme.of(context);
    var state = vm.stateOf(topic);
    var stats = vm.statsOf(topic);
    return Container(
      constraints: BoxConstraints(minHeight: 48),
      padding: EdgeInsets.only(left: _Columns.indent, right: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
      child: Row(children: [
        SizedBox(width: _Columns.status, child: _buildStatus(context, state)),
        Expanded(flex: _Columns.topicFlex, child: _buildTopic(context, vm)),
        SizedBox(width: _Columns.generator, child: Text(SimulatorFormat.generatorName(topic.generator.type))),
        SizedBox(width: _Columns.interval, child: Text(SimulatorFormat.interval(topic.interval))),
        SizedBox(width: _Columns.qos, child: Text(SimulatorFormat.qosAndRetain(topic))),
        SizedBox(
            width: _Columns.sent,
            child: Text(SimulatorFormat.count(stats.sent),
                textAlign: TextAlign.end, style: TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
        SizedBox(width: 12),
        Expanded(flex: _Columns.payloadFlex, child: _buildPayload(context, state, stats)),
        SizedBox(width: _Columns.actions, child: _buildActions(context, vm, state)),
      ]),
    );
  }

  Widget _buildStatus(BuildContext context, TopicRunState state) {
    var theme = Theme.of(context);
    switch (state) {
      case TopicRunState.running:
        return Tooltip(
            message: 'simulator.state.running'.tr(),
            child: Icon(Icons.play_arrow, size: 20, color: theme.custom.running));
      case TopicRunState.error:
        return Tooltip(
            message: 'simulator.state.error'.tr(), child: Icon(Icons.error, size: 20, color: theme.colorScheme.error));
      case TopicRunState.stopped:
        return Tooltip(
            message: 'simulator.state.stopped'.tr(),
            child: Icon(Icons.stop, size: 20, color: theme.unselectedWidgetColor));
    }
  }

  Widget _buildTopic(BuildContext context, SimulatorViewmodel vm) {
    var color = vm.viewerColorOf(device, topic);
    if (color != null) {
      return Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(right: 20),
            child: FastTopicChip(topic: topic.topic, topicColor: color, onPressed: null),
          ));
    }
    return Text(topic.topic, style: Theme.of(context).textTheme.titleSmall, overflow: TextOverflow.ellipsis);
  }

  Widget _buildPayload(BuildContext context, TopicRunState state, TopicStats stats) {
    var theme = Theme.of(context);
    if (state == TopicRunState.error) {
      return Text(_errorText(stats), overflow: TextOverflow.ellipsis, maxLines: 1);
    }
    if (stats.lastPayload == null) {
      return Text('–', style: TextStyle(color: theme.hintColor));
    }
    return Row(children: [
      Flexible(
          child: Text(stats.lastPayload!,
              overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(fontWeight: FontWeight.w500))),
      if (device.instanceCount > 1 && stats.lastInstance != null) ...[
        SizedBox(width: 6),
        Text('#${stats.lastInstance}', style: theme.textTheme.bodySmall),
      ],
    ]);
  }

  // the generator and validation errors are known to the app and shown localized
  String _errorText(TopicStats stats) {
    if (stats.generatorError != null) {
      if (stats.generatorError == GeneratorError.imageFolderNotFound ||
          stats.generatorError == GeneratorError.noUsableImages ||
          stats.generatorError == GeneratorError.imageUnreadable ||
          stats.generatorError == GeneratorError.invalidTemplateField) {
        return 'simulator.error.${stats.generatorError!.name}'.tr(args: [stats.errorDetail]);
      }
      return 'simulator.error.${stats.generatorError!.name}'.tr();
    }
    if (stats.issue != null) {
      return 'simulator.issue.${stats.issue!.name}'.tr(args: [stats.errorDetail]);
    }
    return stats.error ?? '';
  }

  Widget _buildActions(BuildContext context, SimulatorViewmodel vm, TopicRunState state) {
    var subscribed = vm.isSubscribedInViewer(device, topic);
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      state == TopicRunState.running
          ? IconButton(
              onPressed: () => vm.stopTopic(topic), icon: Icon(Icons.stop), tooltip: 'simulator.stoptopic.tooltip'.tr())
          : IconButton(
              onPressed: vm.canStart ? () => vm.startTopic(device, topic) : null,
              icon: Icon(Icons.play_arrow),
              color: Colors.green,
              tooltip: vm.isConnected ? 'simulator.starttopic.tooltip'.tr() : 'simulator.connectfirst.tooltip'.tr()),
      IconButton(
          onPressed: () => SimulatorDialogs.editTopic(context, vm, device, topic),
          icon: Icon(Icons.edit),
          tooltip: 'simulator.edittopic.tooltip'.tr()),
      IconButton(
          onPressed: () => vm.duplicateTopic(device, topic),
          icon: Icon(Icons.copy),
          tooltip: 'simulator.duplicatetopic.tooltip'.tr()),
      IconButton(
          onPressed: () => SimulatorDialogs.deleteTopic(context, vm, device, topic),
          icon: Icon(Icons.delete),
          tooltip: 'simulator.deletetopic.tooltip'.tr()),
      IconButton(
          onPressed: subscribed ? null : () => vm.subscribeInViewer(device, topic),
          icon: Icon(Icons.visibility),
          tooltip: subscribed
              ? 'simulator.subscribed.tooltip'.tr()
              : 'simulator.subscribe.tooltip'.tr(args: [vm.subscriptionOf(device, topic)])),
    ]);
  }
}

// A recorded topic of a recorded device: where it is published, how many were sent and the last payload. It has no
// actions of its own; the device dialog edits what is played.
class _RecordedTopicRow extends StatelessWidget {
  final SimulatedDevice device;
  final String topic;

  const _RecordedTopicRow({required this.device, required this.topic});

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<SimulatorViewmodel>();
    var theme = Theme.of(context);
    var running = vm.isRecordedRunning(device);
    var stats = vm.recordedStatsOf(device, topic);
    var playback = device.recorded!.playback;
    return Container(
      constraints: BoxConstraints(minHeight: 48),
      padding: EdgeInsets.only(left: _Columns.indent, right: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
      child: Row(children: [
        SizedBox(
          width: _Columns.status,
          child: running
              ? Tooltip(
                  message: 'simulator.state.running'.tr(),
                  child: Icon(Icons.play_arrow, size: 20, color: theme.custom.running))
              : Tooltip(
                  message: 'simulator.state.stopped'.tr(),
                  child: Icon(Icons.stop, size: 20, color: theme.unselectedWidgetColor)),
        ),
        Expanded(
          flex: _Columns.topicFlex,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: topic, style: theme.textTheme.titleSmall),
              TextSpan(text: '  →  ${vm.recordedTargetOf(device, topic)}', style: TextStyle(color: theme.hintColor)),
            ]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: _Columns.generator, child: Text('simulator.recorded.generator'.tr())),
        SizedBox(width: _Columns.interval, child: Text(RecorderFormat.speed(playback.speed))),
        SizedBox(
            width: _Columns.qos,
            child: Text(playback.qos == null ? 'simulator.recorded.asrecorded'.tr() : SimulatorFormat.qos(playback.qos!))),
        SizedBox(
            width: _Columns.sent,
            child: Text(SimulatorFormat.count(stats.sent),
                textAlign: TextAlign.end, style: TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
        SizedBox(width: 12),
        Expanded(flex: _Columns.payloadFlex, child: _buildPayload(context, stats)),
        SizedBox(width: _Columns.actions, child: _buildActions(vm)),
      ]),
    );
  }

  Widget _buildPayload(BuildContext context, TopicStats stats) {
    var theme = Theme.of(context);
    if (stats.lastPayload == null) {
      return Text('–', style: TextStyle(color: theme.hintColor));
    }
    return Row(children: [
      Flexible(
          child: Text(stats.lastPayload!,
              overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(fontWeight: FontWeight.w500))),
      if (device.instanceCount > 1 && stats.lastInstance != null) ...[
        SizedBox(width: 6),
        Text('#${stats.lastInstance}', style: theme.textTheme.bodySmall),
      ],
    ]);
  }

  Widget _buildActions(SimulatorViewmodel vm) {
    var subscribed = vm.isRecordedSubscribedInViewer(device, topic);
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      IconButton(
          onPressed: subscribed ? null : () => vm.subscribeRecordedInViewer(device, topic),
          icon: Icon(Icons.visibility),
          tooltip: subscribed
              ? 'simulator.subscribed.tooltip'.tr()
              : 'simulator.subscribe.tooltip'.tr(args: [vm.recordedSubscriptionOf(device, topic)])),
    ]);
  }
}

// A simulated VDA 5050 robot: its connection, mode, battery, messages sent and what it does, with the Faults menu
// while it runs (doc/vda5050-design.md §10.4, §10.6). Before the first start only the serial number is known.
class _RobotRow extends StatelessWidget {
  final SimulatedDevice device;
  final SimulatedRobot? robot;
  final int? instance;

  const _RobotRow({required this.device, this.robot, this.instance});

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<SimulatorViewmodel>();
    var theme = Theme.of(context);
    var running = vm.isRecordedRunning(device);
    var robot = this.robot;
    return Container(
      constraints: BoxConstraints(minHeight: 48),
      padding: EdgeInsets.only(left: _Columns.indent, right: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
      child: Row(children: [
        SizedBox(width: _Columns.status, child: _buildStatus(context, running)),
        Expanded(flex: _Columns.topicFlex, child: _buildName(context)),
        SizedBox(width: _Columns.generator, child: Text(robot?.connectionState ?? '–')),
        SizedBox(width: _Columns.interval, child: Text(robot?.operatingMode ?? '–', overflow: TextOverflow.ellipsis)),
        SizedBox(width: _Columns.qos, child: _buildBattery(context)),
        SizedBox(
            width: _Columns.sent,
            child: Text(SimulatorFormat.count(robot?.sent ?? 0),
                textAlign: TextAlign.end, style: TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
        SizedBox(width: 12),
        Expanded(flex: _Columns.payloadFlex, child: _buildActivity(context)),
        SizedBox(width: _Columns.actions, child: _buildActions(context, vm, running)),
      ]),
    );
  }

  Widget _buildStatus(BuildContext context, bool running) {
    var theme = Theme.of(context);
    var robot = this.robot;
    if (!running || robot == null) {
      return Tooltip(
          message: 'simulator.state.stopped'.tr(), child: Icon(Icons.stop, size: 20, color: theme.unselectedWidgetColor));
    }
    if (!robot.isOnline) {
      var broken = robot.connectionState == VdaConnectionState.connectionBroken;
      return Tooltip(
          message: robot.connectionState,
          child: Icon(Icons.link_off,
              size: 20, color: broken ? theme.custom.disconnectedColor : theme.unselectedWidgetColor));
    }
    return Tooltip(
        message: 'simulator.state.running'.tr(), child: Icon(Icons.play_arrow, size: 20, color: theme.custom.running));
  }

  Widget _buildName(BuildContext context) {
    var theme = Theme.of(context);
    var source = device.vda5050!;
    var n = robot?.instance ?? instance!;
    var serial = robot?.serialNumber ?? Placeholders.resolve(source.serialNumber, instance: n, deviceName: device.name);
    var prefix = robot?.topicPrefix ?? Placeholders.resolve(source.topicPrefix, instance: n, deviceName: device.name);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: serial, style: theme.textTheme.titleSmall),
        TextSpan(text: '  $prefix', style: TextStyle(color: theme.hintColor)),
      ]),
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildBattery(BuildContext context) {
    var robot = this.robot;
    if (robot == null) {
      return Text('–');
    }
    return Row(children: [
      Text('${robot.stateOfCharge.round()} %'),
      if (robot.charging)
        Tooltip(message: 'vda5050sim.charging.tooltip'.tr(), child: Icon(Icons.bolt, size: 16)),
    ]);
  }

  // driving or why not, the order and the last node, errors and open requests
  Widget _buildActivity(BuildContext context) {
    var theme = Theme.of(context);
    var robot = this.robot;
    if (robot == null) {
      return Text('–', style: TextStyle(color: theme.hintColor));
    }
    var fatal = robot.hasFatalError;
    var errors = robot.errors.length;
    var parts = [
      robot.driving ? 'vda5050sim.driving.label'.tr() : _blockedText(robot),
      if (robot.orderId.isNotEmpty)
        'vda5050sim.order.label'.tr(args: [robot.orderId, '${robot.orderUpdateId}', robot.lastNodeId])
      else
        'vda5050sim.at.label'.tr(args: [robot.lastNodeId]),
      if (robot.openRequests > 0) 'vda5050sim.requests.label'.tr(args: ['${robot.openRequests}']),
    ];
    return Row(children: [
      if (errors > 0) ...[
        Tooltip(
          message: robot.errors.map((error) => '${error.errorLevel} ${error.errorType}').join('\n'),
          child: Icon(fatal ? Icons.error : Icons.warning,
              size: 16, color: fatal ? theme.colorScheme.error : theme.custom.warning),
        ),
        SizedBox(width: 4),
        Text('$errors', style: theme.textTheme.labelLarge),
        SizedBox(width: 8),
      ],
      Flexible(child: Text(parts.join(' · '), overflow: TextOverflow.ellipsis, maxLines: 1)),
    ]);
  }

  String _blockedText(SimulatedRobot robot) {
    var reason = robot.blockedBy;
    if (reason == null) {
      return robot.isIdle ? 'vda5050sim.idle.label'.tr() : 'vda5050sim.waiting.label'.tr();
    }
    return 'vda5050sim.blocked.$reason'.tr();
  }

  Widget _buildActions(BuildContext context, SimulatorViewmodel vm, bool running) {
    var robot = this.robot;
    var fleet = vm.fleetOf(device);
    var enabled = running && robot != null && fleet != null && fleet.isRunning;
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      PopupMenuButton<RobotFault>(
        enabled: enabled,
        icon: Icon(Icons.bolt),
        tooltip: 'vda5050sim.faults.tooltip'.tr(),
        // a popup menu is at most 280 px wide unless it is told otherwise
        constraints: BoxConstraints.tightFor(width: RobotFaultMenu.width),
        onSelected: (fault) => vm.injectFault(device, robot!, fault),
        itemBuilder: (_) => [RobotFaultMenu(fleet: fleet!, robot: robot!)],
      ),
    ]);
  }
}

// A simulated Sparkplug edge node: its state, bdSeq, the seq of its last message, messages sent and its devices, with
// the Faults menu while it runs (doc/sparkplug-design.md §10.5, §10.6). Before the first start only its id is known.
class _EdgeNodeRow extends StatelessWidget {
  final SimulatedDevice device;
  final SimulatedEdgeNode? node;
  final int? instance;

  const _EdgeNodeRow({required this.device, this.node, this.instance});

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<SimulatorViewmodel>();
    var theme = Theme.of(context);
    var running = vm.isRecordedRunning(device);
    var node = this.node;
    var tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
    return Container(
      constraints: BoxConstraints(minHeight: 48),
      padding: EdgeInsets.only(left: _Columns.indent, right: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
      child: Row(children: [
        SizedBox(width: _Columns.status, child: _buildStatus(context, running)),
        Expanded(flex: _Columns.topicFlex, child: _buildName(context)),
        SizedBox(
            width: _Columns.generator,
            child: Text(node == null || !running ? '–' : 'sparkplugsim.state.${node.state.name}'.tr(),
                overflow: TextOverflow.ellipsis)),
        SizedBox(
            width: _Columns.interval,
            child: Text(node == null || node.bdSeq < 0 ? '–' : 'bdSeq ${node.bdSeq}', style: tabular)),
        SizedBox(
            width: _Columns.qos,
            child: Text(node?.lastSeq == null ? '–' : 'seq ${node!.lastSeq}', style: tabular)),
        SizedBox(
            width: _Columns.sent,
            child: Text(SimulatorFormat.count(node?.messages ?? 0), textAlign: TextAlign.end, style: tabular)),
        SizedBox(width: 12),
        Expanded(flex: _Columns.payloadFlex, child: _buildDevices(context)),
        SizedBox(width: _Columns.actions, child: _buildActions(context, vm, running)),
      ]),
    );
  }

  Widget _buildStatus(BuildContext context, bool running) {
    var theme = Theme.of(context);
    var node = this.node;
    if (!running || node == null || node.state == EdgeNodeState.stopped) {
      return Tooltip(
          message: 'simulator.state.stopped'.tr(), child: Icon(Icons.stop, size: 20, color: theme.unselectedWidgetColor));
    }
    if (node.state != EdgeNodeState.online) {
      var lost = node.state == EdgeNodeState.reconnecting;
      return Tooltip(
          message: 'sparkplugsim.state.${node.state.name}'.tr(),
          child: Icon(lost ? Icons.link_off : Icons.hourglass_empty,
              size: 20, color: lost ? theme.custom.disconnectedColor : theme.unselectedWidgetColor));
    }
    return Tooltip(
        message: 'simulator.state.running'.tr(), child: Icon(Icons.play_arrow, size: 20, color: theme.custom.running));
  }

  Widget _buildName(BuildContext context) {
    var theme = Theme.of(context);
    var source = device.sparkplug!;
    var id = node?.edgeNodeId ??
        Placeholders.resolve(source.edgeNodeId, instance: instance!, deviceName: device.name);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: id, style: theme.textTheme.titleSmall),
        TextSpan(text: '  spBv1.0/${source.groupId}/…/$id', style: TextStyle(color: theme.hintColor)),
      ]),
      overflow: TextOverflow.ellipsis,
    );
  }

  // the devices that are online, and the toggled faults that are on
  Widget _buildDevices(BuildContext context) {
    var theme = Theme.of(context);
    var node = this.node;
    if (node == null) {
      return Text('–', style: TextStyle(color: theme.hintColor));
    }
    var ids = node.deviceIds;
    var online = ids.where(node.isDeviceOnline).length;
    var faults = [
      for (var fault in SparkplugFault.values)
        if (fault.toggle && node.isFaultActive(fault)) 'sparkplugsim.fault.${fault.name}'.tr(),
    ];
    var parts = [
      if (ids.isNotEmpty) 'sparkplugsim.devices.label'.tr(args: ['$online', '${ids.length}']),
      ...faults,
    ];
    return Text(parts.join(' · '), overflow: TextOverflow.ellipsis, maxLines: 1);
  }

  Widget _buildActions(BuildContext context, SimulatorViewmodel vm, bool running) {
    var node = this.node;
    var run = vm.sparkplugOf(device);
    var enabled = running && node != null && run != null && run.isRunning;
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      PopupMenuButton<SparkplugFault>(
        enabled: enabled,
        icon: Icon(Icons.bolt),
        tooltip: 'sparkplugsim.faults.tooltip'.tr(),
        // a popup menu is at most 280 px wide unless it is told otherwise
        constraints: BoxConstraints.tightFor(width: SparkplugFaultMenu.width),
        onSelected: (fault) => vm.injectSparkplugFault(device, node!, fault),
        itemBuilder: (_) => [SparkplugFaultMenu(node: node!)],
      ),
    ]);
  }
}
