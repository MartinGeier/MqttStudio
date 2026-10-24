import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/widgets/recorder_format.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the merge dialog: which other recordings to merge and the new name
class MergeViewmodel extends SrxChangeNotifier {
  static const String nameField = 'name';

  final List<RecordingInfo> candidates;
  final Set<String> chosen = {};
  late final FormGroup form;
  bool noneChosen = false;

  MergeViewmodel(RecordingInfo recording, this.candidates) {
    form = FormGroup({
      nameField: FormControl<String>(
          value: '${recording.name} (merged)', validators: [Validators.required, Validators.maxLength(100)]),
    });
  }

  void toggle(RecordingInfo info, bool merge) {
    if (merge) {
      chosen.add(info.id);
    } else {
      chosen.remove(info.id);
    }
    noneChosen = false;
    notifyListeners();
  }

  ({List<RecordingInfo> recordings, String name})? save() {
    form.markAllAsTouched();
    noneChosen = chosen.isEmpty;
    notifyListeners();
    if (!form.valid || noneChosen) {
      return null;
    }
    return (
      recordings: candidates.where((info) => chosen.contains(info.id)).toList(),
      name: (form.control(nameField).value as String).trim()
    );
  }
}

// Merges the selected recording with others into a new one, interleaved by time. Returns ({recordings, name}) or null.
class MergeDialog extends StatelessWidget {
  final RecordingInfo recording;
  final List<RecordingInfo> candidates;

  const MergeDialog({Key? key, required this.recording, required this.candidates}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MergeViewmodel>(
      create: (_) => MergeViewmodel(recording, candidates),
      child: Consumer<MergeViewmodel>(builder: (context, vm, _) {
        var theme = Theme.of(context);
        return SimpleDialog(
          title: Text('merge.title'.tr(args: [recording.name])),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 480, maxWidth: 480),
              child: ReactiveForm(
                formGroup: vm.form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SrxFormRow(children: [
                    Expanded(
                      child: ReactiveTextField<String>(
                        formControlName: MergeViewmodel.nameField,
                        autofocus: true,
                        decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'merge.name.label'.tr(), isDense: true),
                        validationMessages: {
                          ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
                          ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr(),
                        },
                        onSubmitted: (_) => _onMergePressed(vm),
                      ),
                    ),
                  ]),
                  Text('merge.with.label'.tr(), style: theme.textTheme.titleSmall),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: 320),
                    child: ListView(shrinkWrap: true, children: [
                      for (var info in candidates)
                        CheckboxListTile(
                          dense: true,
                          value: vm.chosen.contains(info.id),
                          onChanged: (merge) => vm.toggle(info, merge ?? false),
                          title: Text(info.name),
                          subtitle: Text('${RecorderFormat.date(info.header.startedAt)} · ${RecorderFormat.duration(info.footer.duration)}'),
                        ),
                    ]),
                  ),
                  if (vm.noneChosen)
                    Text('merge.nonechosen.error'.tr(), style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error)),
                  SizedBox(height: 16),
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
                        child: ElevatedButton(onPressed: () => _onMergePressed(vm), child: Text('merge.merge.button'.tr()))),
                  ]),
                ]),
              ),
            ),
          ],
        );
      }),
    );
  }

  void _onMergePressed(MergeViewmodel vm) {
    var result = vm.save();
    if (result != null) {
      GetIt.I.get<SrxNavigationService>().pop(result);
    }
  }
}
