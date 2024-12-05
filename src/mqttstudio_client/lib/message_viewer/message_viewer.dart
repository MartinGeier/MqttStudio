import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/message_viewer/message_buffer.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:srx_flutter/srx_flutter.dart';

import '../model/project.dart';

// Manages MQTT operations for message viewers. Receives messages from MQTTAdapter and offers events for viewmodels.
// Stores all received messages using MessageBuffer
class MessageViewer {
  final _mqttAdapter = GetIt.I.get<MqttAdapter>();
  bool paused = false;
  late ProjectManager _projectManager;
  bool isBusy = false;
  MQTTMessageBuffer messageBuffer = MQTTMessageBuffer();
  final topicSubscriptionsChangedEvent = Event();
  final messageReceivedEvent = Event<ReceivedMqttMessage>();
  final messagesClearedEvent = Event();

  MessageViewer() {
    _projectManager = GetIt.I.get<ProjectManager>();
    _projectManager.projectClosedEvent.subscribe((_) => clearMessages());
    _mqttAdapter.messageReceivedEvent.subscribe((args) => _messageReceived(args));
    _mqttAdapter.onConnectedEvent.subscribe((args) => _onMqttConntected());
  }

  void dispose() {
    _projectManager.projectClosedEvent.unsubscribeAll();
    _mqttAdapter.messageReceivedEvent.unsubscribeAll();
    _mqttAdapter.onConnectedEvent.unsubscribeAll();
  }

  void clearMessages() {
    messageBuffer.clear();
    messagesClearedEvent.broadcast();
  }

  void addTopicSubscription(TopicSubscription subscription) {
    assert(_projectManager.isProjectOpen);
    if (_projectManager.currentProject!.topicSubscriptions.any((x) => x.topic == subscription.topic)) {
      throw SrxServiceException('Trying to add duplicate topic \'${subscription.topic}\'', ServiceError.DuplicateTopic);
    }
    _projectManager.currentProject!.topicSubscriptions.add(subscription);
    _projectManager.currentProject!.topicColors[subscription.topic] = subscription.color;
    _addRecentTopic(subscription.topic);

    if (_mqttAdapter.isConnected() && !paused) {
      _subscribeToTopic(subscription.topic, subscription.qos);
    }

    topicSubscriptionsChangedEvent.broadcast();
  }

  void removeTopicSubscription(String topic) {
    assert(_projectManager.isProjectOpen);
    if (_mqttAdapter.isConnected()) {
      _unSubscribeFromTopic(topic);
    }

    _projectManager.currentProject!.topicSubscriptions.removeWhere((x) => x.topic == topic);
    topicSubscriptionsChangedEvent.broadcast();
  }

  void _addRecentTopic(String topic) {
    assert(_projectManager.isProjectOpen);

    if (!_projectManager.currentProject!.recentTopics.contains(topic)) {
      _projectManager.currentProject!.recentTopics.insert(0, topic);
    }

    if (_projectManager.currentProject!.recentTopics.length > 20) {
      _projectManager.currentProject!.recentTopics.removeLast();
    }
  }

  void tooglePauseTopicSubscription(String topic) {
    assert(_projectManager.isProjectOpen);
    var sub = _projectManager.currentProject!.topicSubscriptions.singleWhere((x) => x.topic == topic);
    sub.paused = !sub.paused;
    if (sub.paused) {
      _unSubscribeFromTopic(topic);
    } else if (!paused) {
      _subscribeToTopic(topic, sub.qos);
    }

    topicSubscriptionsChangedEvent.broadcast();
  }

  void pauseAllTopics() {
    paused = true;
    for (var sub in _projectManager.currentProject!.topicSubscriptions) {
      _unSubscribeFromTopic(sub.topic);
    }

    topicSubscriptionsChangedEvent.broadcast();
  }

  void playAllTopics() {
    paused = false;
    for (var sub in _projectManager.currentProject!.topicSubscriptions) {
      if (!sub.paused) {
        _subscribeToTopic(sub.topic, sub.qos);
      }
    }

    topicSubscriptionsChangedEvent.broadcast();
  }

  void _messageReceived(ReceivedMqttMessage msg) {
    assert(_projectManager.isProjectOpen);

    messageBuffer.storeMessage(msg);
    messageReceivedEvent.broadcast(msg);

    var sub = TopicSubscription.getTopicSubscriptionMatch(msg.topicName, _projectManager.currentProject!.topicSubscriptions);
    if (sub != null) {
      _projectManager.currentProject!.topicColors[msg.topicName] = sub.color;
    } else {
      _projectManager.currentProject!.topicColors[msg.topicName] = TopicColor(Colors.black);
    }
  }

  TopicColor getTopicColor(String topicName) {
    assert(_projectManager.isProjectOpen);

    return _projectManager.currentProject!.topicColors[topicName]!;
  }

  void _onMqttConntected() {
    // subscribe to all topics
    if (_projectManager.currentProject != null) {
      for (var sub in _projectManager.currentProject!.topicSubscriptions) {
        if (!sub.paused) {
          _subscribeToTopic(sub.topic, sub.qos);
        }
      }
    }
  }

  void _subscribeToTopic(String topic, MqttQos qos) {
    if (_mqttAdapter.isConnected()) {
      _mqttAdapter.subscribeToTopic(topic, qos);
    }
  }

  void _unSubscribeFromTopic(String topic) {
    if (_mqttAdapter.isConnected()) {
      _mqttAdapter.unSubscribeFromTopic(topic);
    }
  }

  void publishTopic(String topic, dynamic payload, MqttPayloadType payloadType, bool retain, [MqttQos qos = MqttQos.atLeastOnce]) {
    if (_mqttAdapter.isConnected()) {
      _mqttAdapter.publish(topic, payload, payloadType, retain, qos);
    }
    _addRecentTopic(topic);
  }
}
