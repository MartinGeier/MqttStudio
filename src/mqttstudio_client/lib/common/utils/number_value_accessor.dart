import 'package:reactive_forms/reactive_forms.dart';

// Shows 20 instead of 20.00 as DoubleValueAccessor does, and takes a comma as decimal separator
class NumberValueAccessor extends ControlValueAccessor<double, String> {
  @override
  String modelToViewValue(double? modelValue) {
    if (modelValue == null) {
      return '';
    }
    return modelValue == modelValue.roundToDouble() && modelValue.abs() < 1e15
        ? modelValue.toInt().toString()
        : modelValue.toString();
  }

  @override
  double? viewToModelValue(String? viewValue) =>
      viewValue == null || viewValue.trim().isEmpty ? null : double.tryParse(viewValue.trim().replaceAll(',', '.'));
}
