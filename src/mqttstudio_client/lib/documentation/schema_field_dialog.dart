import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/utils/number_value_accessor.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/documentation/schema_field_viewmodel.dart';
import 'package:mqttstudio/documentation/widgets/doc_format.dart';
import 'package:mqttstudio/documentation/widgets/tag_field.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

typedef S = SchemaFieldViewmodel;

// Adds or edits one field of a JSON payload schema. Returns a SchemaFieldResult or null.
class SchemaFieldDialog extends StatefulWidget {
  final SchemaNode? schema;
  final String? path;
  final bool required;

  const SchemaFieldDialog({Key? key, required this.schema, this.path, this.required = false}) : super(key: key);

  @override
  State<SchemaFieldDialog> createState() => _SchemaFieldDialogState();
}

class _SchemaFieldDialogState extends State<SchemaFieldDialog> {
  late final SchemaFieldViewmodel _viewmodel;

  @override
  void initState() {
    super.initState();
    _viewmodel = SchemaFieldViewmodel(widget.schema, widget.path, required: widget.required);
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
        child: Consumer<SchemaFieldViewmodel>(builder: (context, vm, _) {
          return SimpleDialog(
              title: Text((vm.isNew ? 'schemafielddialog.add.title' : 'schemafielddialog.edit.title').tr()),
              contentPadding: EdgeInsets.all(16),
              children: [
                ConstrainedBox(
                    constraints: BoxConstraints(minWidth: 480, maxWidth: 480),
                    child: ReactiveForm(
                        formGroup: vm.form,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          SrxFormRow(children: [
                            Expanded(flex: 3, child: _buildPathField()),
                            SizedBox(width: 16),
                            Expanded(flex: 2, child: _buildTypeField())
                          ]),
                          SizedBox(height: 16),
                          if (vm.isNumber) ...[_buildNumberRow(), SizedBox(height: 16)],
                          if (vm.isString) ...[_buildFormatField(), SizedBox(height: 16)],
                          if (vm.isString || vm.isNumber) ...[
                            ReactiveTagField(
                                formControlName: S.enumField, labelText: 'schemafielddialog.enum.label'.tr()),
                            SizedBox(height: 16)
                          ],
                          _buildDescriptionField(),
                          if (!vm.isItems)
                            CheckboxField(
                                formControlName: S.requiredField,
                                form: vm.form,
                                label: 'schemafielddialog.required.label'.tr()),
                          SizedBox(height: 16),
                          _buildActions()
                        ])))
              ]);
        }));
  }

  Widget _buildPathField() {
    return ReactiveTextField<String>(
        formControlName: S.pathField,
        autofocus: true,
        maxLines: 1,
        decoration: InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'schemafielddialog.path.label'.tr(),
            helperText: 'schemafielddialog.path.helper'.tr(),
            isDense: true),
        validationMessages: {
          ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
          'schemaPath': (_) => 'schemafielddialog.path.error'.tr(),
          'taken': (_) => 'schemafielddialog.path.taken.error'.tr()
        },
        onSubmitted: (_) => _onSave());
  }

  Widget _buildTypeField() {
    return ReactiveDropdownField<SchemaType>(
        formControlName: S.typeField,
        decoration: InputDecoration(
            border: OutlineInputBorder(), labelText: 'schemafielddialog.type.label'.tr(), isDense: true),
        items: [
          for (var type in SchemaType.values) DropdownMenuItem(value: type, child: Text(DocFormat.schemaType(type)))
        ]);
  }

  Widget _buildNumberRow() {
    return SrxFormRow(children: [
      Expanded(child: _textField(S.unitField, 'doceditor.unit.label')),
      SizedBox(width: 16),
      Expanded(child: _numberField(S.minimumField, 'doceditor.min.label')),
      SizedBox(width: 16),
      Expanded(child: _numberField(S.maximumField, 'doceditor.max.label'))
    ]);
  }

  Widget _buildFormatField() {
    return ReactiveDropdownField<String>(
        formControlName: S.formatField,
        decoration: InputDecoration(
            border: OutlineInputBorder(), labelText: 'schemafielddialog.format.label'.tr(), isDense: true),
        items: [
          DropdownMenuItem<String>(value: null, child: Text('schemafielddialog.format.none'.tr())),
          for (var format in S.formats) DropdownMenuItem(value: format, child: Text(format))
        ]);
  }

  Widget _buildDescriptionField() => _textField(S.descriptionField, 'doceditor.fielddescription.label', maxLines: 3);

  Widget _textField(String name, String labelKey, {int maxLines = 1}) {
    return ReactiveTextField<String>(
        formControlName: name,
        minLines: 1,
        maxLines: maxLines,
        decoration: InputDecoration(border: OutlineInputBorder(), labelText: labelKey.tr(), isDense: true),
        validationMessages: {ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr()},
        onSubmitted: maxLines == 1 ? (_) => _onSave() : null);
  }

  Widget _numberField(String name, String labelKey) {
    return ReactiveTextField<double>(
        formControlName: name,
        valueAccessor: NumberValueAccessor(),
        maxLines: 1,
        decoration: InputDecoration(border: OutlineInputBorder(), labelText: labelKey.tr(), isDense: true),
        validationMessages: {'range': (_) => 'doceditor.range.error'.tr()},
        onSubmitted: (_) => _onSave());
  }

  Widget _buildActions() {
    return SrxFormRow(alignment: CrossAxisAlignment.center, children: [
      Spacer(flex: 1),
      Expanded(
          flex: 5,
          child: OutlinedButton(
              onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('srx.common.cancel'.tr()))),
      SizedBox(width: 16),
      Expanded(flex: 5, child: ElevatedButton(onPressed: _onSave, child: Text('srx.common.save'.tr())))
    ]);
  }

  void _onSave() {
    var result = _viewmodel.save();
    if (result != null) {
      GetIt.I.get<SrxNavigationService>().pop(result);
    }
  }
}
