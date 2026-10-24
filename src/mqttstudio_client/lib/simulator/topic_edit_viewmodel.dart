import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/simulator/engine/placeholders.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/generator_editor_model.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the dialog that adds or edits a simulated topic
class TopicEditViewmodel extends SrxChangeNotifier {
  static const String topicField = 'topic';
  static const String intervalField = 'interval';
  static const String upToField = 'upTo';
  static const String qosField = 'qos';
  static const String retainField = 'retain';
  static const String contentTypeField = 'contentType';
  static const String messageExpiryField = 'messageExpiry';
  static const String userPropertiesField = 'userProperties';
  static const String userPropertyKeyField = 'key';
  static const String userPropertyValueField = 'value';

  // largest message expiry interval MQTT 5 allows (four byte integer)
  static const int maxMessageExpiry = 4294967295;

  final SimulatedDevice device;
  final SimulatedTopic? topic;
  late final FormGroup form;
  late final GeneratorEditorModel generator;

  TopicEditViewmodel(this.device, this.topic) {
    var initial = topic ??
        SimulatedTopic(
            topic: device.instanceCount > 1 ? 'simulator/{n}/value' : 'simulator/value',
            generator: const RandomWalkGenerator());
    generator = GeneratorEditorModel(initial.generator);
    form = FormGroup({
      topicField: FormControl<String>(value: initial.topic, validators: [
        Validators.required,
        Validators.maxLength(200),
        Validators.delegate(_validateTopic),
      ]),
      intervalField: FormControl<int>(
          value: initial.interval.minMs, validators: [Validators.required, Validators.min(SimulationRules.minIntervalMs)]),
      upToField: FormControl<int>(
          value: initial.interval.isRandom ? initial.interval.maxMs : null, validators: [Validators.delegate(_validateUpTo)]),
      qosField: FormControl<MqttQos>(value: initial.qos),
      retainField: FormControl<bool>(value: initial.retain),
      contentTypeField: FormControl<String>(value: initial.mqtt5.contentType, validators: [Validators.maxLength(200)]),
      messageExpiryField:
          FormControl<int>(value: initial.mqtt5.messageExpirySeconds, validators: [Validators.delegate(_validateExpiry)]),
      userPropertiesField: FormArray<Map<String, Object?>>([
        for (var property in initial.mqtt5.userProperties) _userPropertyGroup(property.key, property.value),
      ]),
    });
    _subscriptions.add(
        form.control(intervalField).valueChanges.listen((_) => form.control(upToField).updateValueAndValidity()));
    _subscriptions.add(form.valueChanges.listen((_) => notifyListeners()));
  }

  final List<StreamSubscription> _subscriptions = [];

  @override
  void dispose() {
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    generator.dispose();
    super.dispose();
  }

  bool get isNew => topic == null;

  // MQTT 5 properties are only sent to MQTT 5 brokers
  bool get isMqtt5 => GetIt.I.get<ProjectManager>().currentProject?.mqttSettings.isMqtt5 ?? false;

  FormArray<Map<String, Object?>> get userProperties =>
      form.control(userPropertiesField) as FormArray<Map<String, Object?>>;

  String get topicText => (form.control(topicField).value as String?) ?? '';

  // the topics of the first and the last instance
  String get resolvedRange {
    var first = Placeholders.resolve(topicText, instance: device.firstInstance, deviceName: device.name);
    if (device.instanceCount == 1) {
      return first;
    }
    var last = Placeholders.resolve(topicText, instance: device.lastInstance, deviceName: device.name);
    return '$first … $last';
  }

  Duration get previewInterval => Duration(milliseconds: (form.control(intervalField).value as int?) ?? 1000);

  // a short summary of the MQTT tab for the dialog subtitle
  String get mqttSummary {
    var parts = <String>['QoS ${_qosNumber(form.control(qosField).value as MqttQos)}'];
    if (form.control(retainField).value == true) {
      parts.add('simulator.topicdialog.retained.summary'.tr());
    }
    if (userProperties.controls.isNotEmpty) {
      parts.add('simulator.topicdialog.userproperties.summary'.tr(args: ['${userProperties.controls.length}']));
    }
    return parts.join(', ');
  }

  static String _qosNumber(MqttQos qos) => qos == MqttQos.exactlyOnce ? '2' : (qos == MqttQos.atLeastOnce ? '1' : '0');

  bool get payloadTabValid =>
      form.control(topicField).valid && form.control(intervalField).valid && form.control(upToField).valid;

  void addUserProperty() {
    userProperties.add(_userPropertyGroup('', ''));
    notifyListeners();
  }

  void removeUserProperty(int index) {
    userProperties.removeAt(index);
    notifyListeners();
  }

  // the edited topic, or null when the form is not valid
  SimulatedTopic? save() {
    form.markAllAsTouched();
    var generatorValid = generator.validate();
    if (!form.valid || !generatorValid) {
      notifyListeners();
      return null;
    }
    var minMs = form.control(intervalField).value as int;
    var upTo = form.control(upToField).value as int?;
    String? contentType = form.control(contentTypeField).value as String?;
    return SimulatedTopic(
      id: topic?.id,
      topic: topicText.trim(),
      generator: generator.build(),
      qos: form.control(qosField).value as MqttQos,
      retain: form.control(retainField).value == true,
      interval: PublishInterval(minMs: minMs, maxMs: upTo ?? minMs),
      mqtt5: Mqtt5PublishProperties(
        contentType: contentType == null || contentType.trim().isEmpty ? null : contentType.trim(),
        messageExpirySeconds: form.control(messageExpiryField).value as int?,
        userProperties: userProperties.controls
            .map((control) => control as FormGroup)
            .map((group) => SimulatedUserProperty(
                (group.control(userPropertyKeyField).value as String?) ?? '',
                (group.control(userPropertyValueField).value as String?) ?? ''))
            .toList(),
      ),
    );
  }

  static FormGroup _userPropertyGroup(String key, String value) => FormGroup({
        userPropertyKeyField: FormControl<String>(value: key, validators: [Validators.required, Validators.maxLength(200)]),
        userPropertyValueField: FormControl<String>(value: value, validators: [Validators.maxLength(1000)]),
      });

  Map<String, dynamic>? _validateTopic(AbstractControl<dynamic> control) {
    var value = (control.value as String?) ?? '';
    if (value.isEmpty) {
      return null;
    }
    if (SimulationRules.topicHasWildcard(value)) {
      return {'wildcards': true};
    }
    if (device.instanceCount > 1 && !Placeholders.containsInstance(value)) {
      return {'needsInstance': true};
    }
    return null;
  }

  Map<String, dynamic>? _validateUpTo(AbstractControl<dynamic> control) {
    var upTo = control.value as int?;
    var interval = (control.parent as FormGroup?)?.control(intervalField).value as int?;
    if (upTo != null && interval != null && upTo < interval) {
      return {'upTo': true};
    }
    return null;
  }

  Map<String, dynamic>? _validateExpiry(AbstractControl<dynamic> control) {
    var value = control.value as int?;
    if (value != null && (value < 0 || value > maxMessageExpiry)) {
      return {'expiry': true};
    }
    return null;
  }
}
