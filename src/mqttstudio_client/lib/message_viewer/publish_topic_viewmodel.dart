import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/message_viewer/message_viewer.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:typed_data/typed_buffers.dart';

class PublishTopicViewmodel extends SrxChangeNotifier {
  static String topicNameField = 'topicName';
  static String retainField = 'retain';
  static String payloadField = 'payload';

  late FormGroup form;

  PublishTopicViewmodel() {
    form = buildFormGroup();
  }

  FormGroup buildFormGroup() {
    return FormGroup({
      topicNameField:
          FormControl<String>(validators: [Validators.required, Validators.maxLength(200), Validators.delegate(_excludeMqttWildcards)]),
      retainField: FormControl<bool>(),
      payloadField: FormControl<String>(validators: [Validators.maxLength(20000)]),
    });
  }

  Future<bool> publishTopic() async {
    form.markAllAsTouched();
    if (!form.valid) {
      return false;
    }

    GetIt.I.get<MessageViewer>().publishTopic(form.control(topicNameField).value, form.control(payloadField).value ?? '',
        MqttPayloadType.string, form.control(retainField).value ?? false);

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
    GetIt.I
        .get<MessageViewer>()
        .publishTopic(form.control(topicNameField).value, buf, MqttPayloadType.binary, form.control(retainField).value ?? false);

    return true;
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
