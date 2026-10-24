import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/utils/json_path.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/recorder/tools/recording_export.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the export dialog (doc/recorder-design.md §8.3)
class ExportViewmodel extends SrxChangeNotifier {
  static const String formatField = 'format';
  static const String topicsField = 'topics';
  static const String rangeField = 'range';
  static const String columnsField = 'columns';

  final bool canLimitTopics;
  final bool canLimitRange;
  late final FormGroup form;
  late final StreamSubscription _subscription;

  ExportViewmodel({required this.canLimitTopics, required this.canLimitRange}) {
    form = FormGroup({
      formatField: FormControl<ExportFormat>(value: ExportFormat.jsonLines),
      topicsField: FormControl<bool>(value: canLimitTopics, disabled: !canLimitTopics),
      rangeField: FormControl<bool>(value: canLimitRange, disabled: !canLimitRange),
      columnsField: FormControl<String>(value: '', validators: [Validators.delegate(_validateColumns)]),
    });
    _subscription = form.valueChanges.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  ExportFormat get format => form.control(formatField).value as ExportFormat? ?? ExportFormat.jsonLines;

  // a .mqttrec export is a copy of the whole file
  bool get isCopy => format == ExportFormat.mqttrec;

  ExportRequest? save() {
    form.markAllAsTouched();
    if (!form.valid) {
      return null;
    }
    return ExportRequest(
      format,
      onlySelectedTopics: !isCopy && canLimitTopics && (form.control(topicsField).value as bool? ?? false),
      onlyRange: !isCopy && canLimitRange && (form.control(rangeField).value as bool? ?? false),
      columns: format == ExportFormat.csv ? _columns(form.control(columnsField).value as String?) : const [],
    );
  }

  static List<JsonPath> _columns(String? text) => [
        for (var part in (text ?? '').split(',').map((part) => part.trim()).where((part) => part.isNotEmpty)) JsonPath.parse(part)
      ];

  static Map<String, dynamic>? _validateColumns(AbstractControl<dynamic> control) {
    try {
      _columns(control.value as String?);
      return null;
    } on FormatException {
      return {'jsonpath': true};
    }
  }
}

// Exports the selected recording as JSON lines, CSV or a copy of the file. Returns an ExportRequest or null.
class ExportDialog extends StatelessWidget {
  final bool canLimitTopics;
  final bool canLimitRange;
  final String topicsLabel;

  const ExportDialog({Key? key, required this.canLimitTopics, required this.canLimitRange, required this.topicsLabel})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ExportViewmodel>(
      create: (_) => ExportViewmodel(canLimitTopics: canLimitTopics, canLimitRange: canLimitRange),
      child: Consumer<ExportViewmodel>(builder: (context, vm, _) {
        return SimpleDialog(
          title: Text('export.title'.tr()),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 480, maxWidth: 480),
              child: ReactiveForm(
                formGroup: vm.form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SrxFormRow(children: [
                    Expanded(
                      child: ReactiveDropdownField<ExportFormat>(
                        formControlName: ExportViewmodel.formatField,
                        autofocus: true,
                        decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'export.format.label'.tr(), isDense: true),
                        items: [
                          for (var format in ExportFormat.values)
                            DropdownMenuItem(value: format, child: Text('export.format.${format.name}'.tr()))
                        ],
                      ),
                    ),
                  ]),
                  if (!vm.isCopy) ...[
                    CheckboxField(formControlName: ExportViewmodel.topicsField, form: vm.form, label: topicsLabel),
                    CheckboxField(formControlName: ExportViewmodel.rangeField, form: vm.form, label: 'export.range.label'.tr()),
                  ],
                  if (vm.format == ExportFormat.csv)
                    SrxFormRow(children: [
                      Expanded(
                        child: ReactiveTextField<String>(
                          formControlName: ExportViewmodel.columnsField,
                          decoration: InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'export.columns.label'.tr(),
                              helperText: 'export.columns.helper'.tr(),
                              isDense: true),
                          validationMessages: {'jsonpath': (_) => 'recordingcharts.path.error'.tr()},
                          onSubmitted: (_) => _onExportPressed(vm),
                        ),
                      ),
                    ]),
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
                        child: ElevatedButton(onPressed: () => _onExportPressed(vm), child: Text('export.export.button'.tr()))),
                  ]),
                ]),
              ),
            ),
          ],
        );
      }),
    );
  }

  void _onExportPressed(ExportViewmodel vm) {
    var request = vm.save();
    if (request != null) {
      GetIt.I.get<SrxNavigationService>().pop(request);
    }
  }
}
