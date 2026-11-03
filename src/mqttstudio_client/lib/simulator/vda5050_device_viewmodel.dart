import 'dart:async';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/simulator/engine/placeholders.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/model/vda5050_source.dart';
import 'package:mqttstudio/simulator/vda5050/simulated_fleet.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the dialog that adds or edits a device of simulated VDA 5050 robots (doc/vda5050-design.md §10.6)
class Vda5050DeviceViewmodel extends SrxChangeNotifier {
  static const String nameField = 'name';
  static const String robotsField = 'robots';
  static const String firstInstanceField = 'firstInstance';
  static const String versionField = 'version';
  static const String interfaceNameField = 'interfaceName';
  static const String manufacturerField = 'manufacturer';
  static const String serialNumberField = 'serialNumber';
  static const String speedField = 'speed';
  static const String batteryPerHourField = 'batteryPerHour';
  static const String chargePerHourField = 'chargePerHour';
  static const String columnsField = 'columns';
  static const String rowsField = 'rows';
  static const String spacingField = 'spacing';
  static const String chargingStationsField = 'chargingStations';
  static const String mapIdField = 'mapId';
  static const String minOrderNodesField = 'minOrderNodes';
  static const String maxOrderNodesField = 'maxOrderNodes';
  static const String horizonNodesField = 'horizonNodes';
  static const String actionPercentField = 'actionPercent';
  static const String minActionSecField = 'minActionSec';
  static const String maxActionSecField = 'maxActionSec';
  static const String minIdleSecField = 'minIdleSec';
  static const String maxIdleSecField = 'maxIdleSec';
  static const String heartbeatField = 'heartbeat';
  static const String visualizationField = 'visualization';
  static const String factsheetField = 'factsheet';
  static const String zonesField = 'zones';
  static const String requestsField = 'requests';
  static const String randomFaultsField = 'randomFaults';
  static const String seedField = 'seed';

  final SimulatedDevice device;
  final Simulation simulation;
  final bool isNew;
  late final FormGroup form;
  late final StreamSubscription _subscription;
  late final StreamSubscription _versionSubscription;

  Vda5050DeviceViewmodel(this.device, this.simulation, {required this.isNew}) {
    var source = device.vda5050 ?? Vda5050Source();
    FormControl<int> intControl(int value, int minimum, int maximum) =>
        FormControl<int>(value: value, validators: [Validators.required, Validators.min(minimum), Validators.max(maximum)]);
    FormControl<double> doubleControl(double value, double minimum, double maximum) => FormControl<double>(
        value: value, validators: [Validators.required, Validators.min(minimum), Validators.max(maximum)]);
    FormControl<String> nameControl(String value) => FormControl<String>(
        value: value, validators: [Validators.required, Validators.maxLength(100), Validators.delegate(_validateLevel)]);
    form = FormGroup({
      nameField: FormControl<String>(
          value: device.name,
          validators: [Validators.required, Validators.maxLength(100), Validators.delegate(_validateName)]),
      robotsField: intControl(device.instanceCount, 1, SimulationRules.maxRobots),
      firstInstanceField: intControl(device.firstInstance, 0, 1000000),
      versionField: FormControl<VdaVersion>(value: source.version),
      interfaceNameField: nameControl(source.interfaceName),
      manufacturerField: nameControl(source.manufacturer),
      serialNumberField: nameControl(source.serialNumber),
      speedField: doubleControl(source.speed, 0.1, 10),
      batteryPerHourField: doubleControl(source.batteryPerHour, 0, 1000),
      chargePerHourField: doubleControl(source.chargePerHour, 1, 10000),
      columnsField: intControl(source.columns, 2, 50),
      rowsField: intControl(source.rows, 1, 50),
      spacingField: doubleControl(source.spacing, 0.5, 100),
      chargingStationsField: intControl(source.chargingStations, 0, 50),
      mapIdField: nameControl(source.mapId),
      minOrderNodesField: intControl(source.minOrderNodes, 2, 100),
      maxOrderNodesField: intControl(source.maxOrderNodes, 2, 100),
      horizonNodesField: intControl(source.horizonNodes, 0, 10),
      actionPercentField: intControl((source.actionProbability * 100).round(), 0, 100),
      minActionSecField: intControl(source.minActionSec, 0, 3600),
      maxActionSecField: intControl(source.maxActionSec, 0, 3600),
      minIdleSecField: intControl(source.minIdleSec, 0, 3600),
      maxIdleSecField: intControl(source.maxIdleSec, 0, 3600),
      heartbeatField: intControl(source.stateHeartbeatSec, 1, 30),
      visualizationField: FormControl<int>(
          value: source.visualizationMs, validators: [Validators.required, Validators.delegate(_validateVisualization)]),
      factsheetField: FormControl<bool>(value: source.factsheet),
      zonesField: FormControl<bool>(value: source.zones),
      requestsField: FormControl<bool>(value: source.requests),
      randomFaultsField: doubleControl(source.randomFaultsPerHour, 0, 3600),
      seedField: FormControl<int>(value: source.seed),
    });
    _subscription = form.valueChanges.listen((_) => notifyListeners());
    _versionSubscription = form.control(versionField).valueChanges.listen((value) => _onVersionChanged(value as VdaVersion?));
    _enableV3Fields(source.version);
  }

  @override
  void dispose() {
    _subscription.cancel();
    _versionSubscription.cancel();
    super.dispose();
  }

  T _value<T>(String field, T fallback) => (form.control(field).value as T?) ?? fallback;

  bool get isV3 => _value(versionField, VdaVersion.v3).isV3;

  // the device as entered, for the rules and for saving
  SimulatedDevice _edited() {
    var source = Vda5050Source(
      version: _value(versionField, VdaVersion.v3),
      interfaceName: _value(interfaceNameField, '').trim(),
      manufacturer: _value(manufacturerField, '').trim(),
      serialNumber: _value(serialNumberField, '').trim(),
      mapId: _value(mapIdField, '').trim(),
      columns: _value(columnsField, 0),
      rows: _value(rowsField, 0),
      spacing: _value(spacingField, 0.0),
      chargingStations: _value(chargingStationsField, 0),
      speed: _value(speedField, 0.0),
      batteryPerHour: _value(batteryPerHourField, 0.0),
      chargePerHour: _value(chargePerHourField, 0.0),
      stateHeartbeatSec: _value(heartbeatField, 0),
      visualizationMs: _value(visualizationField, 0),
      factsheet: _value(factsheetField, true),
      minOrderNodes: _value(minOrderNodesField, 0),
      maxOrderNodes: _value(maxOrderNodesField, 0),
      horizonNodes: _value(horizonNodesField, 0),
      actionProbability: _value(actionPercentField, 0) / 100,
      minActionSec: _value(minActionSecField, 0),
      maxActionSec: _value(maxActionSecField, 0),
      minIdleSec: _value(minIdleSecField, 0),
      maxIdleSec: _value(maxIdleSecField, 0),
      zones: _value(zonesField, true),
      requests: _value(requestsField, true),
      randomFaultsPerHour: _value(randomFaultsField, 0.0),
      seed: form.control(seedField).value as int?,
    );
    return device.copy()
      ..name = _value(nameField, '').trim()
      ..kind = DeviceKind.vda5050
      ..instanceCount = _value(robotsField, 1)
      ..firstInstance = _value(firstInstanceField, 1)
      ..topics = []
      ..vda5050 = source;
  }

  // rules the entered device breaks; empty when it can be saved
  List<SimulationIssue> get issues => form.valid ? SimulationRules.validateVda5050(_edited()) : [];

  // the state topics of the first and the last robot
  String get resolvedTopics {
    var edited = _edited();
    String stateOf(int n) =>
        '${Placeholders.resolve(edited.vda5050!.topicPrefix, instance: n, deviceName: edited.name)}/${VdaTopic.state}';
    return edited.instanceCount == 1
        ? stateOf(edited.firstInstance)
        : '${stateOf(edited.firstInstance)} … ${stateOf(edited.lastInstance)}';
  }

  double get rate => SimulatedFleet.rateOf(_edited());

  // the fields of the ROBOTS tab; the rest is on the SIMULATION tab
  static const List<String> robotsTabFields = [
    nameField, robotsField, firstInstanceField, versionField, interfaceNameField, manufacturerField, serialNumberField,
    columnsField, rowsField, spacingField, chargingStationsField, mapIdField,
  ];

  // the tab that shows the first problem: 0 for ROBOTS, 1 for SIMULATION, null when there is none
  int? get tabWithErrors {
    if (robotsTabFields.any((field) => form.control(field).invalid)) {
      return 0;
    }
    if (form.invalid) {
      return 1;
    }
    var issue = issues.firstOrNull;
    if (issue == null) {
      return null;
    }
    var onSimulationTab = issue.kind == SimulationIssueKind.vdaSettingOutOfRange &&
        !const ['columns', 'rows', 'spacing'].contains(issue.detail);
    return onSimulationTab ? 1 : 0;
  }

  SimulatedDevice? save() {
    form.markAllAsTouched();
    if (!form.valid || issues.isNotEmpty) {
      notifyListeners();
      return null;
    }
    return _edited();
  }

  // the usual interface name follows the version unless the user chose another one
  void _onVersionChanged(VdaVersion? version) {
    var control = form.control(interfaceNameField);
    var name = control.value as String?;
    if (version == VdaVersion.v2 && name == Vda5050Source.defaultInterfaceV3) {
      control.value = Vda5050Source.defaultInterfaceV2;
    } else if (version == VdaVersion.v3 && name == Vda5050Source.defaultInterfaceV2) {
      control.value = Vda5050Source.defaultInterfaceV3;
    }
    _enableV3Fields(version ?? VdaVersion.v3);
  }

  // zones and requests stay visible but are disabled for 2.x robots
  void _enableV3Fields(VdaVersion version) {
    for (var field in [zonesField, requestsField]) {
      var control = form.control(field);
      if (version.isV3) {
        control.markAsEnabled(emitEvent: false);
      } else {
        control.markAsDisabled(emitEvent: false);
      }
    }
  }

  Map<String, dynamic>? _validateName(AbstractControl<dynamic> control) {
    var name = (control.value as String?) ?? '';
    if (name.trim().isNotEmpty && SimulationRules.isDuplicateDeviceName(name, simulation, exceptId: device.id)) {
      return {'duplicate': true};
    }
    return null;
  }

  // names become topic levels
  static Map<String, dynamic>? _validateLevel(AbstractControl<dynamic> control) {
    var value = (control.value as String?) ?? '';
    if (value.contains('/') || SimulationRules.topicHasWildcard(value)) {
      return {'level': true};
    }
    return null;
  }

  static Map<String, dynamic>? _validateVisualization(AbstractControl<dynamic> control) {
    var value = control.value as int?;
    if (value != null && value != 0 && value < 100) {
      return {'visualization': true};
    }
    return null;
  }
}
