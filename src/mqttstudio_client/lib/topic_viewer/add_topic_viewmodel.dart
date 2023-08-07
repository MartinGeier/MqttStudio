import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

import '../project/project_global_viewmodel.dart';

class AddTopicViewmodel extends SrxChangeNotifier {
  static String topicNameField = 'topicName';
  static String qosField = 'qos';
  static String colorField = 'color';

  late FormGroup form;

  AddTopicViewmodel() {
    form = buildFormGroup();
  }

  FormGroup buildFormGroup() {
    return FormGroup({
      topicNameField: FormControl<String>(validators: [Validators.required, Validators.maxLength(200), TopicNameValidator().validate]),
      qosField: FormControl<MqttQos>(validators: [Validators.required], value: MqttQos.atLeastOnce),
      colorField: FormControl<Color>(validators: [Validators.required], value: TopicColor.random().color),
    });
  }

  bool addTopic() {
    form.markAllAsTouched();
    if (!form.valid) {
      return false;
    }

    TopicSubscription topicSub = TopicSubscription(form.control(topicNameField).value, form.control(qosField).value,
        color: TopicColor(form.control(colorField).value));

    GetIt.I.get<ProjectGlobalViewmodel>().addTopicSubscription(topicSub);
    return true;
  }
}

/// Validator that validates the topic name is valid
class TopicNameValidator extends Validator<dynamic> {
  TopicNameValidator() : super();

  @override
  Map<String, dynamic>? validate(AbstractControl<dynamic> control) {
    return control.isNotNull && ('#'.allMatches(control.value).length) < 2 ? null : {'invalidTopicName': 'Invalid topic name'};
  }
}
