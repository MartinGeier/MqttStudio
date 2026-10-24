import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

class RecordingDetails {
  final String name;
  final String notes;

  RecordingDetails(this.name, this.notes);
}

// Changes the name and the notes of a recording. Returns RecordingDetails or null.
class RecordingDetailsDialog extends StatefulWidget {
  final RecordingInfo recording;

  const RecordingDetailsDialog({Key? key, required this.recording}) : super(key: key);

  @override
  State<RecordingDetailsDialog> createState() => _RecordingDetailsDialogState();
}

class _RecordingDetailsDialogState extends State<RecordingDetailsDialog> {
  static const String nameField = 'name';
  static const String notesField = 'notes';

  late final FormGroup _form = FormGroup({
    nameField:
        FormControl<String>(value: widget.recording.name, validators: [Validators.required, Validators.maxLength(100)]),
    notesField: FormControl<String>(value: widget.recording.footer.notes, validators: [Validators.maxLength(2000)]),
  });

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text('recordingdetails.title'.tr()),
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
                    formControlName: nameField,
                    autofocus: true,
                    decoration: InputDecoration(
                        border: OutlineInputBorder(), labelText: 'recordingdetails.name.label'.tr(), isDense: true),
                    validationMessages: {
                      ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
                      ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr(),
                    },
                    onSubmitted: (_) => _onSavePressed(),
                  ),
                ),
              ]),
              SrxFormRow(children: [
                Expanded(
                  child: ReactiveTextField<String>(
                    formControlName: notesField,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                        border: OutlineInputBorder(), labelText: 'recordingdetails.notes.label'.tr(), isDense: true),
                    validationMessages: {ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr()},
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
                    child: ElevatedButton(onPressed: _onSavePressed, child: Text('recordingdetails.save.button'.tr()))),
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
    GetIt.I.get<SrxNavigationService>().pop(RecordingDetails(
        (_form.control(nameField).value as String).trim(), (_form.control(notesField).value as String?) ?? ''));
  }
}
