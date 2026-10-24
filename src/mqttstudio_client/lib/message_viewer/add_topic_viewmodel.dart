import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/message_viewer/message_viewer.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

class AddTopicViewmodel extends SrxChangeNotifier {
  static String topicNameField = 'topicName';
  static String qosField = 'qos';
  static String colorField = 'color';
  static String noLocalField = 'noLocal';
  static String retainAsPublishedField = 'retainAsPublished';
  static String retainHandlingField = 'retainHandling';

  late FormGroup form;

  AddTopicViewmodel() {
    form = buildFormGroup();
  }

  // the subscription options are only sent to MQTT 5 brokers
  bool get isMqtt5 => GetIt.I.get<ProjectManager>().currentProject?.mqttSettings.isMqtt5 ?? false;

  FormGroup buildFormGroup() {
    return FormGroup({
      topicNameField:
          FormControl<String>(validators: [Validators.required, Validators.maxLength(200), TopicNameValidator()]),
      qosField: FormControl<MqttQos>(validators: [Validators.required], value: MqttQos.atLeastOnce),
      colorField: FormControl<Color>(validators: [Validators.required], value: TopicColor.random().color),
      noLocalField: FormControl<bool>(value: false),
      retainAsPublishedField: FormControl<bool>(value: false),
      retainHandlingField: FormControl<SubscriptionRetainHandling>(
          validators: [Validators.required], value: SubscriptionRetainHandling.sendOnSubscribe),
    });
  }

  bool addTopic() {
    form.markAllAsTouched();
    if (!form.valid) {
      return false;
    }

    TopicSubscription topicSub = TopicSubscription(form.control(topicNameField).value, form.control(qosField).value,
        color: TopicColor(form.control(colorField).value),
        noLocal: form.control(noLocalField).value ?? false,
        retainAsPublished: form.control(retainAsPublishedField).value ?? false,
        retainHandling: form.control(retainHandlingField).value ?? SubscriptionRetainHandling.sendOnSubscribe);

    GetIt.I.get<MessageViewer>().addTopicSubscription(topicSub);
    return true;
  }
}

/// Validator that validates the topic name is valid
class TopicNameValidator extends Validator<dynamic> {
  TopicNameValidator() : super();

  @override
  Map<String, dynamic>? validate(AbstractControl<dynamic> control) {
    return control.isNotNull && _isValidMultiLevelWildcard(control.value) && _isValidSharedSubscription(control.value)
        ? null
        : {'invalidTopicName': 'Invalid topic name'};
  }

  // MQTT allows at most one '#', and only as the whole last level ('#' or '.../#')
  bool _isValidMultiLevelWildcard(String topic) {
    var index = topic.indexOf('#');
    return index < 0 || (index == topic.length - 1 && (index == 0 || topic[index - 1] == '/'));
  }

  // a shared subscription is '$share/<group>/<filter>', the group must not be empty or contain wildcards
  bool _isValidSharedSubscription(String topic) {
    if (!topic.startsWith(TopicSubscription.sharePrefix)) {
      return true;
    }
    var filterStart = topic.indexOf('/', TopicSubscription.sharePrefix.length);
    if (filterStart < 0 || filterStart == topic.length - 1) {
      return false;
    }
    var group = topic.substring(TopicSubscription.sharePrefix.length, filterStart);
    return group.isNotEmpty && !group.contains('+') && !group.contains('#');
  }
}
