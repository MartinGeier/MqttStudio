import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the dialog that adds or edits a recorded device (doc/simulator-design.md §8.3)
class RecordedDeviceViewmodel extends SrxChangeNotifier {
  static const String nameField = 'name';
  static const String recordingField = 'recording';
  static const String instanceCountField = 'instanceCount';
  static const String firstInstanceField = 'firstInstance';
  static const String instanceStartField = 'instanceStart';

  final SimulatedDevice? device;
  final Simulation simulation;
  final _library = GetIt.I.get<RecordingLibrary>();
  late final FormGroup form;
  late final StreamSubscription _subscription;

  List<RecordingInfo> recordings = [];
  bool loading = true;
  PlaybackOptions playback;

  RecordedDeviceViewmodel(this.device, this.simulation)
      : playback = device?.recorded?.playback.copy() ?? PlaybackOptions() {
    form = FormGroup({
      nameField: FormControl<String>(
          value: device?.name ?? '',
          validators: [Validators.required, Validators.maxLength(100), Validators.delegate(_validateName)]),
      recordingField: FormControl<String>(value: device?.recorded?.recordingId, validators: [Validators.required]),
      instanceCountField: FormControl<int>(
          value: device?.instanceCount ?? 1,
          validators: [Validators.required, Validators.min(1), Validators.max(SimulationRules.maxInstances)]),
      firstInstanceField:
          FormControl<int>(value: device?.firstInstance ?? 1, validators: [Validators.required, Validators.min(0)]),
      instanceStartField: FormControl<InstanceStart>(value: device?.recorded?.instanceStart ?? InstanceStart.staggered),
    });
    _subscription = form.valueChanges.listen((_) => notifyListeners());
    form.control(recordingField).valueChanges.listen(_onRecordingChanged);
    _load();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  bool get isNew => device == null;

  Future<void> _load() async {
    recordings = await _library.list();
    var source = device?.recorded;
    if (source != null && recording == null) {
      // found by file name after a copy (D23)
      var byFile = recordings.where((info) => info.fileName == source.fileName).firstOrNull;
      if (byFile != null) {
        form.control(recordingField).value = byFile.id;
      }
    }
    if (form.control(recordingField).value == null && recordings.isNotEmpty) {
      form.control(recordingField).value = recordings.first.id;
      _suggestName();
    }
    loading = false;
    notifyListeners();
  }

  RecordingInfo? get recording =>
      recordings.where((info) => info.id == form.control(recordingField).value).firstOrNull;

  List<String> get topics => List.of(recording?.footer.topics ?? <String>[])..sort();

  bool isTopicPlayed(String topic) => playback.plays(topic);

  void setTopicPlayed(String topic, bool played) {
    var chosen = (playback.topics ?? topics).toSet();
    if (played) {
      chosen.add(topic);
    } else {
      chosen.remove(topic);
    }
    playback.topics = chosen.length == topics.length ? null : topics.where(chosen.contains).toList();
    notifyListeners();
  }

  void setPlayback(PlaybackOptions options) {
    var topicsBefore = playback.topics;
    playback = options..topics = topicsBefore;
    notifyListeners();
  }

  int get _instanceCount => (form.control(instanceCountField).value as int?) ?? 1;

  // the device as entered, for the rules and for saving
  SimulatedDevice _edited() {
    var info = recording;
    var edited = device?.copy() ?? SimulatedDevice(name: '', kind: DeviceKind.recorded);
    return edited
      ..name = ((form.control(nameField).value as String?) ?? '').trim()
      ..kind = DeviceKind.recorded
      ..instanceCount = _instanceCount
      ..firstInstance = (form.control(firstInstanceField).value as int?) ?? 1
      ..topics = []
      ..recorded = info == null
          ? null
          : RecordedSource(
              recordingId: info.id,
              fileName: info.fileName,
              recordingName: info.name,
              playback: playback.copy(),
              instanceStart: form.control(instanceStartField).value as InstanceStart? ?? InstanceStart.staggered);
  }

  // rules the entered device breaks; empty when it can be saved
  List<SimulationIssue> get issues => loading ? [] : SimulationRules.validateRecorded(_edited());

  bool get hasPlayedTopics => topics.any(isTopicPlayed);

  SimulatedDevice? save() {
    form.markAllAsTouched();
    if (!form.valid || issues.isNotEmpty || !hasPlayedTopics) {
      notifyListeners();
      return null;
    }
    return _edited();
  }

  void _onRecordingChanged(Object? _) {
    // while loading, the recording is only found again, it doesn't change
    if (loading || recording == null) {
      return;
    }
    // other recordings have other topics
    playback.topics = null;
    _suggestName();
    notifyListeners();
  }

  void _suggestName() {
    var name = form.control(nameField);
    if (recording != null && ((name.value as String?) ?? '').trim().isEmpty) {
      name.value = _uniqueName(recording!.name);
    }
  }

  String _uniqueName(String name) {
    var candidate = name;
    var number = 2;
    while (SimulationRules.isDuplicateDeviceName(candidate, simulation, exceptId: device?.id)) {
      candidate = '$name $number';
      number++;
    }
    return candidate;
  }

  Map<String, dynamic>? _validateName(AbstractControl<dynamic> control) {
    var name = (control.value as String?) ?? '';
    if (name.trim().isNotEmpty && SimulationRules.isDuplicateDeviceName(name, simulation, exceptId: device?.id)) {
      return {'duplicate': true};
    }
    return null;
  }
}
