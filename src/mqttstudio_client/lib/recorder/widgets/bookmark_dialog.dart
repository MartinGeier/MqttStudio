import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Renames a bookmark of a recording. Returns the new label or null.
class BookmarkDialog extends StatefulWidget {
  final String label;

  const BookmarkDialog({Key? key, required this.label}) : super(key: key);

  static Future<String?> show(BuildContext context, String label) => showDialog<String>(
      context: context, builder: (_) => SrxTheme(data: CustomTheme.srxTheme, child: BookmarkDialog(label: label)));

  @override
  State<BookmarkDialog> createState() => _BookmarkDialogState();
}

class _BookmarkDialogState extends State<BookmarkDialog> {
  static const String labelField = 'label';

  late final FormGroup _form = FormGroup({
    labelField: FormControl<String>(value: widget.label, validators: [Validators.required, Validators.maxLength(100)]),
  });

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text('bookmarkdialog.title'.tr()),
      contentPadding: EdgeInsets.all(16),
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: 480, maxWidth: 480),
          child: ReactiveForm(
            formGroup: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SrxFormRow(children: [
                Expanded(
                  child: ReactiveTextField<String>(
                    formControlName: labelField,
                    autofocus: true,
                    decoration: InputDecoration(
                        border: OutlineInputBorder(), labelText: 'bookmarkdialog.label.label'.tr(), isDense: true),
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
                    flex: 5, child: ElevatedButton(onPressed: _onSavePressed, child: Text('bookmarkdialog.save.button'.tr()))),
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
    GetIt.I.get<SrxNavigationService>().pop((_form.control(labelField).value as String).trim());
  }
}
