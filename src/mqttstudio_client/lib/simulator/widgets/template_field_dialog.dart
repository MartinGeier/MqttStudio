import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/simulator/generator_editor_model.dart';
import 'package:mqttstudio/simulator/widgets/generator_editor.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Edits one named field of a template: its name and its generator. Returns the TemplateField or null.
class TemplateFieldDialog extends StatefulWidget {
  final TemplateField field;
  // names of the other fields of the template, a name must be unique
  final List<String> otherNames;

  const TemplateFieldDialog({Key? key, required this.field, required this.otherNames}) : super(key: key);

  @override
  State<TemplateFieldDialog> createState() => _TemplateFieldDialogState();
}

class _TemplateFieldDialogState extends State<TemplateFieldDialog> {
  static const String nameField = 'name';
  static final RegExp namePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  late final GeneratorEditorModel _generator;
  late final FormGroup _form;

  @override
  void initState() {
    super.initState();
    _generator = GeneratorEditorModel(widget.field.generator, isTemplateField: true);
    _form = FormGroup({
      nameField: FormControl<String>(value: widget.field.name, validators: [
        Validators.required,
        Validators.pattern(namePattern, validationMessage: 'fieldName'),
        Validators.delegate((control) => widget.otherNames.contains(control.value) ? {'duplicate': true} : null),
      ]),
    });
  }

  @override
  void dispose() {
    _generator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(title: Text('simulator.templatefielddialog.title'.tr()), contentPadding: EdgeInsets.all(16), children: [
      ConstrainedBox(
        constraints: BoxConstraints(minWidth: 760, maxWidth: 760),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ReactiveForm(
            formGroup: _form,
            child: SrxFormRow(children: [
              Expanded(
                  child: ReactiveTextField<String>(
                formControlName: nameField,
                autofocus: true,
                decoration: InputDecoration(
                    border: OutlineInputBorder(), labelText: 'simulator.templatefield.name.label'.tr(), isDense: true),
                validationMessages: {
                  ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
                  'fieldName': (_) => 'simulator.templatefield.name.error'.tr(),
                  'duplicate': (_) => 'simulator.templatefield.duplicate.error'.tr(),
                },
                onSubmitted: (_) => _onOkPressed(),
              )),
              SizedBox(width: 16),
              Expanded(
                  child: ReactiveDropdownField(
                formControl: _generator.typeControl,
                decoration: InputDecoration(
                    border: OutlineInputBorder(), labelText: 'simulator.field.generator.label'.tr(), isDense: true),
                items: [
                  for (var type in _generator.availableTypes)
                    DropdownMenuItem(value: type, child: Text('simulator.generator.${type.key}'.tr()))
                ],
              )),
            ]),
          ),
          GeneratorEditor(model: _generator),
          SizedBox(height: 16),
          SrxFormRow(alignment: CrossAxisAlignment.center, children: [
            Spacer(flex: 1),
            Expanded(
                flex: 5,
                child: OutlinedButton(
                    onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('srx.common.cancel'.tr()))),
            SizedBox(width: 16),
            Expanded(flex: 5, child: ElevatedButton(onPressed: _onOkPressed, child: Text('srx.common.ok'.tr()))),
          ]),
        ]),
      ),
    ]);
  }

  void _onOkPressed() {
    _form.markAllAsTouched();
    if (!_form.valid || !_generator.validate()) {
      return;
    }
    GetIt.I.get<SrxNavigationService>().pop(TemplateField(_form.control(nameField).value as String, _generator.build()));
  }
}
