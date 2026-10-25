import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/documentation/export/import_merge.dart';
import 'package:mqttstudio/documentation/import_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Imports an AsyncAPI 3.0 or 2.x document into the documentation: new topics are added, changed ones replaced, or
// the whole documentation is replaced. Returns a DocImportRequest or null.
class ImportDialog extends StatefulWidget {
  const ImportDialog({Key? key}) : super(key: key);

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  static const int shownWarnings = 5;
  late final ImportViewmodel _viewmodel;

  @override
  void initState() {
    super.initState();
    _viewmodel = ImportViewmodel();
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
      child: Consumer<ImportViewmodel>(builder: (context, vm, _) {
        return SimpleDialog(
          title: Text('docimportdialog.title'.tr()),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 640, maxWidth: 640),
              child: ReactiveForm(
                formGroup: vm.form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _buildFile(context, vm),
                  SizedBox(height: 16),
                  SizedBox(height: 360, child: _buildContent(context, vm)),
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

  Widget _buildFile(BuildContext context, ImportViewmodel vm) {
    return Row(children: [
      Expanded(
        child: InputDecorator(
          decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'docimportdialog.file.label'.tr(),
              isDense: true,
              enabled: false),
          child: Text(vm.fileName ?? 'docimportdialog.nofile.label'.tr(), overflow: TextOverflow.ellipsis),
        ),
      ),
      SizedBox(width: 16),
      OutlinedButton.icon(
          autofocus: true,
          onPressed: vm.chooseFile,
          icon: Icon(Icons.folder_open),
          label: Text('docimportdialog.choose.button'.tr())),
    ]);
  }

  Widget _buildContent(BuildContext context, ImportViewmodel vm) {
    var theme = Theme.of(context);
    if (vm.error != null) {
      return Text('docimportdialog.error'.tr(args: [vm.error!]),
          style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.error));
    }
    var plan = vm.plan;
    var imported = vm.imported;
    if (plan == null || imported == null) {
      return Center(
          child:
              Text('docimportdialog.hint'.tr(), style: theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor)));
    }
    var warnings = imported.warnings;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
          'docimportdialog.summary'.tr(args: [
            imported.documentation.title.isEmpty ? '–' : imported.documentation.title,
            imported.version,
            '${plan.countOf(ImportState.added)}',
            '${plan.countOf(ImportState.changed)}',
            '${plan.countOf(ImportState.same)}',
          ]),
          style: theme.textTheme.bodyMedium),
      if (warnings.isNotEmpty) ...[
        SizedBox(height: 4),
        Tooltip(
          message: warnings.join('\n'),
          child: Text(
              [
                'docimportdialog.warnings'.plural(warnings.length),
                ...warnings.take(shownWarnings),
                if (warnings.length > shownWarnings) '…'
              ].join('\n'),
              maxLines: shownWarnings + 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error)),
        ),
      ],
      SizedBox(height: 8),
      _buildMode(vm),
      SizedBox(height: 8),
      Expanded(child: _buildItems(context, vm, plan)),
    ]);
  }

  Widget _buildMode(ImportViewmodel vm) {
    return ReactiveDropdownField<ImportMode>(
      formControlName: ImportViewmodel.modeField,
      decoration:
          InputDecoration(border: OutlineInputBorder(), labelText: 'docimportdialog.mode.label'.tr(), isDense: true),
      items: [
        for (var mode in ImportMode.values)
          DropdownMenuItem(value: mode, child: Text('docimportdialog.mode.${mode.name}'.tr())),
      ],
    );
  }

  Widget _buildItems(BuildContext context, ImportViewmodel vm, ImportPlan plan) {
    var theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(4)),
      child: ListView(children: [
        for (var item in plan.items)
          Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
            child: Row(children: [
              Checkbox(
                  value: vm.replaceAll || item.accept,
                  onChanged: vm.replaceAll || item.state == ImportState.same || item.state == ImportState.conflict
                      ? null
                      : (value) => vm.setAccept(item, value == true)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.imported.path, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
                  if (item.imported.title.isNotEmpty)
                    Text(item.imported.title,
                        style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor),
                        overflow: TextOverflow.ellipsis),
                ]),
              ),
              Tooltip(
                message: item.state == ImportState.conflict
                    ? 'docimportdialog.conflict.tooltip'.tr(args: [item.existing!.path])
                    : '',
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 12),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(10)),
                  child: Text('docimportdialog.state.${item.state.name}'.tr(), style: theme.textTheme.bodySmall),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _buildActions(ImportViewmodel vm) {
    return SrxFormRow(alignment: CrossAxisAlignment.center, children: [
      Spacer(flex: 1),
      Expanded(
          flex: 5,
          child: OutlinedButton(
              onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('srx.common.cancel'.tr()))),
      SizedBox(width: 16),
      Expanded(
          flex: 5,
          child: ElevatedButton(
              onPressed: vm.canImport ? () => GetIt.I.get<SrxNavigationService>().pop(vm.save()) : null,
              child: Text('docimportdialog.import.button'.tr()))),
    ]);
  }
}
