import 'dart:async';
import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/mqtt/viewer_mqtt_service.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel for all project related operations.
class ProjectService {
  Project? _currentProject;
  late ViewerMqttService _viewerMQTTService;
  late MqttAdapter _mqttAdapter;
  final projectOpenedEvent = Event();
  final projectClosedEvent = Event();
  final topicSubscriptionsChangedEvent = Event();
  bool paused = false;
  int? lastSavedProjectHash;
  final Future Function() _onClosingNotSaved;

  ProjectService(this._onClosingNotSaved) {
    _viewerMQTTService = GetIt.I.get<ViewerMqttService>();
    _viewerMQTTService.onMessageReceivedEvent.subscribe((args) => _onMessageReceived(args));
    _mqttAdapter = GetIt.I.get<MqttAdapter>();
    _mqttAdapter.onConnectedEvent.subscribe((args) => _onMqttConntected());
  }

  void dispose() {
    _mqttAdapter.onConnectedEvent.unsubscribeAll();
    _viewerMQTTService.onMessageReceivedEvent.unsubscribeAll();
  }

  Project? get currentProject => _currentProject;

  bool get isProjectOpen => _currentProject != null;

  Future openProject(Project? newProject) async {
    await closeProject(true);

    if (_mqttAdapter.isConnected()) {
      if (newProject == null) {
        _mqttAdapter.disconnect();
      } else if (_currentProject != null) {
        // if connection setting have been changed than reconnect
        _mqttAdapter.disconnect();
        _mqttAdapter.connect(newProject.mqttSettings);
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

    projectOpenedEvent.broadcast();
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

    _viewerMQTTService.clearMessages();
    _mqttAdapter.disconnect();
    projectClosedEvent.broadcast();
    _currentProject = null;
    lastSavedProjectHash = null;
    projectClosedEvent.broadcast();
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

    if (_mqttAdapter.isConnected() && !paused) {
      _viewerMQTTService.subscribeToTopic(subscription.topic, subscription.qos);
    }

    topicSubscriptionsChangedEvent.broadcast();
  }

  void removeTopicSubscription(String topic) {
    assert(isProjectOpen);
    if (_mqttAdapter.isConnected()) {
      _viewerMQTTService.unSubscribeFromTopic(topic);
    }

    _currentProject!.topicSubscriptions.removeWhere((x) => x.topic == topic);
    topicSubscriptionsChangedEvent.broadcast();
  }

  void tooglePauseTopicSubscription(String topic) {
    assert(isProjectOpen);
    var sub = _currentProject!.topicSubscriptions.singleWhere((x) => x.topic == topic);
    sub.paused = !sub.paused;
    if (sub.paused) {
      _viewerMQTTService.unSubscribeFromTopic(topic);
    } else if (!paused) {
      _viewerMQTTService.subscribeToTopic(topic, sub.qos);
    }

    topicSubscriptionsChangedEvent.broadcast();
  }

  void pauseAllTopics() {
    paused = true;
    for (var sub in _currentProject!.topicSubscriptions) {
      _viewerMQTTService.unSubscribeFromTopic(sub.topic);
    }

    topicSubscriptionsChangedEvent.broadcast();
  }

  void playAllTopics() {
    paused = false;
    for (var sub in _currentProject!.topicSubscriptions) {
      if (!sub.paused) {
        _viewerMQTTService.subscribeToTopic(sub.topic, sub.qos);
      }
    }

    topicSubscriptionsChangedEvent.broadcast();
  }

  void clearMessages() {
    _viewerMQTTService.messageBuffer.clear();
  }

  void publishTopic(String topic, dynamic payload, MqttPayloadType payloadType, bool retain, [MqttQos qos = MqttQos.atMostOnce]) {
    _viewerMQTTService.publishTopic(topic, payload, payloadType, retain, qos);
    _addRecentTopic(topic);
  }

  void _onMqttConntected() {
    // subscribe to all topics
    if (_currentProject != null) {
      for (var sub in _currentProject!.topicSubscriptions) {
        if (!sub.paused) {
          _viewerMQTTService.subscribeToTopic(sub.topic, sub.qos);
        }
      }
    }
  }

  void _onMessageReceived(ReceivedMqttMessage msg) {
    assert(isProjectOpen);

    var sub = TopicSubscription.getTopicSubscriptionMatch(msg.topicName, _currentProject!.topicSubscriptions);
    if (sub != null) {
      _currentProject!.topicColors[msg.topicName] = sub.color;
    } else {
      _currentProject!.topicColors[msg.topicName] = TopicColor(Colors.black);
    }
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
