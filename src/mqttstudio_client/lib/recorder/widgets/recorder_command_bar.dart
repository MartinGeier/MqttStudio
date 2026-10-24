import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/common/widgets/main_appbar.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/recorder/engine/recording_player.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/recorder_viewmodel.dart';
import 'package:mqttstudio/recorder/widgets/recorder_dialogs.dart';
import 'package:mqttstudio/recorder/widgets/recorder_format.dart';
import 'package:provider/provider.dart';

// The toolbar of the RECORDER tab: recording controls for the running session, playback controls for the selected
// recording. Built like the topic viewer's command bar.
class RecorderCommandBar extends StatelessWidget {
  const RecorderCommandBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<RecorderViewmodel>();
    return Column(children: [
      Divider(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          _buildRecordGroup(context, vm),
          SizedBox(height: 40, child: VerticalDivider()),
          _buildPlaybackGroup(context, vm),
          SizedBox(height: 40, child: VerticalDivider()),
          _buildSpeedGroup(context, vm),
        ]),
        Row(children: [_buildAddToSimulation(context, vm), _buildMore(context, vm)]),
      ]),
      Divider(height: 4),
    ]);
  }

  Widget _buildRecordGroup(BuildContext context, RecorderViewmodel vm) {
    var theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: OverflowBar(spacing: 6, children: [
        Tooltip(
          message: vm.isProjectOpen ? 'recorder.record.tooltip'.tr() : 'recorder.record.noproject.tooltip'.tr(),
          child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: Size(0, 48)),
              onPressed: vm.canRecord ? () => RecorderDialogs.record(context, vm) : null,
              icon: Icon(Icons.fiber_manual_record, color: vm.canRecord ? theme.custom.recordingColor : null),
              label: Text('recorder.record.button'.tr())),
        ),
        IconButton(
            onPressed: vm.isRecording ? vm.stopRecording : null,
            icon: Icon(Icons.stop),
            tooltip: 'recorder.stoprecording.tooltip'.tr()),
        IconButton(
            onPressed: vm.isRecording ? vm.addBookmark : null,
            icon: Icon(Icons.bookmark_border),
            tooltip: 'recorder.bookmark.tooltip'.tr()),
        // the flight recorder writes its window as a recording
        Tooltip(
          message: vm.isSaveScheduled ? 'recorder.saveflight.scheduled.tooltip'.tr() : 'recorder.saveflight.tooltip'.tr(),
          child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: Size(0, 48)),
              onPressed: vm.canSaveFlight ? vm.saveFlightRecording : null,
              icon: Icon(Icons.save),
              label: Text(vm.isSaveScheduled ? 'recorder.saveflight.saving'.tr() : 'recorder.saveflight.button'.tr())),
        ),
      ]),
    );
  }

  Widget _buildPlaybackGroup(BuildContext context, RecorderViewmodel vm) {
    var state = vm.playbackState;
    return OverflowBar(spacing: 6, children: [
      IconButton(
          onPressed: vm.canPlay ? () => RecorderDialogs.play(context, vm) : null,
          icon: Icon(Icons.play_arrow),
          color: Colors.green,
          tooltip: vm.selected != null && !vm.isConnected
              ? 'recorder.connectfirst.tooltip'.tr()
              : 'recorder.play.tooltip'.tr()),
      IconButton(
          onPressed: state == PlaybackState.playing ? vm.pause : null,
          icon: Icon(Icons.pause),
          color: Colors.blue,
          tooltip: 'recorder.pause.tooltip'.tr()),
      IconButton(
          onPressed: state != PlaybackState.stopped ? vm.stopPlayback : null,
          icon: Icon(Icons.stop),
          tooltip: 'recorder.stopplayback.tooltip'.tr()),
      IconButton(
          onPressed: vm.canStep ? vm.step : null, icon: Icon(Icons.skip_next), tooltip: 'recorder.step.tooltip'.tr()),
    ]);
  }

  Widget _buildSpeedGroup(BuildContext context, RecorderViewmodel vm) {
    var hasRecording = vm.selected != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        Tooltip(
          message: 'recorder.speed.tooltip'.tr(),
          child: DropdownButton<double>(
            value: vm.options.speed,
            onChanged: hasRecording ? (speed) => vm.setSpeed(speed!) : null,
            items: [
              for (var speed in PlaybackOptions.speeds)
                DropdownMenuItem(value: speed, child: Text(RecorderFormat.speed(speed)))
            ],
          ),
        ),
        SizedBox(width: 8),
        // a toggle like the view modes of the topic viewer, so it shows pressed while looping
        Tooltip(
          message: 'recorder.loop.tooltip'.tr(),
          child: ToggleButtons(
            renderBorder: false,
            constraints: BoxConstraints.tight(Size(48, 48)),
            isSelected: [vm.options.loop],
            onPressed: hasRecording ? (_) => vm.toggleLoop() : null,
            children: [Icon(Icons.repeat)],
          ),
        ),
        IconButton(
            onPressed: hasRecording ? () => RecorderDialogs.playbackOptions(context, vm) : null,
            icon: Icon(Icons.tune),
            tooltip: 'recorder.options.tooltip'.tr()),
      ]),
    );
  }

  Widget _buildAddToSimulation(BuildContext context, RecorderViewmodel vm) {
    return Tooltip(
      message: vm.isProjectOpen ? 'recorder.addtosimulation.tooltip'.tr() : 'recorder.record.noproject.tooltip'.tr(),
      child: TextButton.icon(
          style: TextButton.styleFrom(minimumSize: Size(0, 48)),
          onPressed: vm.canAddToSimulation
              ? () {
                  var name = vm.addToSimulation();
                  DefaultTabController.of(context).animateTo(MainAppBar.simulatorTab);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('recorder.addedtosimulation.info'.tr(args: [name]))));
                }
              : null,
          icon: Icon(Icons.add),
          label: Text('recorder.addtosimulation.button'.tr())),
    );
  }

  Widget _buildMore(BuildContext context, RecorderViewmodel vm) {
    var info = vm.selected;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        enabled: info != null && !vm.liveSelected,
        tooltip: 'recorder.more.tooltip'.tr(),
        icon: Icon(Icons.more_vert),
        onSelected: (action) => RecorderDialogs.onMenuAction(context, vm, info!, action),
        itemBuilder: (_) => RecorderDialogs.menuItems(vm, info!),
      ),
    );
  }
}
