import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Asks for the name of the recording the topic viewer's messages are saved to (doc/recorder-design.md §5.6).
// Returns the name or null.
class SaveBufferDialog extends StatefulWidget {
  final String name;
  final int messageCount;

  const SaveBufferDialog({Key? key, required this.name, required this.messageCount}) : super(key: key);

  @override
  State<SaveBufferDialog> createState() => _SaveBufferDialogState();
}

class _SaveBufferDialogState extends State<SaveBufferDialog> {
  static const String nameField = 'name';

  late final FormGroup _form = FormGroup({
    nameField: FormControl<String>(value: widget.name, validators: [Validators.required, Validators.maxLength(100)]),
  });

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return SimpleDialog(
      title: Text('savebufferdialog.title'.tr()),
      contentPadding: EdgeInsets.all(16),
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: 480, maxWidth: 480),
          child: ReactiveForm(
            formGroup: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                    'savebufferdialog.note'.tr(args: [NumberFormat.decimalPattern('en').format(widget.messageCount)]),
                    style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black87)),
              ),
              SrxFormRow(children: [
                Expanded(
                  child: ReactiveTextField<String>(
                    formControlName: nameField,
                    autofocus: true,
                    decoration: InputDecoration(
                        border: OutlineInputBorder(), labelText: 'savebufferdialog.name.label'.tr(), isDense: true),
                    validationMessages: {
                      ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
                      ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr(),
                    },
                    onSubmitted: (_) => _onSavePressed(),
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
                    child: ElevatedButton(onPressed: _onSavePressed, child: Text('savebufferdialog.save.button'.tr()))),
              ]),
            ]),
          ),
        ),
      ],
    );
  }

  void _onSavePressed() {
    _form.markAllAsTouched();
    if (!_form.valid) {
      return;
    }
    GetIt.I.get<SrxNavigationService>().pop((_form.control(nameField).value as String).trim());
  }
}
