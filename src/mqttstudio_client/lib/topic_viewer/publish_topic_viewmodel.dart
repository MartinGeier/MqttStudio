import 'dart:io';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:typed_data/typed_buffers.dart';
import '../project/project_global_viewmodel.dart';

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
      topicNameField: FormControl<String>(validators: [Validators.required, Validators.maxLength(200)]),
      retainField: FormControl<bool>(),
      payloadField: FormControl<String>(validators: [Validators.maxLength(20000)]),
    });
  }

  Future<bool> publishTopic() async {
    form.markAllAsTouched();
    if (!form.valid) {
      return false;
    }

    GetIt.I.get<ProjectGlobalViewmodel>().publishTopic(form.control(topicNameField).value, form.control(payloadField).value ?? '',
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
        .get<ProjectGlobalViewmodel>()
        .publishTopic(form.control(topicNameField).value, buf, MqttPayloadType.binary, form.control(retainField).value ?? false);

    return true;
  }
}
