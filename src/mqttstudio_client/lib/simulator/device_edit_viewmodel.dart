import 'dart:async';
import 'package:mqttstudio/simulator/engine/placeholders.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the dialog that adds or edits a simulated device
class DeviceEditViewmodel extends SrxChangeNotifier {
  static const String nameField = 'name';
  static const String instanceCountField = 'instanceCount';
  static const String firstInstanceField = 'firstInstance';

  final SimulatedDevice? device;
  final Simulation simulation;
  late final FormGroup form;

  DeviceEditViewmodel(this.device, this.simulation) {
    form = FormGroup({
      nameField: FormControl<String>(
          value: device?.name ?? _newName(),
          validators: [Validators.required, Validators.maxLength(100), Validators.delegate(_validateName)]),
      instanceCountField: FormControl<int>(
          value: device?.instanceCount ?? 1,
          validators: [Validators.required, Validators.min(1), Validators.max(SimulationRules.maxInstances)]),
      firstInstanceField:
          FormControl<int>(value: device?.firstInstance ?? 1, validators: [Validators.required, Validators.min(0)]),
    });
    _subscription = form.valueChanges.listen((_) => notifyListeners());
  }

  late final StreamSubscription _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  bool get isNew => device == null;

  int get _instanceCount => (form.control(instanceCountField).value as int?) ?? 1;

  int get _firstInstance => (form.control(firstInstanceField).value as int?) ?? 1;

  String get _name => (form.control(nameField).value as String?) ?? '';

  int get lastInstance => _firstInstance + _instanceCount - 1;

  // what the device publishes to with the entered values, per topic its first and last instance
  List<String> get resolvedTopics {
    var topics = device?.topics ?? [];
    return topics.map((topic) {
      var first = Placeholders.resolve(topic.topic, instance: _firstInstance, deviceName: _name);
      if (_instanceCount == 1) {
        return first;
      }
      return '$first … ${Placeholders.resolve(topic.topic, instance: lastInstance, deviceName: _name)}';
    }).toList();
  }

  // topics without {n} would all publish to the same topic once there is more than one instance
  bool get hasTopicsWithoutInstance =>
      _instanceCount > 1 && (device?.topics ?? []).any((topic) => !Placeholders.containsInstance(topic.topic));

  double get rate {
    var edited = SimulatedDevice(name: _name, instanceCount: _instanceCount);
    return SimulationRules.estimateRate((device?.topics ?? []).map((topic) => (edited, topic)));
  }

  SimulatedDevice? save() {
    form.markAllAsTouched();
    if (!form.valid) {
      return null;
    }
    var edited = device?.copy() ?? SimulatedDevice(name: _name);
    return edited
      ..name = _name.trim()
      ..instanceCount = _instanceCount
      ..firstInstance = _firstInstance;
  }

  String _newName() {
    var number = simulation.devices.length + 1;
    while (SimulationRules.isDuplicateDeviceName('Device $number', simulation)) {
      number++;
    }
    return 'Device $number';
  }

  Map<String, dynamic>? _validateName(AbstractControl<dynamic> control) {
    var name = (control.value as String?) ?? '';
    if (name.trim().isNotEmpty && SimulationRules.isDuplicateDeviceName(name, simulation, exceptId: device?.id)) {
      return {'duplicate': true};
    }
    return null;
  }
}
