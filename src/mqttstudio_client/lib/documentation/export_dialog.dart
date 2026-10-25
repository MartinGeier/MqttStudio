import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/documentation/export/doc_export.dart';
import 'package:mqttstudio/documentation/export_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

typedef X = ExportViewmodel;

// Exports the documentation as Markdown, HTML, AsyncAPI, a JSON Schema bundle or CSV. Returns a DocExportRequest or
// null.
class ExportDialog extends StatefulWidget {
  final String title;
  // the documented paths, for the scope
  final Iterable<String> paths;
  final String? selectedPath;

  const ExportDialog({Key? key, required this.title, this.paths = const [], this.selectedPath}) : super(key: key);

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  late final ExportViewmodel _viewmodel;

  @override
  void initState() {
    super.initState();
    _viewmodel = ExportViewmodel(title: widget.title, paths: widget.paths, selectedPath: widget.selectedPath);
  }

  @override
  void dispose() {
    _viewmodel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewmodel,
      child: Consumer<ExportViewmodel>(builder: (context, vm, _) {
        return SimpleDialog(
          title: Text('docexportdialog.title'.tr()),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 480, maxWidth: 480),
              child: ReactiveForm(
                formGroup: vm.form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _buildFormat(),
                  SizedBox(height: 16),
                  _buildScope(vm),
                  SizedBox(height: 8),
                  _buildOptions(vm),
                  SizedBox(height: 8),
                  _buildFileName(vm),
                  SizedBox(height: 16),
                  _buildNote(context),
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

  Widget _buildFormat() {
    return ReactiveDropdownField<DocExportFormat>(
      formControlName: X.formatField,
      decoration:
          InputDecoration(border: OutlineInputBorder(), labelText: 'docexportdialog.format.label'.tr(), isDense: true),
      items: [
        for (var format in DocExportFormat.values)
          DropdownMenuItem(value: format, child: Text('docexportdialog.format.${format.name}'.tr())),
      ],
    );
  }

  Widget _buildScope(ExportViewmodel vm) {
    return ReactiveDropdownField<String>(
      formControlName: X.scopeField,
      isExpanded: true,
      decoration:
          InputDecoration(border: OutlineInputBorder(), labelText: 'docexportdialog.scope.label'.tr(), isDense: true),
      items: [
        DropdownMenuItem(value: X.wholeDocumentation, child: Text('docexportdialog.scope.all'.tr())),
        for (var scope in vm.scopes)
          DropdownMenuItem(
              value: scope,
              child: Text('docexportdialog.scope.selected'.tr(args: [scope]), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildOptions(ExportViewmodel vm) {
    Widget option(String name, String key) => CheckboxField(formControlName: name, form: vm.form, label: key.tr());
    return Column(children: [
      option(X.examplesField, 'docexportdialog.examples.label'),
      option(X.observedField, 'docexportdialog.observed.label'),
      option(X.brokerField, 'docexportdialog.broker.label'),
    ]);
  }

  Widget _buildFileName(ExportViewmodel vm) {
    return ReactiveTextField<String>(
      formControlName: X.fileNameField,
      maxLines: 1,
      decoration: InputDecoration(
          border: OutlineInputBorder(), labelText: 'docexportdialog.filename.label'.tr(), isDense: true),
      validationMessages: {
        ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
        ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr(),
      },
      onSubmitted: (_) => _onExport(vm),
    );
  }

  Widget _buildNote(BuildContext context) {
    var theme = Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.lock_outline, size: 18, color: theme.hintColor),
      SizedBox(width: 8),
      Expanded(child: Text('docexportdialog.credentials.note'.tr(), style: theme.textTheme.bodySmall)),
    ]);
  }

  Widget _buildActions(ExportViewmodel vm) {
    return SrxFormRow(alignment: CrossAxisAlignment.center, children: [
      Spacer(flex: 1),
      Expanded(
          flex: 5,
          child: OutlinedButton(
              onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('srx.common.cancel'.tr()))),
      SizedBox(width: 16),
      Expanded(
          flex: 5,
          child: ElevatedButton(onPressed: () => _onExport(vm), child: Text('docexportdialog.export.button'.tr()))),
    ]);
  }

  void _onExport(ExportViewmodel vm) {
    var request = vm.save();
    if (request != null) {
      GetIt.I.get<SrxNavigationService>().pop(request);
    }
  }
}
