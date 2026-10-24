import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/recorder/engine/playback_service.dart';
import 'package:mqttstudio/recorder/anonymize_dialog.dart';
import 'package:mqttstudio/recorder/export_dialog.dart';
import 'package:mqttstudio/recorder/import_dialog.dart';
import 'package:mqttstudio/recorder/merge_dialog.dart';
import 'package:mqttstudio/recorder/model/anonymize_rule.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/rename_topics_dialog.dart';
import 'package:mqttstudio/recorder/tools/recording_export.dart';
import 'package:mqttstudio/recorder/tools/recording_import.dart';
import 'package:mqttstudio/recorder/widgets/split_dialog.dart';
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
  static const String assignAction = 'assign';
  static const String deleteAction = 'delete';
  static const String trimAction = 'trim';
  static const String topicsAction = 'topics';
  static const String renameAction = 'rename';
  static const String anonymizeAction = 'anonymize';
  static const String mergeAction = 'merge';
  static const String splitAction = 'split';
  static const String exportAction = 'export';

  static Future<T?> _show<T>(BuildContext context, Widget dialog) =>
      showDialog<T>(context: context, builder: (_) => SrxTheme(data: CustomTheme.srxTheme, child: dialog));

  static Future record(BuildContext context, RecorderViewmodel vm) async {
    var project = GetIt.I.get<ProjectManager>().currentProject;
    if (project == null) {
      return;
    }
    var initial = await vm.initialConfig();
    var suggestions = await vm.filterSuggestions();
    if (!context.mounted) {
      return;
    }
    var config = await _show<RecorderConfig>(context, RecordDialog(config: initial, settings: project.mqttSettings, suggestions: suggestions));
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

  static PopupMenuItem<String> _item(String action, IconData icon, String labelKey, {bool enabled = true}) => PopupMenuItem(
      value: action, enabled: enabled, child: ListTile(leading: Icon(icon), title: Text(labelKey.tr()), dense: true));

  // edits write new recordings (§8.1); they apply to the selected recording, so the menu acts on that one
  static List<PopupMenuEntry<String>> menuItems(RecorderViewmodel vm, RecordingInfo info) {
    var edits = vm.canEdit && vm.selected?.id == info.id;
    return [
      _item(editAction, Icons.edit, 'recorder.menu.edit'),
      PopupMenuItem(
          value: assignAction,
          enabled: vm.canAssignToProject(info),
          child: ListTile(
              leading: Icon(Icons.drive_file_move),
              title: Text('recorder.menu.assign'.tr(args: [vm.projectName ?? ''])),
              dense: true)),
      PopupMenuDivider(),
      _item(trimAction, Icons.content_cut, 'recorder.menu.trim', enabled: edits && vm.canTrim),
      _item(topicsAction, Icons.checklist, 'recorder.menu.topics', enabled: edits && vm.canKeepTopics),
      _item(renameAction, Icons.drive_file_rename_outline, 'recorder.menu.rename', enabled: edits),
      _item(anonymizeAction, Icons.visibility_off, 'recorder.menu.anonymize', enabled: edits),
      _item(mergeAction, Icons.merge, 'recorder.menu.merge', enabled: edits && vm.otherRecordings.isNotEmpty),
      _item(splitAction, Icons.call_split, 'recorder.menu.split', enabled: edits),
      PopupMenuDivider(),
      _item(exportAction, Icons.file_download, 'recorder.menu.export', enabled: edits),
      PopupMenuDivider(),
      _menuDelete(vm, info),
    ];
  }

  static PopupMenuItem<String> _menuDelete(RecorderViewmodel vm, RecordingInfo info) => PopupMenuItem(
            value: deleteAction,
            enabled: vm.canDelete(info),
            child: ListTile(leading: Icon(Icons.delete), title: Text('recorder.menu.delete'.tr()), dense: true));

  static Future importRecording(BuildContext context, RecorderViewmodel vm) async {
    var request = await _show<ImportRequest>(context, ImportDialog());
    if (request != null) {
      await vm.importRecording(request);
    }
  }

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
          await vm.saveDetails(info, details.name, details.notes);
        }
      case assignAction:
        await vm.assignToProject(info);
      case trimAction:
        await vm.trimToRange();
      case topicsAction:
        await vm.keepSelectedTopics();
      case renameAction:
        var remaps = await _show<List<TopicRemap>>(context, RenameTopicsDialog(topics: List.of(info.footer.topics)..sort()));
        if (remaps != null) {
          await vm.renameTopics(remaps);
        }
      case anonymizeAction:
        var result = await _show<({List<AnonymizeRule> rules, bool properties})>(context, AnonymizeDialog());
        if (result != null) {
          await vm.anonymize(result.rules, result.properties);
        }
      case mergeAction:
        var result = await _show<({List<RecordingInfo> recordings, String name})>(
            context, MergeDialog(recording: info, candidates: vm.otherRecordings));
        if (result != null) {
          await vm.merge(result.recordings, result.name);
        }
      case splitAction:
        var mode = await _show<SplitMode>(
            context,
            SplitDialog(
                bookmarkCount: vm.bookmarkCount, playheadMicros: vm.playheadMicros, topicCount: info.footer.topics.length));
        if (mode != null) {
          await vm.split(mode);
        }
      case exportAction:
        var request = await _show<ExportRequest>(
            context,
            ExportDialog(
                canLimitTopics: vm.selectedTopicCount < info.footer.topics.length,
                canLimitRange: vm.hasRange,
                topicsLabel: 'export.topics.label'.tr(args: ['${vm.selectedTopicCount}', '${info.footer.topics.length}'])));
        if (request != null) {
          await vm.export(request);
        }
      case deleteAction:
        if (await _show<bool>(context, SrxDialog.confirmDelete(bodyText: 'recorder.delete.confirm'.tr(args: [info.name]))) ==
            true) {
          await vm.delete(info);
        }
    }
  }
}
