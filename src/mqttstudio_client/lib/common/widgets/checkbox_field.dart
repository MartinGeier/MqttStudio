import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';

class CheckboxField extends StatelessWidget {
  final String formControlName;
  final FormGroup form;
  final String label;
  final void Function()? onChanged;

  CheckboxField({required this.formControlName, required this.form, required this.label, this.onChanged});

  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(children: [
        ReactiveCheckbox(formControlName: formControlName, onChanged: (_) => _onChanged()),
        SizedBox(width: 6),
        MouseRegion(
          cursor: form.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
              child: Text(label),
              onTap: () {
                var control = form.control(formControlName);
                if (form.enabled && control.enabled) {
                  control.value = control.value != null ? !control.value : true;
                  _onChanged();
                }
              }),
        )
      ]),
    );
  }

  _onChanged() {
    if (onChanged != null) {
      onChanged!();
    }
  }
}
