import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Chooses the folder of the recordings library. Returns the chosen folder, or null when nothing changed.
class RecordingsFolderDialog extends StatefulWidget {
  final String current;
  final String defaultFolder;

  const RecordingsFolderDialog({Key? key, required this.current, required this.defaultFolder}) : super(key: key);

  @override
  State<RecordingsFolderDialog> createState() => _RecordingsFolderDialogState();
}

class _RecordingsFolderDialogState extends State<RecordingsFolderDialog> {
  late String _folder = widget.current;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): _onSavePressed},
      child: Focus(
        autofocus: true,
        child: SimpleDialog(
          title: Text('recordingsfolder.title'.tr()),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 560, maxWidth: 560),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                InputDecorator(
                  decoration: InputDecoration(
                      border: OutlineInputBorder(), labelText: 'recordingsfolder.folder.label'.tr(), isDense: true),
                  child: SelectableText(_folder, style: theme.textTheme.bodyLarge),
                ),
                SizedBox(height: 8),
                Row(children: [
                  TextButton.icon(
                      style: TextButton.styleFrom(minimumSize: Size(0, 48)),
                      onPressed: _onChoosePressed,
                      icon: Icon(Icons.folder_open),
                      label: Text('recordingsfolder.choose.button'.tr())),
                  SizedBox(width: 8),
                  TextButton.icon(
                      style: TextButton.styleFrom(minimumSize: Size(0, 48)),
                      onPressed: _folder == widget.defaultFolder ? null : () => setState(() => _folder = widget.defaultFolder),
                      icon: Icon(Icons.restore),
                      label: Text('recordingsfolder.default.button'.tr())),
                ]),
                SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline, size: 20, color: theme.unselectedWidgetColor),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text('recordingsfolder.hint'.tr(),
                          style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black87))),
                ]),
                SizedBox(height: 24),
                SrxFormRow(alignment: CrossAxisAlignment.center, children: [
                  Spacer(flex: 1),
                  Expanded(
                      flex: 5,
                      child: OutlinedButton(
                          onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null),
                          child: Text('srx.common.cancel'.tr()))),
                  SizedBox(width: 16),
                  Expanded(
                      flex: 5,
                      child: ElevatedButton(onPressed: _onSavePressed, child: Text('recordingsfolder.save.button'.tr()))),
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onChoosePressed() async {
    var folder = await FilePicker.getDirectoryPath(dialogTitle: 'recordingsfolder.title'.tr(), initialDirectory: _folder);
    if (folder != null && mounted) {
      setState(() => _folder = folder);
    }
  }

  void _onSavePressed() => GetIt.I.get<SrxNavigationService>().pop(_folder == widget.current ? null : _folder);
}
