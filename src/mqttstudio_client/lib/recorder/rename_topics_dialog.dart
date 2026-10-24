import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/recorder/rename_topics_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Renames topics by prefix into a new recording. Returns the list of TopicRemap or null.
class RenameTopicsDialog extends StatelessWidget {
  final List<String> topics;

  const RenameTopicsDialog({Key? key, required this.topics}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RenameTopicsViewmodel>(
      create: (_) => RenameTopicsViewmodel(topics),
      child: Consumer<RenameTopicsViewmodel>(builder: (context, vm, _) {
        var theme = Theme.of(context);
        var hint = theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor);
        return SimpleDialog(
          title: Text('renametopics.title'.tr()),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 600, maxWidth: 600),
              child: ReactiveForm(
                formGroup: vm.form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('renametopics.hint'.tr(), style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black87)),
                  ),
                  for (var i = 0; i < vm.remaps.controls.length; i++) _buildRow(vm, vm.remaps.controls[i] as FormGroup, i),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                        style: TextButton.styleFrom(minimumSize: Size(0, 48)),
                        onPressed: vm.addRemap,
                        icon: Icon(Icons.add),
                        label: Text('renametopics.add.button'.tr())),
                  ),
                  SizedBox(height: 8),
                  for (var (from, to) in vm.preview) Text('$from  →  $to', style: hint, overflow: TextOverflow.ellipsis),
                  SizedBox(height: 16),
                  _buildActions(vm),
                ]),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildRow(RenameTopicsViewmodel vm, FormGroup group, int index) {
    return SrxFormRow(children: [
      Expanded(
        child: ReactiveTextField<String>(
          formControl: group.control(RenameTopicsViewmodel.fromField) as FormControl<String>,
          autofocus: index == 0,
          decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'renametopics.from.label'.tr(), isDense: true),
          validationMessages: {ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr()},
          onSubmitted: (_) => _onSavePressed(vm),
        ),
      ),
      SizedBox(width: 16),
      Expanded(
        child: ReactiveTextField<String>(
          formControl: group.control(RenameTopicsViewmodel.toField) as FormControl<String>,
          decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'renametopics.to.label'.tr(), isDense: true),
          validationMessages: {'wildcard': (_) => 'renametopics.wildcard.error'.tr()},
          onSubmitted: (_) => _onSavePressed(vm),
        ),
      ),
      IconButton(
          onPressed: vm.remaps.controls.length > 1 ? () => vm.removeRemap(index) : null,
          tooltip: 'renametopics.remove.tooltip'.tr(),
          icon: Icon(Icons.close)),
    ]);
  }

  Widget _buildActions(RenameTopicsViewmodel vm) {
    return SrxFormRow(alignment: CrossAxisAlignment.center, children: [
      Spacer(flex: 1),
      Expanded(
          flex: 5,
          child: OutlinedButton(
              onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('srx.common.cancel'.tr()))),
      SizedBox(width: 16),
      Expanded(
          flex: 5,
          child: ElevatedButton(onPressed: () => _onSavePressed(vm), child: Text('renametopics.save.button'.tr()))),
    ]);
  }

  void _onSavePressed(RenameTopicsViewmodel vm) {
    var remaps = vm.save();
    if (remaps != null) {
      GetIt.I.get<SrxNavigationService>().pop(remaps);
    }
  }
}
