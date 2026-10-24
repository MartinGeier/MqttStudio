import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/recorder/recorder_viewmodel.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/widgets/recorder_dialogs.dart';
import 'package:mqttstudio/recorder/widgets/recorder_format.dart';
import 'package:provider/provider.dart';

// The recordings library on the left of the RECORDER tab: the running recording on top, then the saved ones
class RecordingList extends StatelessWidget {
  static const double width = 300;

  const RecordingList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<RecorderViewmodel>();
    var theme = Theme.of(context);
    return Container(
      width: width,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: theme.dividerColor))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _buildHead(context, vm),
        Expanded(child: _buildItems(context, vm)),
        Divider(height: 1),
        _buildFoot(context, vm),
      ]),
    );
  }

  Widget _buildHead(BuildContext context, RecorderViewmodel vm) {
    var theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(children: [
        Expanded(
            child: Text('recordinglist.title'.tr(), style: theme.textTheme.titleMedium!.copyWith(color: Colors.black87))),
        IconButton(onPressed: vm.loadRecordings, icon: Icon(Icons.refresh), tooltip: 'recordinglist.refresh.tooltip'.tr()),
        IconButton(
            onPressed: vm.canChangeFolder ? () => RecorderDialogs.recordingsFolder(context, vm) : null,
            icon: Icon(Icons.settings),
            tooltip: vm.isRecording
                ? 'recordinglist.foldersetting.recording.tooltip'.tr()
                : 'recordinglist.foldersetting.tooltip'.tr()),
      ]),
    );
  }

  Widget _buildItems(BuildContext context, RecorderViewmodel vm) {
    var theme = Theme.of(context);
    if (vm.recordings.isEmpty && !vm.isRecording) {
      return Center(
          child: Text('recordinglist.watermark'.tr(),
              style: theme.textTheme.headlineMedium!.copyWith(color: theme.dividerColor)));
    }
    return ListView(children: [
      if (vm.isRecording) ...[_buildLiveItem(context, vm), Divider(height: 9)],
      for (var info in vm.recordings) _buildItem(context, vm, info),
    ]);
  }

  Widget _buildLiveItem(BuildContext context, RecorderViewmodel vm) {
    var theme = Theme.of(context);
    var color = theme.custom.recordingColor;
    return _ItemFrame(
      selected: vm.liveSelected,
      onTap: vm.selectLive,
      leading: Container(
          width: 14, height: 14, margin: EdgeInsets.all(3), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      name: vm.liveName,
      meta: 'recordinglist.live.meta'.tr(args: [RecorderFormat.clock(vm.liveElapsed), RecorderFormat.count(vm.liveMessages)]),
      metaStyle: theme.textTheme.bodySmall!.copyWith(color: color, fontWeight: FontWeight.w500),
    );
  }

  Widget _buildItem(BuildContext context, RecorderViewmodel vm, RecordingInfo info) {
    var theme = Theme.of(context);
    return GestureDetector(
      onSecondaryTapDown: (details) => RecorderDialogs.showRecordingMenu(context, vm, info, details.globalPosition),
      child: _ItemFrame(
        selected: !vm.liveSelected && vm.selected?.id == info.id,
        onTap: () => vm.select(info),
        name: info.name,
        meta: '${RecorderFormat.date(info.header.startedAt)} · ${RecorderFormat.duration(info.footer.duration)} · '
            '${RecorderFormat.bytes(info.size)}',
        metaStyle: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor),
        tag: info.footer.recovered ? 'recordinglist.recovered.tag'.tr() : null,
        trailing: _buildItemActions(context, vm, info),
      ),
    );
  }

  Widget _buildItemActions(BuildContext context, RecorderViewmodel vm, RecordingInfo info) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
          onPressed: () => RecorderDialogs.onMenuAction(context, vm, info, RecorderDialogs.editAction),
          icon: Icon(Icons.edit, size: 20),
          visualDensity: VisualDensity.compact,
          tooltip: 'recordinglist.edit.tooltip'.tr()),
      IconButton(
          onPressed: vm.canDelete(info) ? () => RecorderDialogs.onMenuAction(context, vm, info, RecorderDialogs.deleteAction) : null,
          icon: Icon(Icons.delete, size: 20),
          visualDensity: VisualDensity.compact,
          tooltip: vm.canDelete(info) ? 'recordinglist.delete.tooltip'.tr() : 'recordinglist.deleteplaying.tooltip'.tr()),
    ]);
  }

  Widget _buildFoot(BuildContext context, RecorderViewmodel vm) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Expanded(
            child: Tooltip(
          message: 'recordinglist.import.tooltip'.tr(),
          child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: Size(0, 48)),
              onPressed: vm.canImport ? vm.importRecording : null,
              icon: Icon(Icons.file_upload),
              label: Text('recordinglist.import.button'.tr())),
        )),
        SizedBox(width: 8),
        Expanded(
            child: Tooltip(
          message: 'recordinglist.folder.tooltip'.tr(),
          child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: Size(0, 48)),
              onPressed: vm.canOpenFolder ? vm.openFolder : null,
              icon: Icon(Icons.folder_open),
              label: Text('recordinglist.folder.button'.tr())),
        )),
      ]),
    );
  }
}

class _ItemFrame extends StatelessWidget {
  final bool selected;
  final void Function() onTap;
  final Widget? leading;
  final String name;
  final String meta;
  final TextStyle metaStyle;
  final String? tag;
  final Widget? trailing;

  const _ItemFrame(
      {required this.selected,
      required this.onTap,
      this.leading,
      required this.name,
      required this.meta,
      required this.metaStyle,
      this.tag,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: selected
              ? BoxDecoration(border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3)))
              : null,
          padding: EdgeInsets.fromLTRB(selected ? 9 : 12, 8, 12, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (leading != null) ...[leading!, SizedBox(width: 8)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w500)),
                SizedBox(height: 2),
                Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle),
                if (tag != null) ...[SizedBox(height: 4), Chip(label: Text(tag!), visualDensity: VisualDensity.compact)],
              ]),
            ),
            if (trailing != null) trailing!,
          ]),
        ),
      ),
    );
  }
}
