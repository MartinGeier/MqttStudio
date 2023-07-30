import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:mqttstudio/project/message_buffer_viewmodel.dart';
import 'package:mqttstudio/common/mqtt_global_viewmodel.dart';
import 'package:srx_flutter/srx_flutter.dart';

class ProjectGlobalViewmodel extends SrxChangeNotifier {
  Project? _currentProject;
  MessageBufferViewmodel messageBufferViewmodel = MessageBufferViewmodel();
  late MqttGlobalViewmodel _mqttGlobalViewmodel;
  var closeProjectStreamController = StreamController.broadcast();
  bool _paused = false;
  int? lastSavedProjectHash;
  Future Function() _onClosingNotSaved;

  ProjectGlobalViewmodel(this._onClosingNotSaved) {
    _mqttGlobalViewmodel = GetIt.I.get<MqttGlobalViewmodel>();
    _mqttGlobalViewmodel.onConnected = onMqttConntected;
    _mqttGlobalViewmodel.onMessageReceived = onMessageReceived;
  }

  Project? get currentProject => _currentProject;

  bool get isProjectOpen => _currentProject != null;

  Future openProject(Project? newProject) async {
    await closeProject(true);

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
    if (newProject?.lastUsed != null) {
      _currentProject?.lastUsed = DateTime.now();
      await saveProject();
    } else {
      _currentProject?.lastUsed = DateTime.now();
    }

    // keep the hash to check for changes
    lastSavedProjectHash = _currentProject?.getHash();

    notifyListeners();
  }

  Future<bool> closeProject([bool forceSave = false]) async {
    if (forceSave) {
      await saveProject();
    } else if (hasProjectChanged()) {
      var result = await _onClosingNotSaved();

      if (result == null) {
        return false;
      } else if (result != null && result) {
        await saveProject();
      }
    }

    _mqttGlobalViewmodel.disconnect();
    messageBufferViewmodel.clear();
    closeProjectStreamController.add(null);
    _currentProject = null;
    lastSavedProjectHash = null;
    notifyListeners();
    return true;
  }

  Future saveProject() async {
    if (currentProject != null) {
      await LocalStore().saveProject(currentProject!);
    }
  }

  bool hasProjectChanged() {
    return currentProject?.getHash() != lastSavedProjectHash;
  }

  void addTopicSubscription(TopicSubscription subscription) {
    assert(isProjectOpen);
    if (_currentProject!.topicSubscriptions.any((x) => x.topic == subscription.topic)) {
      throw SrxServiceException('Trying to add duplicate topic \'${subscription.topic}\'', ServiceError.DuplicateTopic);
    }
    _currentProject!.topicSubscriptions.add(subscription);
    _currentProject!.topicColors[subscription.topic] = subscription.color;
    _addRecentTopic(subscription.topic);

    if (_mqttGlobalViewmodel.isConnected() && !_paused) {
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
    } else if (!_paused) {
      _mqttGlobalViewmodel.subscribeToTopic(topic, sub.qos);
    }
    notifyListeners();
  }

  void pauseAllTopics() {
    _paused = true;
    for (var sub in _currentProject!.topicSubscriptions) {
      _mqttGlobalViewmodel.unSubscribeFromTopic(sub.topic);
    }
    notifyListeners();
  }

  void playAllTopics() {
    _paused = false;
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

  void publishTopic(String topic, dynamic payload, MqttPayloadType payloadType, bool retain, [MqttQos qos = MqttQos.atMostOnce]) {
    _mqttGlobalViewmodel.publishTopic(topic, payload, payloadType, retain, qos);
    _addRecentTopic(topic);
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

  void _addRecentTopic(String topic) {
    assert(isProjectOpen);

    if (!currentProject!.recentTopics.contains(topic)) {
      currentProject!.recentTopics.insert(0, topic);
    }

    if (currentProject!.recentTopics.length > 20) {
      _currentProject!.recentTopics.removeLast();
    }
  }
}
