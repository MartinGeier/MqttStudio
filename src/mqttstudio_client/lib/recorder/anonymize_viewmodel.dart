import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/model/anonymize_rule.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the anonymize dialog: a list of rules, applied in order, that can be loaded from and saved to a file
class AnonymizeViewmodel extends SrxChangeNotifier {
  static const String rulesField = 'rules';
  static const String propertiesField = 'properties';
  static const String filterField = 'filter';
  static const String targetField = 'target';
  // the JSON path or the topic level, depending on the target
  static const String detailField = 'detail';
  static const String actionField = 'action';
  // the fixed value or the jitter percent, depending on the action
  static const String valueField = 'value';

  late final FormGroup form;
  late final StreamSubscription _subscription;
  // a message for the user after loading or saving rules failed
  void Function(String message)? onFileError;

  AnonymizeViewmodel(List<AnonymizeRule> rules) {
    form = FormGroup({
      rulesField: FormArray<Map<String, Object?>>([
        for (var rule in rules.isEmpty ? [AnonymizeRule('#', AnonymizeTarget.wholePayload, AnonymizeAction.hash)] : rules)
          _ruleGroup(rule)
      ]),
      propertiesField: FormControl<bool>(value: false),
    });
    _subscription = form.valueChanges.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  FormArray<Map<String, Object?>> get rules => form.control(rulesField) as FormArray<Map<String, Object?>>;

  List<FormGroup> get groups => rules.controls.cast<FormGroup>();

  AnonymizeTarget targetOf(FormGroup group) => group.control(targetField).value as AnonymizeTarget? ?? AnonymizeTarget.jsonPath;

  AnonymizeAction actionOf(FormGroup group) => group.control(actionField).value as AnonymizeAction? ?? AnonymizeAction.hash;

  bool needsValue(FormGroup group) =>
      actionOf(group) == AnonymizeAction.fixed || actionOf(group) == AnonymizeAction.jitterNumber;

  void addRule() {
    rules.add(_ruleGroup(AnonymizeRule('#', AnonymizeTarget.wholePayload, AnonymizeAction.hash)));
    notifyListeners();
  }

  void removeRule(int index) {
    rules.removeAt(index);
    notifyListeners();
  }

  // null when a rule is incomplete; the field with the problem shows an error then
  ({List<AnonymizeRule> rules, bool properties})? save() {
    form.markAllAsTouched();
    if (!form.valid) {
      return null;
    }
    var result = <AnonymizeRule>[];
    var valid = true;
    for (var group in groups) {
      var rule = _ruleOf(group);
      var problem = rule.problem;
      if (problem == 'jsonPath' || problem == 'level') {
        group.control(detailField).setErrors({problem!: true});
        valid = false;
      } else if (problem == 'percent') {
        group.control(valueField).setErrors({problem!: true});
        valid = false;
      }
      result.add(rule);
    }
    if (!valid) {
      notifyListeners();
      return null;
    }
    return (rules: result, properties: form.control(propertiesField).value as bool? ?? false);
  }

  Future<void> loadRules() async {
    var picked = await FilePicker.pickFiles(
        dialogTitle: 'anonymize.load.title'.tr(), type: FileType.custom, allowedExtensions: ['json'], withData: true);
    var file = picked?.files.single;
    if (file == null) {
      return;
    }
    try {
      var bytes = file.bytes ?? await File(file.path!).readAsBytes();
      var loaded = AnonymizeRule.decodeList(utf8.decode(bytes));
      rules.clear();
      for (var rule in loaded) {
        rules.add(_ruleGroup(rule));
      }
      notifyListeners();
    } on FormatException catch (exc) {
      onFileError?.call('anonymize.load.error'.tr(args: [exc.message]));
    }
  }

  Future<void> saveRules() async {
    var text = AnonymizeRule.encodeList([for (var group in groups) _ruleOf(group)]);
    var bytes = Uint8List.fromList(utf8.encode(text));
    var path = await FilePicker.saveFile(
        dialogTitle: 'anonymize.save.title'.tr(),
        fileName: 'anonymize-rules.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: kIsWeb ? bytes : null);
    if (path != null && !kIsWeb) {
      await File(path).writeAsBytes(bytes);
    }
  }

  AnonymizeRule _ruleOf(FormGroup group) {
    var target = targetOf(group);
    var action = actionOf(group);
    var detail = ((group.control(detailField).value as String?) ?? '').trim();
    var value = ((group.control(valueField).value as String?) ?? '').trim();
    return AnonymizeRule(
      ((group.control(filterField).value as String?) ?? '').trim(),
      target,
      action,
      jsonPath: target == AnonymizeTarget.jsonPath ? detail : null,
      level: target == AnonymizeTarget.topicLevel ? int.tryParse(detail) : null,
      value: action == AnonymizeAction.fixed ? value : null,
      percent: action == AnonymizeAction.jitterNumber ? double.tryParse(value) : null,
    );
  }

  FormGroup _ruleGroup(AnonymizeRule rule) => FormGroup({
        filterField: FormControl<String>(value: rule.topicFilter, validators: [Validators.required, Validators.delegate(_validateFilter)]),
        targetField: FormControl<AnonymizeTarget>(value: rule.target),
        detailField: FormControl<String>(value: rule.jsonPath ?? (rule.level?.toString() ?? '')),
        actionField: FormControl<AnonymizeAction>(value: rule.action),
        valueField: FormControl<String>(value: rule.value ?? (rule.percent?.toString() ?? '')),
      });

  static Map<String, dynamic>? _validateFilter(AbstractControl<dynamic> control) {
    var value = ((control.value as String?) ?? '').trim();
    return value.isEmpty || RecorderRules.validateFilter(value) == null ? null : {'filter': true};
  }
}
