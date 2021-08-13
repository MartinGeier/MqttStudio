import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

import 'project_global_viewmodel.dart';

class AddTopicViewmodel extends SrxChangeNotifier {
  static String topicNameField = 'topicName';
  static String qosField = 'retain';

  late FormGroup form;

  AddTopicViewmodel() {
    form = buildFormGroup();
  }

  FormGroup buildFormGroup() {
    return FormGroup({
      topicNameField: FormControl<String>(validators: [Validators.required, Validators.maxLength(200)]),
      qosField: FormControl<MqttQos>(validators: [Validators.required], value: MqttQos.atLeastOnce),
    });
  }

  bool addTopic() {
    form.markAllAsTouched();
    if (!form.valid) {
      return false;
    }

    TopicSubscription topicSub = TopicSubscription(form.control(topicNameField).value, form.control(qosField).value);
    GetIt.I.get<ProjectGlobalViewmodel>().addTopicSubscription(topicSub);
    return true;
  }
}
