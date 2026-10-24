import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/recorder/engine/playback_service.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/model/recorder_config.dart';
import 'package:mqttstudio/recorder/playback_options_dialog.dart';
import 'package:mqttstudio/recorder/record_dialog.dart';
import 'package:mqttstudio/recorder/recorder_viewmodel.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/widgets/recording_details_dialog.dart';
import 'package:mqttstudio/recorder/widgets/recordings_folder_dialog.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Opens the dialogs of the RECORDER tab and applies their result
class RecorderDialogs {
  static const String editAction = 'edit';
  static const String deleteAction = 'delete';

  static Future<T?> _show<T>(BuildContext context, Widget dialog) =>
      showDialog<T>(context: context, builder: (_) => SrxTheme(data: CustomTheme.srxTheme, child: dialog));

  static Future record(BuildContext context, RecorderViewmodel vm) async {
    var project = GetIt.I.get<ProjectManager>().currentProject;
    if (project == null) {
      return;
    }
    var initial = await vm.initialConfig();
    if (!context.mounted) {
      return;
    }
    var config = await _show<RecorderConfig>(context, RecordDialog(config: initial, settings: project.mqttSettings));
    if (config != null) {
      await vm.startRecording(config);
    }
  }

  // asks first when the running recording would record the playback; that can be intended (§6.3)
  static Future play(BuildContext context, RecorderViewmodel vm) async {
    if (vm.playbackWouldBeRecorded &&
        await _show<bool>(context, SrxDialog.yesNo(bodyText: 'recorder.feedback.confirm'.tr())) != true) {
      return;
    }
    await vm.play();
  }

  static Future playbackOptions(BuildContext context, RecorderViewmodel vm) async {
    var info = vm.selected;
    if (info == null) {
      return;
    }
    var options = await _show<PlaybackOptions>(
        context,
        PlaybackOptionsDialog(
            recording: info, options: vm.options, maxRate: GetIt.I.get<PlaybackService>().availableRate));
    if (options != null) {
      await vm.applyOptions(options);
    }
  }

  static Future recordingsFolder(BuildContext context, RecorderViewmodel vm) async {
    var current = vm.libraryLocation;
    var defaultFolder = vm.defaultLibraryLocation;
    if (current == null || defaultFolder == null) {
      return;
    }
    var folder = await _show<String>(context, RecordingsFolderDialog(current: current, defaultFolder: defaultFolder));
    if (folder != null) {
      await vm.changeFolder(folder);
    }
  }

  static List<PopupMenuEntry<String>> menuItems(RecorderViewmodel vm, RecordingInfo info) => [
        PopupMenuItem(
            value: editAction,
            child: ListTile(leading: Icon(Icons.edit), title: Text('recorder.menu.edit'.tr()), dense: true)),
        PopupMenuItem(
            value: deleteAction,
            enabled: vm.canDelete(info),
            child: ListTile(leading: Icon(Icons.delete), title: Text('recorder.menu.delete'.tr()), dense: true)),
      ];

  static Future showRecordingMenu(BuildContext context, RecorderViewmodel vm, RecordingInfo info, Offset position) async {
    var action = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
        items: menuItems(vm, info));
    if (action != null && context.mounted) {
      await onMenuAction(context, vm, info, action);
    }
  }

  static Future onMenuAction(BuildContext context, RecorderViewmodel vm, RecordingInfo info, String action) async {
    switch (action) {
      case editAction:
        var details = await _show<RecordingDetails>(context, RecordingDetailsDialog(recording: info));
        if (details != null) {
          await vm.rename(info, details.name);
          var renamed = vm.recordings.where((r) => r.id == info.id).firstOrNull ?? info;
          await vm.saveNotes(renamed, details.notes);
        }
      case deleteAction:
        if (await _show<bool>(context, SrxDialog.confirmDelete(bodyText: 'recorder.delete.confirm'.tr(args: [info.name]))) ==
            true) {
          await vm.delete(info);
        }
    }
  }
}
