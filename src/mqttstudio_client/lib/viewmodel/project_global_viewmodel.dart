import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:mqttstudio/viewmodel/message_buffer_viewmodel.dart';
import 'package:mqttstudio/viewmodel/mqtt_global_viewmodel.dart';
import 'package:srx_flutter/srx_flutter.dart';

class ProjectGlobalViewmodel extends SrxChangeNotifier {
  Project? _currentProject;
  MessageBufferViewmodel messageBufferViewmodel = MessageBufferViewmodel();
  late MqttGlobalViewmodel _mqttGlobalViewmodel;

  ProjectGlobalViewmodel() {
    _mqttGlobalViewmodel = GetIt.I.get<MqttGlobalViewmodel>();
    _mqttGlobalViewmodel.onConnected = onMqttConntected;
    _mqttGlobalViewmodel.onMessageReceived = onMessageReceived;
  }

  Project? get currentProject => _currentProject;

  bool get isProjectOpen => _currentProject != null;

  void openProject(Project? newProject) {
    if (_mqttGlobalViewmodel.isConnected()) {
      if (newProject == null) {
        _mqttGlobalViewmodel.disconnect();
      } else if (_currentProject != null) {
        // if connection setting have been changed than reconnect
        _mqttGlobalViewmodel.disconnect();
        _mqttGlobalViewmodel.connect(newProject.mqttSettings);
      }
    }

    _currentProject = newProject;
    notifyListeners();
  }

  void closeProject() {
    _currentProject = null;
    notifyListeners();
  }

  void addTopicSubscription(TopicSubscription subscription) {
    assert(isProjectOpen);
    if (_currentProject!.topicSubscriptions.any((x) => x.topic == subscription.topic)) {
      throw SrxServiceException('Trying to add duplicate topic \'${subscription.topic}\'', ServiceError.DuplicateTopic);
    }
    _currentProject!.topicSubscriptions.add(subscription);

    if (_mqttGlobalViewmodel.isConnected()) {
      _mqttGlobalViewmodel.subscribeToTopic(subscription.topic, subscription.qos);
    }

    notifyListeners();
  }

  void removeTopicSubscription(String topic) {
    assert(isProjectOpen);
    _currentProject!.topicSubscriptions.removeWhere((x) => x.topic == topic);

    if (_mqttGlobalViewmodel.isConnected()) {
      _mqttGlobalViewmodel.unSubscribeFromTopic(topic);
    }

    notifyListeners();
  }

  void onMqttConntected() {
    // subscribe to all topics
    if (_currentProject != null) {
      for (var sub in _currentProject!.topicSubscriptions) {
        _mqttGlobalViewmodel.subscribeToTopic(sub.topic, sub.qos);
      }
    }
  }

  void onMessageReceived(ReceivedMqttMessage msg) {
    assert(isProjectOpen);

    var sub = TopicSubscription.getTopicSubscriptionMatch(msg.topicName, _currentProject!.topicSubscriptions);
    if (sub != null) {
      _currentProject!.topicColors[msg.topicName] = sub.color;
    } else {
      _currentProject!.topicColors[msg.topicName] = TopicColor(Colors.black);
    }
    messageBufferViewmodel.storeMessage(msg);
  }

  TopicColor getTopicColor(String topicName) {
    assert(isProjectOpen);

    return _currentProject!.topicColors[topicName]!;
  }
}
