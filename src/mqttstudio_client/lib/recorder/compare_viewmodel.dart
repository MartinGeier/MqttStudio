import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/utils/json_path.dart';
import 'package:mqttstudio/recorder/model/compare_options.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/tools/recording_comparer.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the COMPARE tab (doc/recorder-design.md §9): the selected recording is A, B is picked here
class CompareViewmodel extends SrxChangeNotifier {
  static const String recordingField = 'recording';
  static const String countsField = 'counts';
  static const String payloadsField = 'payloads';
  static const String timingField = 'timing';
  static const String countToleranceField = 'countTolerance';
  static const String numberToleranceField = 'numberTolerance';
  static const String timingToleranceField = 'timingTolerance';
  static const String ignoreField = 'ignore';
  static const String remapsField = 'remaps';
  static const String rangeField = 'range';

  final _library = GetIt.I.get<RecordingLibrary>();
  late final FormGroup form = FormGroup({
    recordingField: FormControl<String>(validators: [Validators.required]),
    countsField: FormControl<bool>(value: true),
    payloadsField: FormControl<bool>(value: true),
    timingField: FormControl<bool>(value: true),
    countToleranceField: FormControl<double>(value: 0, validators: [Validators.required, Validators.min(0)]),
    numberToleranceField: FormControl<double>(value: 0, validators: [Validators.required, Validators.min(0)]),
    timingToleranceField: FormControl<double>(value: 10, validators: [Validators.required, Validators.min(0)]),
    ignoreField: FormControl<String>(value: '', validators: [Validators.delegate(_validatePaths)]),
    remapsField: FormControl<String>(value: '', validators: [Validators.delegate(_validateRemaps)]),
    rangeField: FormControl<bool>(value: false),
  });
  late final StreamSubscription _subscription;

  RecordingInfo? _info;
  int? _rangeFrom;
  int? _rangeTo;
  List<RecordingInfo> candidates = [];
  CompareResult? result;
  bool isRunning = false;
  double progress = 0;
  String? error;
  bool _disposed = false;

  CompareViewmodel() {
    _subscription = form.valueChanges.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }

  RecordingInfo? get info => _info;

  bool get hasRange => _rangeFrom != null || _rangeTo != null;

  Future<void> show(RecordingInfo info, {int? rangeFrom, int? rangeTo}) async {
    if (_info?.id != info.id) {
      result = null;
      error = null;
    }
    _info = info;
    _rangeFrom = rangeFrom;
    _rangeTo = rangeTo;
    var all = await _library.list();
    if (_disposed) {
      return;
    }
    candidates = all.where((other) => other.id != info.id).toList();
    var chosen = form.control(recordingField).value as String?;
    if (chosen != null && !candidates.any((other) => other.id == chosen)) {
      form.control(recordingField).value = null;
    }
    if (!hasRange) {
      form.control(rangeField).value = false;
    }
    notifyListeners();
  }

  Future<void> compare() async {
    form.markAllAsTouched();
    if (!form.valid || _info == null || isRunning) {
      notifyListeners();
      return;
    }
    var b = candidates.firstWhere((other) => other.id == form.control(recordingField).value);
    var onlyRange = hasRange && (form.control(rangeField).value as bool? ?? false);
    var options = CompareOptions(
      remaps: _remaps(form.control(remapsField).value as String?),
      counts: form.control(countsField).value as bool? ?? true,
      countTolerance: (form.control(countToleranceField).value as num).toDouble(),
      payloads: form.control(payloadsField).value as bool? ?? true,
      ignorePaths: _paths(form.control(ignoreField).value as String?),
      numberTolerance: (form.control(numberToleranceField).value as num).toDouble(),
      timing: form.control(timingField).value as bool? ?? true,
      timingTolerance: (form.control(timingToleranceField).value as num).toDouble(),
      rangeAFromMicros: onlyRange ? _rangeFrom : null,
      rangeAToMicros: onlyRange ? _rangeTo : null,
    );
    isRunning = true;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      var comparer = RecordingComparer(_library, onProgress: (value) {
        progress = value;
        if (!_disposed) {
          notifyListeners();
        }
      });
      result = await comparer.compare(_info!, b, options);
    } catch (exc) {
      error = exc.toString();
    }
    isRunning = false;
    if (!_disposed) {
      notifyListeners();
    }
  }

  static List<String> _paths(String? text) =>
      (text ?? '').split(',').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();

  // "test/=prod/, a/=b/"
  static List<TopicRemap> _remaps(String? text) => [
        for (var part in _paths(text))
          TopicRemap(part.substring(0, part.indexOf('=')).trim(), part.substring(part.indexOf('=') + 1).trim())
      ];

  static Map<String, dynamic>? _validatePaths(AbstractControl<dynamic> control) =>
      _paths(control.value as String?).every((path) => JsonPath.tryParse(path) != null) ? null : {'jsonpath': true};

  static Map<String, dynamic>? _validateRemaps(AbstractControl<dynamic> control) =>
      _paths(control.value as String?).every((part) => part.indexOf('=') > 0) ? null : {'remap': true};
}
