import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mqttstudio/common/widgets/fast_topic_chip.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/recorder/widgets/recorder_format.dart';
import 'package:mqttstudio/simulator/engine/generator_instances.dart';
import 'package:mqttstudio/simulator/engine/simulator_runner.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/simulator_viewmodel.dart';
import 'package:mqttstudio/simulator/widgets/simulator_dialogs.dart';
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
            if (device.isRecorded)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tooltip(
                    message: 'simulator.recorded.tooltip'.tr(),
                    child: Icon(Icons.history, size: 20, color: theme.unselectedWidgetColor)),
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

  Widget _buildActions(BuildContext context, SimulatorViewmodel vm, int running) {
    var canStartDevice = device.isRecorded ? !vm.isRecordedRunning(device) : running < device.topics.length;
    var isRunning = device.isRecorded ? vm.isRecordedRunning(device) : running > 0;
    return Row(children: [
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
