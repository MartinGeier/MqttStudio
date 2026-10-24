import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/message_viewer/message_viewer.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

class DiscoverRequest {
  final DiscoverySettings settings;
  final DiscoverySource source;
  final RecordingInfo? recording;

  DiscoverRequest(this.settings, this.source, this.recording);
}

// Viewmodel of the dialog that starts a discovery (doc/documentation-design.md §12.5)
class DiscoverViewmodel extends SrxChangeNotifier {
  static const String sourceField = 'source';
  static const String recordingField = 'recording';
  static const String filtersField = 'filters';
  static const String filterField = 'filter';
  static const String excludeField = 'exclude';
  static const String stopField = 'stop';
  static const String durationField = 'duration';
  static const String maxMessagesField = 'maxMessages';
  static const String detectTemplatesField = 'detectTemplates';
  static const String inferSchemasField = 'inferSchemas';
  static const String keepExamplesField = 'keepExamples';
  static const String ignoreSysField = 'ignoreSys';

  final _projectManager = GetIt.I.get<ProjectManager>();
  late final FormGroup form;
  List<RecordingInfo> recordings = [];
  final List<StreamSubscription> _subscriptions = [];

  DiscoverViewmodel({DiscoverySource source = DiscoverySource.live, String? recordingId}) {
    var documentation = _projectManager.currentProject?.documentation;
    var settings = documentation?.discoverySettings ?? DiscoverySettings();
    // only the filters of an applied discovery are remembered; otherwise one empty filter to fill in
    var filters =
        documentation?.lastDiscoveryAt != null && settings.filters.isNotEmpty ? settings.filters : [RecorderFilter('')];
    form = FormGroup({
      sourceField: FormControl<DiscoverySource>(value: source),
      recordingField: FormControl<String>(value: recordingId, validators: [Validators.delegate(_validateRecording)]),
      filtersField: FormArray<Map<String, Object?>>(
          [for (var filter in filters) _filterGroup(filter.filter, filter.exclude)],
          validators: [Validators.delegate(_validateIncludes)]),
      stopField: FormControl<DiscoveryStop>(value: settings.stop),
      durationField: FormControl<int>(
          value: (settings.durationSeconds / 60).ceil(),
          validators: [Validators.required, Validators.min(1), Validators.max(1440)]),
      maxMessagesField: FormControl<int>(
          value: settings.maxMessages, validators: [Validators.required, Validators.min(1), Validators.max(10000000)]),
      detectTemplatesField: FormControl<bool>(value: settings.detectTemplates),
      inferSchemasField: FormControl<bool>(value: settings.inferSchemas),
      keepExamplesField: FormControl<bool>(value: settings.keepExamples),
      ignoreSysField: FormControl<bool>(value: settings.ignoreSys),
    });
    _updateStopControls();
    _subscriptions.add(form.control(sourceField).valueChanges.listen((_) {
      form.control(recordingField).updateValueAndValidity();
      _updateStopControls();
      notifyListeners();
    }));
    _subscriptions.add(form.control(stopField).valueChanges.listen((_) => notifyListeners()));
    unawaited(_loadRecordings());
  }

  @override
  void dispose() {
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  DiscoverySource get source => form.control(sourceField).value as DiscoverySource;

  DiscoveryStop get stop => form.control(stopField).value as DiscoveryStop;

  bool get isLive => source == DiscoverySource.live;

  // host:port and protocol of the project's broker
  String get broker {
    var settings = _projectManager.currentProject?.mqttSettings;
    return settings == null
        ? ''
        : '${settings.hostname}:${settings.port} · ${settings.isMqtt5 ? 'MQTT 5' : 'MQTT 3.1.1'}';
  }

  int get bufferedMessages => GetIt.I.get<MessageViewer>().messageBuffer.length;

  FormArray<Map<String, Object?>> get filters => form.control(filtersField) as FormArray<Map<String, Object?>>;

  // a recording and the topic viewer are read to the end, so the stop settings only apply to a live discovery. They
  // stay visible but disabled, and the dialog keeps its height on every source.
  void _updateStopControls() {
    for (var name in [stopField, durationField, maxMessagesField]) {
      if (isLive) {
        form.control(name).markAsEnabled();
      } else {
        form.control(name).markAsDisabled();
      }
    }
  }

  void addFilter() {
    filters.add(_filterGroup('', false));
    notifyListeners();
  }

  void removeFilter(int index) {
    filters.removeAt(index);
    notifyListeners();
  }

  Future<void> _loadRecordings() async {
    var library = GetIt.I.isRegistered<RecordingLibrary>() ? GetIt.I.get<RecordingLibrary>() : null;
    recordings = await library?.list() ?? [];
    recordings.sort((a, b) => b.header.startedAt.compareTo(a.header.startedAt));
    form.control(recordingField).updateValueAndValidity();
    notifyListeners();
  }

  FormGroup _filterGroup(String filter, bool exclude) => FormGroup({
        filterField:
            FormControl<String>(value: filter, validators: [Validators.required, Validators.delegate(_validateFilter)]),
        excludeField: FormControl<bool>(value: exclude),
      });

  static Map<String, dynamic>? _validateFilter(AbstractControl<dynamic> control) {
    var value = control.value as String?;
    if (value == null || value.isEmpty) {
      return null;
    }
    var issue = RecorderRules.validateFilter(value.trim());
    return issue == null ? null : {'filter.${issue.name}': true};
  }

  // runs while the form is built too, before it has a parent
  static Map<String, dynamic>? _validateRecording(AbstractControl<dynamic> control) {
    var source = (control.parent as FormGroup?)?.control(sourceField).value;
    return source == DiscoverySource.recording && control.value == null ? {'required': true} : null;
  }

  static Map<String, dynamic>? _validateIncludes(AbstractControl<dynamic> control) {
    var rows = (control as FormArray<Map<String, Object?>>).value ?? [];
    return rows.any((row) => row?[excludeField] != true) ? null : {'noinclude': true};
  }

  // the request, or null while the form is invalid
  DiscoverRequest? save() {
    if (!form.valid) {
      form.markAllAsTouched();
      return null;
    }
    bool flag(String name) => form.control(name).value == true;
    var settings = DiscoverySettings(
        filters: [
          for (var group in filters.controls.cast<FormGroup>())
            RecorderFilter(((group.control(filterField).value as String?) ?? '').trim(),
                exclude: group.control(excludeField).value == true, qos: MqttQos.exactlyOnce)
        ],
        stop: stop,
        durationSeconds: (form.control(durationField).value as int) * 60,
        maxMessages: form.control(maxMessagesField).value as int,
        detectTemplates: flag(detectTemplatesField),
        inferSchemas: flag(inferSchemasField),
        keepExamples: flag(keepExamplesField),
        ignoreSys: flag(ignoreSysField));
    var recordingId = form.control(recordingField).value as String?;
    var recording = recordings.where((info) => info.id == recordingId).firstOrNull;
    return DiscoverRequest(settings, source, source == DiscoverySource.recording ? recording : null);
  }
}
