import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:easy_localization/easy_localization.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/message_viewer/message_viewer.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/common/utils/payload_decoder.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:typed_data/typed_buffers.dart';

class PublishTopicViewmodel extends SrxChangeNotifier {
  static String topicNameField = 'topicName';
  static String retainField = 'retain';
  static String payloadField = 'payload';
  static String contentTypeField = 'contentType';
  static String responseTopicField = 'responseTopic';
  static String correlationDataField = 'correlationData';
  static String messageExpiryIntervalField = 'messageExpiryInterval';
  static String payloadFormatUtf8Field = 'payloadFormatUtf8';
  static String userPropertiesField = 'userProperties';
  static String userPropertyKeyField = 'key';
  static String userPropertyValueField = 'value';

  // largest message expiry interval MQTT 5 allows (four byte integer)
  static const int maxMessageExpiryInterval = 4294967295;

  late FormGroup form;

  // with a message the form starts with its topic, payload, retain flag and properties, to change and publish again
  PublishTopicViewmodel({ReceivedMqttMessage? message}) {
    form = buildFormGroup();
    if (message != null) {
      _prefill(message);
    }
  }

  void _prefill(ReceivedMqttMessage message) {
    form.control(topicNameField).value = message.topicName;
    form.control(retainField).value = message.retain;
    form.control(payloadField).value = utf8.decode(message.payload, allowMalformed: true);
    var properties = message.properties;
    if (properties == null || !isMqtt5) {
      return;
    }
    form.control(contentTypeField).value = properties.contentType;
    form.control(responseTopicField).value = properties.responseTopic;
    // the field sends text, so binary correlation data is left out
    var correlationData = properties.correlationData;
    if (correlationData != null && PayloadDecoding.isUtf8(correlationData)) {
      form.control(correlationDataField).value = utf8.decode(correlationData);
    }
    form.control(messageExpiryIntervalField).value = properties.messageExpiryInterval;
    form.control(payloadFormatUtf8Field).value = properties.payloadFormatUtf8;
    for (var userProperty in properties.userProperties) {
      addUserProperty();
      var group = userProperties.controls.last as FormGroup;
      group.control(userPropertyKeyField).value = userProperty.key;
      group.control(userPropertyValueField).value = userProperty.value;
    }
  }

  // the message properties are only sent to MQTT 5 brokers
  bool get isMqtt5 => GetIt.I.get<ProjectManager>().currentProject?.mqttSettings.isMqtt5 ?? false;

  FormArray<Map<String, Object?>> get userProperties =>
      form.control(userPropertiesField) as FormArray<Map<String, Object?>>;

  FormGroup buildFormGroup() {
    return FormGroup({
      topicNameField: FormControl<String>(
          validators: [Validators.required, Validators.maxLength(200), Validators.delegate(_excludeMqttWildcards)]),
      retainField: FormControl<bool>(),
      payloadField: FormControl<String>(validators: [Validators.maxLength(20000)]),
      contentTypeField: FormControl<String>(validators: [Validators.maxLength(200)]),
      responseTopicField: FormControl<String>(
          validators: [Validators.maxLength(200), Validators.delegate(_excludeMqttWildcards)]),
      correlationDataField: FormControl<String>(validators: [Validators.maxLength(1000)]),
      messageExpiryIntervalField: FormControl<int>(validators: [Validators.delegate(_validateMessageExpiryInterval)]),
      payloadFormatUtf8Field: FormControl<bool>(value: false),
      userPropertiesField: FormArray<Map<String, Object?>>([]),
    });
  }

  void addUserProperty() {
    userProperties.add(FormGroup({
      userPropertyKeyField: FormControl<String>(validators: [Validators.required, Validators.maxLength(200)]),
      userPropertyValueField: FormControl<String>(validators: [Validators.maxLength(1000)]),
    }));
    notifyListeners();
  }

  void removeUserProperty(int index) {
    userProperties.removeAt(index);
    notifyListeners();
  }

  Future<bool> publishTopic() async {
    form.markAllAsTouched();
    if (!form.valid) {
      return false;
    }

    GetIt.I.get<MessageViewer>().publishTopic(form.control(topicNameField).value, form.control(payloadField).value ?? '',
        MqttPayloadType.string, form.control(retainField).value ?? false, MqttQos.atLeastOnce, buildProperties());

    return true;
  }

  Future<bool> publishTopicFromFile(String filePath) async {
    form.markAllAsTouched();
    if (!form.valid) {
      return false;
    }

    var bytes = await File.fromUri(Uri.file(filePath, windows: true)).readAsBytes();
    if (bytes.length > 500000) {
      return throw Exception();
    }

    var buf = Uint8Buffer();
    buf.addAll(bytes);
    GetIt.I.get<MessageViewer>().publishTopic(form.control(topicNameField).value, buf, MqttPayloadType.binary,
        form.control(retainField).value ?? false, MqttQos.atLeastOnce, buildProperties());

    return true;
  }

  // null for MQTT 3.1.1 projects, there the fields are disabled and must not be sent
  MqttMessageProperties? buildProperties() {
    if (!isMqtt5) {
      return null;
    }

    String? correlationData = _nullIfEmpty(form.control(correlationDataField).value);
    return MqttMessageProperties(
      contentType: _nullIfEmpty(form.control(contentTypeField).value),
      responseTopic: _nullIfEmpty(form.control(responseTopicField).value),
      correlationData: correlationData == null ? null : Uint8List.fromList(utf8.encode(correlationData)),
      messageExpiryInterval: form.control(messageExpiryIntervalField).value,
      payloadFormatUtf8: form.control(payloadFormatUtf8Field).value ?? false,
      userProperties: userProperties.controls
          .map((group) => (group as FormGroup))
          .map((group) => MqttUserPropertyEntry(
              group.control(userPropertyKeyField).value ?? '', group.control(userPropertyValueField).value ?? ''))
          .toList(),
    );
  }

  static String? _nullIfEmpty(String? value) => value == null || value.isEmpty ? null : value;

  // the expiry is optional, Validators.min and max would reject an empty field
  Map<String, dynamic>? _validateMessageExpiryInterval(AbstractControl<dynamic> control) {
    final int? value = control.value;
    if (value == null) {
      return null;
    }
    if (value < 0) {
      return {ValidationMessage.min: value};
    }
    if (value > maxMessageExpiryInterval) {
      return {ValidationMessage.max: value};
    }
    return null;
  }

  // Validator function to exclude MQTT wildcards
  Map<String, dynamic>? _excludeMqttWildcards(AbstractControl<dynamic> control) {
    final String? value = control.value;

    if (value == null || value.isEmpty) {
      return null; // Valid if the field is empty
    }

    // Check if the value contains '+' or '#'
    if (value.contains('+') || value.contains('#')) {
      return {'publishtopicdialog.wildcardsError'.tr(): '(+, #)'};
    }

    return null; // Valid
  }
}
