import 'dart:async';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the dialog that renames the topics of a recording into a new recording
class RenameTopicsViewmodel extends SrxChangeNotifier {
  static const String remapsField = 'remaps';
  static const String fromField = 'from';
  static const String toField = 'to';
  static const int previewCount = 5;

  final List<String> topics;
  late final FormGroup form = FormGroup({
    remapsField: FormArray<Map<String, Object?>>([_remapGroup('', '')]),
  });
  late final StreamSubscription _subscription;

  RenameTopicsViewmodel(this.topics) {
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

  List<TopicRemap> get _entered => [
        for (var group in remaps.controls.cast<FormGroup>())
          TopicRemap((group.control(fromField).value as String?) ?? '', (group.control(toField).value as String?) ?? '')
      ];

  // the first topics before and after renaming
  List<(String, String)> get preview {
    var options = PlaybackOptions(remaps: _entered);
    return [for (var topic in topics.take(previewCount)) (topic, options.remap(topic))];
  }

  List<TopicRemap>? save() {
    form.markAllAsTouched();
    if (!form.valid) {
      return null;
    }
    return _entered;
  }

  FormGroup _remapGroup(String from, String to) => FormGroup({
        fromField: FormControl<String>(value: from, validators: [Validators.required]),
        toField: FormControl<String>(value: to, validators: [Validators.delegate(_validateTarget)]),
      });

  // a topic must not get wildcards
  static Map<String, dynamic>? _validateTarget(AbstractControl<dynamic> control) {
    var value = (control.value as String?) ?? '';
    return value.contains('#') || value.contains('+') ? {'wildcard': true} : null;
  }
}
