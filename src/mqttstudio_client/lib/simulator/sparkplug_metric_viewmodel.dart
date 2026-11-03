import 'dart:async';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/simulator/generator_editor_model.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/sparkplug_source.dart';
import 'package:mqttstudio/simulator/sparkplug/metric_values.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the dialog that adds or edits one metric of a simulated edge node or device
// (doc/sparkplug-design.md §10.3, §10.6)
class SparkplugMetricViewmodel extends SrxChangeNotifier {
  static const String nameField = 'name';
  static const String typeField = 'type';
  static const String unitField = 'unit';
  static const String deadbandField = 'deadband';
  static const String writableField = 'writable';
  static const List<String> reservedNames = ['bdSeq', 'Node Control/Rebirth'];

  final SparkplugMetricSpec? metric;
  // the names of the other metrics of the same edge node or device
  final Set<String> otherNames;
  late final FormGroup form;
  // template and image generators don't give a metric value
  late final GeneratorEditorModel generator;
  late final StreamSubscription _subscription;

  SparkplugMetricViewmodel(this.metric, {required this.otherNames}) {
    var initial =
        metric ?? SparkplugMetricSpec(name: '', type: SpbDataType.double, generator: const RandomWalkGenerator());
    generator = GeneratorEditorModel(initial.generator, isTemplateField: true)..addListener(notifyListeners);
    form = FormGroup({
      nameField: FormControl<String>(
        value: initial.name,
        validators: [Validators.required, Validators.maxLength(200), Validators.delegate(_validateName)],
      ),
      typeField: FormControl<SpbDataType>(value: initial.type, validators: [Validators.required]),
      unitField: FormControl<String>(value: initial.unit, validators: [Validators.maxLength(40)]),
      deadbandField: FormControl<double>(value: initial.deadband, validators: [Validators.required, Validators.min(0)]),
      writableField: FormControl<bool>(value: initial.writable),
    });
    _subscription = form.valueChanges.listen((_) => notifyListeners());
  }

  bool get isNew => metric == null;

  @override
  void dispose() {
    _subscription.cancel();
    generator.removeListener(notifyListeners);
    generator.dispose();
    super.dispose();
  }

  SpbDataType get type => (form.control(typeField).value as SpbDataType?) ?? SpbDataType.double;

  bool get isNumber => SparkplugValues.isNumber(type);

  // the chosen generator doesn't give values of the chosen type, e.g. a random string for a Double
  bool get generatorMismatch => !SparkplugValues.generatorFits(type, generator.build());

  SparkplugMetricSpec? save() {
    form.markAllAsTouched();
    var generatorValid = generator.validate();
    if (!form.valid || !generatorValid || generatorMismatch) {
      notifyListeners();
      return null;
    }
    var unit = ((form.control(unitField).value as String?) ?? '').trim();
    return SparkplugMetricSpec(
      name: (form.control(nameField).value as String).trim(),
      type: type,
      generator: generator.build(),
      unit: unit.isEmpty ? null : unit,
      deadband: isNumber ? (form.control(deadbandField).value as double? ?? 0) : 0,
      writable: form.control(writableField).value as bool? ?? false,
    );
  }

  Map<String, dynamic>? _validateName(AbstractControl<dynamic> control) {
    var name = ((control.value as String?) ?? '').trim();
    if (reservedNames.contains(name)) {
      return {'reserved': true};
    }
    if (otherNames.contains(name)) {
      return {'duplicate': true};
    }
    return null;
  }
}
