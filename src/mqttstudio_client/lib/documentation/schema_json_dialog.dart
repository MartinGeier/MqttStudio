import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/documentation/schema_json_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Edits a payload schema as JSON Schema text. Returns the SchemaNode or null.
class SchemaJsonDialog extends StatefulWidget {
  final SchemaNode? schema;

  const SchemaJsonDialog({Key? key, this.schema}) : super(key: key);

  @override
  State<SchemaJsonDialog> createState() => _SchemaJsonDialogState();
}

class _SchemaJsonDialogState extends State<SchemaJsonDialog> {
  late final SchemaJsonViewmodel _viewmodel;

  @override
  void initState() {
    super.initState();
    _viewmodel = SchemaJsonViewmodel(widget.schema);
  }

  @override
  void dispose() {
    _viewmodel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return ChangeNotifierProvider.value(
      value: _viewmodel,
      child: Consumer<SchemaJsonViewmodel>(builder: (context, vm, _) {
        return SimpleDialog(
          title: Text('schemajsondialog.title'.tr()),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 720, maxWidth: 720),
              child: ReactiveForm(
                formGroup: vm.form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ReactiveTextField<String>(
                    formControlName: SchemaJsonViewmodel.textField,
                    autofocus: true,
                    minLines: 18,
                    maxLines: 18,
                    style: TextStyle(fontFamily: 'Consolas', fontSize: 13),
                    decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'schemajsondialog.text.label'.tr(),
                        helperText: 'schemajsondialog.text.helper'.tr(),
                        helperMaxLines: 2,
                        alignLabelWithHint: true,
                        isDense: true),
                    validationMessages: {
                      ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
                      'object': (_) => 'schemajsondialog.object.error'.tr(),
                      'json': (error) => 'schemajsondialog.json.error'.tr(args: ['$error']),
                    },
                  ),
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
                        child: ElevatedButton(onPressed: () => _onSave(vm), child: Text('srx.common.save'.tr()))),
                  ]),
                  if (vm.warnings.isNotEmpty) ...[
                    SizedBox(height: 8),
                    Text(vm.warnings.join('\n'),
                        style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error)),
                  ],
                ]),
              ),
            ),
          ],
        );
      }),
    );
  }

  // keywords outside the supported subset are shown once; saving again keeps the rest
  void _onSave(SchemaJsonViewmodel vm) {
    var hadWarnings = vm.warnings.isNotEmpty;
    var schema = vm.save();
    if (schema != null && (vm.warnings.isEmpty || hadWarnings)) {
      GetIt.I.get<SrxNavigationService>().pop(schema);
    }
  }
}
