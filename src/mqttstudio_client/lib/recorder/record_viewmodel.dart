import 'dart:async';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/cli/duration_parser.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/model/recorder_config.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the dialog that starts a recording
class RecordViewmodel extends SrxChangeNotifier {
  static const String nameField = 'name';
  static const String filtersField = 'filters';
  static const String filterField = 'filter';
  static const String qosField = 'qos';
  static const String excludeField = 'exclude';
  static const String durationField = 'duration';
  static const String maxMessagesField = 'maxMessages';
  static const String maxSizeField = 'maxSizeMb';
  static const String maxPayloadField = 'maxPayloadKb';
  static const String snapshotField = 'snapshot';

  final MqttSettings settings;
  late final FormGroup form;
  late final StreamSubscription _subscription;

  RecordViewmodel(RecorderConfig config, this.settings) {
    form = FormGroup({
      nameField: FormControl<String>(value: config.name, validators: [Validators.required, Validators.maxLength(100)]),
      filtersField: FormArray<Map<String, Object?>>(
          [for (var filter in config.filters) _filterGroup(filter.filter, filter.qos, filter.exclude)],
          validators: [Validators.delegate(_atLeastOneInclude)]),
      durationField: FormControl<String>(
          value: config.durationSeconds == null ? '' : _compact(config.durationSeconds!),
          validators: [Validators.delegate(_validateDuration)]),
      maxMessagesField: FormControl<int>(value: config.maxMessages, validators: [Validators.delegate(_positiveOrEmpty)]),
      maxSizeField: FormControl<int>(
          value: config.maxBytes ~/ RecorderConfig.megabyte, validators: [Validators.required, Validators.min(1)]),
      maxPayloadField: FormControl<int>(
          value: config.maxPayloadBytes == null ? null : config.maxPayloadBytes! ~/ 1024, validators: [Validators.delegate(_positiveOrEmpty)]),
      snapshotField: FormControl<bool>(value: config.recordRetainedSnapshot),
    });
    _subscription = form.valueChanges.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  FormArray<Map<String, Object?>> get filters => form.control(filtersField) as FormArray<Map<String, Object?>>;

  void addFilter() {
    filters.add(_filterGroup('', MqttQos.exactlyOnce, false));
    notifyListeners();
  }

  void removeFilter(int index) {
    filters.removeAt(index);
    notifyListeners();
  }

  List<RecorderFilter> get _enteredFilters => [
        for (var group in filters.controls.cast<FormGroup>())
          RecorderFilter(((group.control(filterField).value as String?) ?? '').trim(),
              qos: group.control(qosField).value as MqttQos? ?? MqttQos.exactlyOnce,
              exclude: group.control(excludeField).value as bool? ?? false)
      ];

  // include filters another one already receives, e.g. a/b/+ under a/#
  List<CoveredFilter> get coveredFilters => RecorderRules.normalize(
          _enteredFilters.where((filter) => RecorderRules.validateFilter(filter.filter) == null).toList())
      .covered;

  // # and + at the start don't match topics like $SYS/…
  bool get hasRootWildcard =>
      _enteredFilters.any((filter) => !filter.exclude && (filter.filter.startsWith('#') || filter.filter.startsWith('+')));

  String get broker => '${settings.hostname}:${settings.port}';

  RecorderConfig? save() {
    form.markAllAsTouched();
    if (!form.valid) {
      return null;
    }
    var duration = (form.control(durationField).value as String?)?.trim() ?? '';
    var maxPayloadKb = form.control(maxPayloadField).value as int?;
    return RecorderConfig(
      name: (form.control(nameField).value as String).trim(),
      filters: _enteredFilters,
      durationSeconds: duration.isEmpty ? null : DurationParser.parse(duration).inSeconds,
      maxMessages: form.control(maxMessagesField).value as int?,
      maxBytes: (form.control(maxSizeField).value as int) * RecorderConfig.megabyte,
      maxPayloadBytes: maxPayloadKb == null ? null : maxPayloadKb * 1024,
      recordRetainedSnapshot: form.control(snapshotField).value as bool? ?? true,
    );
  }

  FormGroup _filterGroup(String filter, MqttQos qos, bool exclude) => FormGroup({
        filterField: FormControl<String>(value: filter, validators: [Validators.required, Validators.delegate(_validateFilter)]),
        qosField: FormControl<MqttQos>(value: qos),
        excludeField: FormControl<bool>(value: exclude),
      });

  static Map<String, dynamic>? _validateFilter(AbstractControl<dynamic> control) {
    var value = (control.value as String?) ?? '';
    if (value.trim().isEmpty) {
      return null;
    }
    var issue = RecorderRules.validateFilter(value.trim());
    return issue == null ? null : {'filter.${issue.name}': true};
  }

  // optional limits: empty means no limit, Validators.min would reject that
  static Map<String, dynamic>? _positiveOrEmpty(AbstractControl<dynamic> control) {
    var value = control.value as int?;
    return value == null || value >= 1 ? null : {ValidationMessage.min: true};
  }

  static Map<String, dynamic>? _atLeastOneInclude(AbstractControl<dynamic> control) {
    var groups = (control as FormArray).controls.cast<FormGroup>();
    var hasInclude = groups.any((group) => group.control(excludeField).value != true);
    return hasInclude ? null : {'noinclude': true};
  }

  static Map<String, dynamic>? _validateDuration(AbstractControl<dynamic> control) {
    var value = ((control.value as String?) ?? '').trim();
    if (value.isEmpty) {
      return null;
    }
    try {
      return DurationParser.parse(value).inSeconds > 0 ? null : {'duration': true};
    } on FormatException {
      return {'duration': true};
    }
  }

  // 8h, 90m or 45s, as typed in the dialog
  static String _compact(int seconds) {
    if (seconds % 3600 == 0) {
      return '${seconds ~/ 3600}h';
    }
    if (seconds % 60 == 0) {
      return '${seconds ~/ 60}m';
    }
    return '${seconds}s';
  }
}
