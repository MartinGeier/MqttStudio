import 'dart:async';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/cli/duration_parser.dart';
import 'package:mqttstudio/recorder/engine/recording_player.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the dialog with the playback options of a recording
class PlaybackOptionsViewmodel extends SrxChangeNotifier {
  static const String speedField = 'speed';
  static const String loopField = 'loop';
  static const String fromField = 'from';
  static const String toField = 'to';
  static const String gapsField = 'gaps';
  static const String remapsField = 'remaps';
  static const String remapFromField = 'remapFrom';
  static const String remapToField = 'remapTo';
  static const String snapshotField = 'snapshot';
  static const String retainField = 'retain';
  // -1 = as recorded, else the QoS index
  static const String qosField = 'qos';
  static const String propertiesField = 'properties';
  static const int qosAsRecorded = -1;

  final RecordingInfo recording;
  final PlaybackOptions original;
  final double maxRate;
  late final FormGroup form;
  late final StreamSubscription _subscription;

  PlaybackOptionsViewmodel(this.recording, this.original, {this.maxRate = 1000}) {
    form = FormGroup({
      speedField: FormControl<double>(value: original.speed),
      loopField: FormControl<bool>(value: original.loop),
      fromField: FormControl<String>(value: _text(original.rangeStartMicros), validators: [Validators.delegate(_validateOffset)]),
      toField: FormControl<String>(value: _text(original.rangeEndMicros), validators: [Validators.delegate(_validateOffset)]),
      gapsField: FormControl<String>(
          value: _text(original.compressGapsOverMicros), validators: [Validators.delegate(_validateOffset)]),
      remapsField: FormArray<Map<String, Object?>>([for (var remap in original.remaps) _remapGroup(remap.from, remap.to)]),
      snapshotField: FormControl<RetainedSnapshotMode>(value: original.snapshot),
      retainField: FormControl<RetainOverride>(value: original.retain),
      qosField: FormControl<int>(value: original.qos?.index ?? qosAsRecorded),
      propertiesField: FormControl<bool>(value: original.republishProperties),
    }, validators: [Validators.delegate(_validateRange)]);
    _subscription = form.valueChanges.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  FormArray<Map<String, Object?>> get remaps => form.control(remapsField) as FormArray<Map<String, Object?>>;

  void addRemap() {
    remaps.add(_remapGroup('', ''));
    notifyListeners();
  }

  void removeRemap(int index) {
    remaps.removeAt(index);
    notifyListeners();
  }

  // the first played topic and where it is published to with the entered remapping
  (String, String)? get remapPreview {
    var options = _current();
    for (var topic in recording.footer.topics) {
      if (options.plays(topic)) {
        return (topic, options.remap(topic));
      }
    }
    return null;
  }

  ({double rate, double peak}) get estimate => RecordingPlayer.estimate(recording, _current(), maxRate: maxRate);

  PlaybackOptions? save() {
    form.markAllAsTouched();
    if (!form.valid) {
      return null;
    }
    return _current();
  }

  PlaybackOptions _current() {
    var qos = form.control(qosField).value as int? ?? qosAsRecorded;
    return PlaybackOptions(
      topics: original.topics == null ? null : List.of(original.topics!),
      speed: form.control(speedField).value as double? ?? 1,
      loop: form.control(loopField).value as bool? ?? false,
      rangeStartMicros: _micros(form.control(fromField).value as String?),
      rangeEndMicros: _micros(form.control(toField).value as String?),
      compressGapsOverMicros: _micros(form.control(gapsField).value as String?),
      remaps: [
        for (var group in remaps.controls.cast<FormGroup>())
          if (((group.control(remapFromField).value as String?) ?? '').isNotEmpty)
            TopicRemap(group.control(remapFromField).value as String, (group.control(remapToField).value as String?) ?? '')
      ],
      snapshot: form.control(snapshotField).value as RetainedSnapshotMode? ?? RetainedSnapshotMode.publish,
      retain: form.control(retainField).value as RetainOverride? ?? RetainOverride.asRecorded,
      qos: qos == qosAsRecorded ? null : MqttQos.values[qos],
      republishProperties: form.control(propertiesField).value as bool? ?? true,
    );
  }

  FormGroup _remapGroup(String from, String to) => FormGroup({
        remapFromField: FormControl<String>(value: from, validators: [Validators.delegate(_validateTopicPart)]),
        remapToField: FormControl<String>(value: to, validators: [Validators.delegate(_validateTopicPart)]),
      });

  static String _text(int? micros) {
    if (micros == null) {
      return '';
    }
    var seconds = micros ~/ Duration.microsecondsPerSecond;
    var hours = seconds ~/ 3600;
    var minutes = seconds % 3600 ~/ 60;
    var rest = seconds % 60;
    return [if (hours > 0) '${hours}h', if (minutes > 0) '${minutes}m', if (rest > 0 || seconds == 0) '${rest}s'].join();
  }

  static int? _micros(String? text) {
    var value = (text ?? '').trim();
    if (value.isEmpty) {
      return null;
    }
    try {
      return DurationParser.parse(value).inMicroseconds;
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic>? _validateOffset(AbstractControl<dynamic> control) {
    var value = ((control.value as String?) ?? '').trim();
    if (value.isEmpty) {
      return null;
    }
    try {
      DurationParser.parse(value);
      return null;
    } on FormatException {
      return {'duration': true};
    }
  }

  // a remapped topic must stay a topic, without wildcards
  static Map<String, dynamic>? _validateTopicPart(AbstractControl<dynamic> control) {
    var value = (control.value as String?) ?? '';
    return value.contains('+') || value.contains('#') ? {'wildcard': true} : null;
  }

  // the end of the range must come after its start
  static Map<String, dynamic>? _validateRange(AbstractControl<dynamic> control) {
    var group = control as FormGroup;
    var from = _micros(group.control(fromField).value as String?);
    var to = _micros(group.control(toField).value as String?);
    var toControl = group.control(toField);
    if (from != null && to != null && to <= from) {
      toControl.setErrors({'range': true}, markAsDirty: false);
    } else if (toControl.hasError('range')) {
      toControl.removeError('range');
    }
    return null;
  }
}
