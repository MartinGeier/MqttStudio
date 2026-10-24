import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/common/widgets/error_snackbar.dart';
import 'package:mqttstudio/recorder/anonymize_viewmodel.dart';
import 'package:mqttstudio/recorder/model/anonymize_rule.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Anonymizes a recording into a new one (doc/recorder-design.md §8.1). Returns ({rules, properties}) or null.
class AnonymizeDialog extends StatelessWidget {
  const AnonymizeDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AnonymizeViewmodel>(
      create: (_) => AnonymizeViewmodel([])
        ..onFileError = (message) => ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(message, context)),
      child: Consumer<AnonymizeViewmodel>(builder: (context, vm, _) {
        var theme = Theme.of(context);
        return SimpleDialog(
          title: Text('anonymize.title'.tr()),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 960, maxWidth: 960),
              child: ReactiveForm(
                formGroup: vm.form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('anonymize.hint'.tr(), style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black87)),
                  ),
                  for (var i = 0; i < vm.groups.length; i++) _buildRule(vm, vm.groups[i], i),
                  Row(children: [
                    TextButton.icon(
                        style: TextButton.styleFrom(minimumSize: Size(0, 48)),
                        onPressed: vm.addRule,
                        icon: Icon(Icons.add),
                        label: Text('anonymize.add.button'.tr())),
                    Spacer(),
                    TextButton.icon(
                        style: TextButton.styleFrom(minimumSize: Size(0, 48)),
                        onPressed: vm.loadRules,
                        icon: Icon(Icons.file_open),
                        label: Text('anonymize.load.button'.tr())),
                    TextButton.icon(
                        style: TextButton.styleFrom(minimumSize: Size(0, 48)),
                        onPressed: vm.saveRules,
                        icon: Icon(Icons.save),
                        label: Text('anonymize.save.button'.tr())),
                  ]),
                  CheckboxField(
                      formControlName: AnonymizeViewmodel.propertiesField, form: vm.form, label: 'anonymize.properties.label'.tr()),
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

  Widget _buildRule(AnonymizeViewmodel vm, FormGroup group, int index) {
    var target = vm.targetOf(group);
    var action = vm.actionOf(group);
    return SrxFormRow(children: [
      Expanded(
        flex: 4,
        child: ReactiveTextField<String>(
          formControl: group.control(AnonymizeViewmodel.filterField) as FormControl<String>,
          autofocus: index == 0,
          decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'anonymize.filter.label'.tr(), isDense: true),
          validationMessages: {
            ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
            'filter': (_) => 'recorddialog.filter.wildcard.error'.tr(),
          },
          onSubmitted: (_) => _onApplyPressed(vm),
        ),
      ),
      SizedBox(width: 16),
      Expanded(
        flex: 3,
        child: ReactiveDropdownField<AnonymizeTarget>(
          formControl: group.control(AnonymizeViewmodel.targetField) as FormControl<AnonymizeTarget>,
          decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'anonymize.target.label'.tr(), isDense: true),
          items: [
            for (var value in AnonymizeTarget.values)
              DropdownMenuItem(value: value, child: Text('anonymize.target.${value.name}'.tr()))
          ],
        ),
      ),
      SizedBox(width: 16),
      Expanded(
        flex: 3,
        child: target == AnonymizeTarget.wholePayload
            ? SizedBox.shrink()
            : ReactiveTextField<String>(
                formControl: group.control(AnonymizeViewmodel.detailField) as FormControl<String>,
                decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: target == AnonymizeTarget.jsonPath ? 'anonymize.path.label'.tr() : 'anonymize.level.label'.tr(),
                    isDense: true),
                validationMessages: {
                  'jsonPath': (_) => 'recordingcharts.path.error'.tr(),
                  'level': (_) => 'anonymize.level.error'.tr(),
                },
                onSubmitted: (_) => _onApplyPressed(vm),
              ),
      ),
      SizedBox(width: 16),
      Expanded(
        flex: 3,
        child: ReactiveDropdownField<AnonymizeAction>(
          formControl: group.control(AnonymizeViewmodel.actionField) as FormControl<AnonymizeAction>,
          decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'anonymize.action.label'.tr(), isDense: true),
          items: [
            for (var value in AnonymizeAction.values)
              DropdownMenuItem(value: value, child: Text('anonymize.action.${value.name}'.tr()))
          ],
        ),
      ),
      SizedBox(width: 16),
      Expanded(
        flex: 2,
        child: !vm.needsValue(group)
            ? SizedBox.shrink()
            : ReactiveTextField<String>(
                formControl: group.control(AnonymizeViewmodel.valueField) as FormControl<String>,
                decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: action == AnonymizeAction.fixed ? 'anonymize.value.label'.tr() : 'anonymize.percent.label'.tr(),
                    isDense: true),
                validationMessages: {'percent': (_) => 'anonymize.percent.error'.tr()},
                onSubmitted: (_) => _onApplyPressed(vm),
              ),
      ),
      IconButton(
          onPressed: vm.groups.length > 1 ? () => vm.removeRule(index) : null,
          tooltip: 'anonymize.remove.tooltip'.tr(),
          icon: Icon(Icons.close)),
    ]);
  }

  Widget _buildActions(AnonymizeViewmodel vm) {
    return SrxFormRow(alignment: CrossAxisAlignment.center, children: [
      Spacer(flex: 3),
      Expanded(
          flex: 5,
          child: OutlinedButton(
              onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('srx.common.cancel'.tr()))),
      SizedBox(width: 16),
      Expanded(
          flex: 5,
          child: ElevatedButton(onPressed: () => _onApplyPressed(vm), child: Text('anonymize.apply.button'.tr()))),
    ]);
  }

  void _onApplyPressed(AnonymizeViewmodel vm) {
    var result = vm.save();
    if (result != null) {
      GetIt.I.get<SrxNavigationService>().pop(result);
    }
  }
}
