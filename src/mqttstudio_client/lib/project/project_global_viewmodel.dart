import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:mqttstudio/topic_viewer/message_buffer_viewmodel.dart';
import 'package:mqttstudio/common/mqtt_global_viewmodel.dart';
import 'package:srx_flutter/srx_flutter.dart';

class ProjectGlobalViewmodel extends SrxChangeNotifier {
  Project? _currentProject;
  MessageBufferViewmodel messageBufferViewmodel = MessageBufferViewmodel();
  late MqttGlobalViewmodel _mqttGlobalViewmodel;
  bool paused = false;

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
    _currentProject!.topicColors[subscription.topic] = subscription.color;

    if (_mqttGlobalViewmodel.isConnected() && !paused) {
      _mqttGlobalViewmodel.subscribeToTopic(subscription.topic, subscription.qos);
    }

    notifyListeners();
  }

  void removeTopicSubscription(String topic) {
    assert(isProjectOpen);
    if (_mqttGlobalViewmodel.isConnected()) {
      _mqttGlobalViewmodel.unSubscribeFromTopic(topic);
    }

    _currentProject!.topicSubscriptions.removeWhere((x) => x.topic == topic);
    notifyListeners();
  }

  void tooglePauseTopicSubscription(String topic) {
    assert(isProjectOpen);
    var sub = _currentProject!.topicSubscriptions.singleWhere((x) => x.topic == topic);
    sub.paused = !sub.paused;
    if (sub.paused) {
      _mqttGlobalViewmodel.unSubscribeFromTopic(topic);
    } else if (!paused) {
      _mqttGlobalViewmodel.subscribeToTopic(topic, sub.qos);
    }
    notifyListeners();
  }

  void pauseAllTopics() {
    paused = true;
    for (var sub in _currentProject!.topicSubscriptions) {
      _mqttGlobalViewmodel.unSubscribeFromTopic(sub.topic);
    }
    notifyListeners();
  }

  void playAllTopics() {
    paused = false;
    for (var sub in _currentProject!.topicSubscriptions) {
      if (!sub.paused) {
        _mqttGlobalViewmodel.subscribeToTopic(sub.topic, sub.qos);
      }
    }
    notifyListeners();
  }

  void clearMessages() {
    messageBufferViewmodel.clear();
  }

  void publishTopic(String topic, String payload, MqttPayloadType payloadType, bool retain) {
    _mqttGlobalViewmodel.publishTopic(topic, payload, payloadType, retain);
  }

  void onMqttConntected() {
    // subscribe to all topics
    if (_currentProject != null) {
      for (var sub in _currentProject!.topicSubscriptions) {
        if (!sub.paused) {
          _mqttGlobalViewmodel.subscribeToTopic(sub.topic, sub.qos);
        }
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
