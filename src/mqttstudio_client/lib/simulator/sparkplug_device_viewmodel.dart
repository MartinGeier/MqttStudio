import 'dart:async';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_profile.dart';
import 'package:mqttstudio/simulator/engine/placeholders.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/model/sparkplug_source.dart';
import 'package:mqttstudio/simulator/sparkplug/simulated_sparkplug_device.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the dialog that adds or edits a device of simulated Sparkplug B edge nodes (doc/sparkplug-design.md
// §10.6). The settings are a form; the metrics, which are edited in a dialog of their own, are lists here.
class SparkplugDeviceViewmodel extends SrxChangeNotifier {
  static const String nameField = 'name';
  static const String nodesField = 'nodes';
  static const String firstInstanceField = 'firstInstance';
  static const String groupIdField = 'groupId';
  static const String edgeNodeIdField = 'edgeNodeId';
  static const String primaryHostField = 'primaryHost';
  static const String simulateHostField = 'simulateHost';
  static const String scanField = 'scan';
  static const String aliasesField = 'aliases';
  static const String compressField = 'compress';
  static const String seedField = 'seed';
  static const String devicesField = 'devices';
  static const String deviceIdField = 'id';
  static const String deviceCountField = 'count';

  final SimulatedDevice device;
  final Simulation simulation;
  final bool isNew;
  late final FormGroup form;
  final List<SparkplugMetricSpec> nodeMetrics;
  // the metrics of each device, in the order of the devices form array
  final List<List<SparkplugMetricSpec>> deviceMetrics;
  late final StreamSubscription _subscription;

  SparkplugDeviceViewmodel(this.device, this.simulation, {required this.isNew})
    : nodeMetrics = [...?device.sparkplug?.copy().nodeMetrics],
      deviceMetrics = [
        for (var spec in (device.sparkplug?.copy() ?? SparkplugSource()).devices) [...spec.metrics],
      ] {
    var source = device.sparkplug ?? SparkplugSource();
    FormControl<int> intControl(int value, int minimum, int maximum) => FormControl<int>(
      value: value,
      validators: [Validators.required, Validators.min(minimum), Validators.max(maximum)],
    );
    form = FormGroup({
      nameField: FormControl<String>(
        value: device.name,
        validators: [Validators.required, Validators.maxLength(100), Validators.delegate(_validateName)],
      ),
      nodesField: intControl(device.instanceCount, 1, SimulationRules.maxEdgeNodes),
      firstInstanceField: intControl(device.firstInstance, 0, 1000000),
      groupIdField: _levelControl(source.groupId),
      edgeNodeIdField: _levelControl(source.edgeNodeId),
      primaryHostField: FormControl<String>(
        value: source.primaryHostId,
        validators: [Validators.maxLength(100), Validators.delegate(_validateLevel)],
      ),
      simulateHostField: FormControl<bool>(value: source.simulateHost),
      scanField: intControl(source.scanMs, SimulationRules.minScanMs, 3600000),
      aliasesField: FormControl<bool>(value: source.aliases),
      compressField: FormControl<bool>(value: source.compress),
      seedField: FormControl<int>(value: source.seed),
      devicesField: FormArray<Map<String, Object?>>([for (var spec in source.devices) _deviceGroup(spec)]),
    });
    _subscription = form.valueChanges.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  static FormControl<String> _levelControl(String value) => FormControl<String>(
    value: value,
    validators: [Validators.required, Validators.maxLength(100), Validators.delegate(_validateLevel)],
  );

  static FormGroup _deviceGroup(SparkplugDeviceSpec spec) => FormGroup({
    deviceIdField: _levelControl(spec.id),
    deviceCountField: FormControl<int>(
      value: spec.count,
      validators: [Validators.required, Validators.min(1), Validators.max(SimulationRules.maxSparkplugDevices)],
    ),
  });

  FormArray<Map<String, Object?>> get devicesArray => form.control(devicesField) as FormArray<Map<String, Object?>>;

  T _value<T>(String field, T fallback) => (form.control(field).value as T?) ?? fallback;

  // a host id without simulating it means a host application of the user's
  bool get hasPrimaryHost => _value(primaryHostField, '').trim().isNotEmpty;

  // ---------- metrics ----------

  void addDevice() {
    var number = devicesArray.controls.length + 1;
    devicesArray.add(_deviceGroup(SparkplugDeviceSpec(id: 'Device$number')));
    deviceMetrics.add([]);
    notifyListeners();
  }

  void removeDevice(int index) {
    devicesArray.removeAt(index);
    deviceMetrics.removeAt(index);
    notifyListeners();
  }

  // the metrics of the edge node (device null) or of a device
  List<SparkplugMetricSpec> metricsOf(int? device) => device == null ? nodeMetrics : deviceMetrics[device];

  // names a new or renamed metric must not take
  Set<String> otherNames(int? device, SparkplugMetricSpec? except) => {
    for (var metric in metricsOf(device))
      if (metric != except) metric.name,
  };

  void putMetric(int? device, SparkplugMetricSpec? old, SparkplugMetricSpec metric) {
    var metrics = metricsOf(device);
    var index = old == null ? -1 : metrics.indexOf(old);
    if (index < 0) {
      metrics.add(metric);
    } else {
      metrics[index] = metric;
    }
    notifyListeners();
  }

  void removeMetric(int? device, SparkplugMetricSpec metric) {
    metricsOf(device).remove(metric);
    notifyListeners();
  }

  // ---------- the device ----------

  SimulatedDevice _edited() {
    var host = _value(primaryHostField, '').trim();
    var source = SparkplugSource(
      groupId: _value(groupIdField, '').trim(),
      edgeNodeId: _value(edgeNodeIdField, '').trim(),
      nodeMetrics: [...nodeMetrics],
      devices: [
        for (var i = 0; i < devicesArray.controls.length; i++)
          SparkplugDeviceSpec(
            id: ((devicesArray.controls[i] as FormGroup).control(deviceIdField).value as String? ?? '').trim(),
            count: (devicesArray.controls[i] as FormGroup).control(deviceCountField).value as int? ?? 1,
            metrics: [...deviceMetrics[i]],
          ),
      ],
      scanMs: _value(scanField, 1000),
      aliases: _value(aliasesField, true),
      primaryHostId: host.isEmpty ? null : host,
      simulateHost: _value(simulateHostField, true),
      compress: _value(compressField, false),
      seed: form.control(seedField).value as int?,
    );
    return device.copy()
      ..name = _value(nameField, '').trim()
      ..kind = DeviceKind.sparkplug
      ..instanceCount = _value(nodesField, 1)
      ..firstInstance = _value(firstInstanceField, 1)
      ..topics = []
      ..sparkplug = source;
  }

  // rules the entered device breaks; empty when it can be saved
  List<SimulationIssue> get issues => form.valid ? SimulationRules.validateSparkplug(_edited()) : [];

  // the NBIRTH topics of the first and the last edge node
  String get resolvedTopics {
    var edited = _edited();
    var source = edited.sparkplug!;
    String birthOf(int n) => SparkplugProfile.topicOf(
      SpbMessageType.nBirth,
      source.groupId,
      Placeholders.resolve(source.edgeNodeId, instance: n, deviceName: edited.name),
    );
    return edited.instanceCount == 1
        ? birthOf(edited.firstInstance)
        : '${birthOf(edited.firstInstance)} … ${birthOf(edited.lastInstance)}';
  }

  double get rate => SimulatedSparkplugDevice.rateOf(_edited());

  // the fields of the EDGE NODE tab; METRICS and ADVANCED have the rest
  static const List<String> nodeTabFields = [
    nameField,
    nodesField,
    firstInstanceField,
    groupIdField,
    edgeNodeIdField,
    primaryHostField,
    simulateHostField,
  ];

  static const List<SimulationIssueKind> _metricIssues = [
    SimulationIssueKind.sparkplugDeviceNeedsNumber,
    SimulationIssueKind.sparkplugTooManyDevices,
    SimulationIssueKind.sparkplugTooManyMetrics,
    SimulationIssueKind.sparkplugMetricNameInvalid,
    SimulationIssueKind.sparkplugMetricDuplicate,
    SimulationIssueKind.sparkplugGeneratorType,
  ];

  // the tab that shows the first problem: 0 EDGE NODE, 1 METRICS, 2 ADVANCED, null when there is none
  int? get tabWithErrors {
    if (nodeTabFields.any((field) => form.control(field).invalid)) {
      return 0;
    }
    if (devicesArray.invalid) {
      return 1;
    }
    if (form.invalid) {
      return 2;
    }
    var issue = issues.firstOrNull;
    if (issue == null) {
      return null;
    }
    if (_metricIssues.contains(issue.kind) ||
        (issue.kind == SimulationIssueKind.sparkplugNameInvalid && issue.detail == 'device id')) {
      return 1;
    }
    return issue.kind == SimulationIssueKind.sparkplugTooManyChanges ? 2 : 0;
  }

  SimulatedDevice? save() {
    form.markAllAsTouched();
    if (!form.valid || issues.isNotEmpty) {
      notifyListeners();
      return null;
    }
    return _edited();
  }

  Map<String, dynamic>? _validateName(AbstractControl<dynamic> control) {
    var name = (control.value as String?) ?? '';
    if (name.trim().isNotEmpty && SimulationRules.isDuplicateDeviceName(name, simulation, exceptId: device.id)) {
      return {'duplicate': true};
    }
    return null;
  }

  // ids become topic levels
  static Map<String, dynamic>? _validateLevel(AbstractControl<dynamic> control) {
    var value = (control.value as String?) ?? '';
    if (value.contains('/') || SimulationRules.topicHasWildcard(value)) {
      return {'level': true};
    }
    return null;
  }
}
