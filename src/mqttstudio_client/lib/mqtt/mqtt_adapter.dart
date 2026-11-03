import 'dart:convert';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/broker_info.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt311_protocol_client.dart';
import 'package:mqttstudio/mqtt/mqtt5_protocol_client.dart';
import 'package:mqttstudio/mqtt/mqtt_protocol_client.dart';
import 'package:mqttstudio/mqtt/tls_context.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart' as lock;
import 'package:event/event.dart';
import 'package:typed_data/typed_buffers.dart';
import 'package:mqttstudio/mqtt/mqtt_will.dart';

class SubscribeFailedEventArgs extends EventArgs {
  final String topic;
  // reason code sent by an MQTT 5 broker, null for MQTT 3.1.1
  final String? reason;

  SubscribeFailedEventArgs(this.topic, this.reason);
}

// Keeps the connection to the MQTT broker and offers basic operations such as publishing a topic and subscribing to a topic.
// Publishes the onMessageReceived event for further processing of incoming messages.
// The protocol version is chosen per project, the protocol specific work is done by a MqttProtocolClient.
class MqttAdapter {
  MqttProtocolClient _client = Mqtt5ProtocolClient();
  List<String> _activeSubscriptions = List.empty(growable: true);
  final onConnectedEvent = Event();
  final onDisconnectedEvent = Event();
  final messageReceivedEvent = Event<ReceivedMqttMessage>();
  final subscribeFailedEvent = Event<SubscribeFailedEventArgs>();
  var _lock = new lock.Lock();
  final MqttProtocolClient Function(MqttProtocolVersion protocolVersion)? _clientFactory;
  _ConnectAttempt? _connecting;

  MqttAdapter({@visibleForTesting MqttProtocolClient Function(MqttProtocolVersion protocolVersion)? clientFactory})
      : _clientFactory = clientFactory;

  MqttProtocolVersion get protocolVersion => _client.protocolVersion;

  // what the broker reported when it accepted the connection, null while not connected
  BrokerInfo? get brokerInfo => _client.brokerInfo;

  // the reason the broker gave for closing the connection, MQTT 5 only
  String? get lastDisconnectReason => _client.lastDisconnectReason;

  // A disconnect or another connect while this one is still running cancels it: the connection it built is closed
  // and it throws a SrxServiceException with ServiceError.MqttConnectCancelled.
  Future connect(MqttSettings mqttSettings, {MqttWill? will}) async {
    _connecting?.cancelled = true;
    var attempt = _connecting = _ConnectAttempt();
    if (!kIsWeb) {
      await TlsContext.loadBundledCa();
    }
    if (attempt.cancelled) {
      throw _cancelledException();
    }

    if (_client.isConnected()) {
      _client.disconnect();
    }
    var client = _createClient(mqttSettings.protocolVersion);
    _client = client;
    // a client that was replaced by a newer connect must not report for the adapter
    client.onConnected = () {
      if (!attempt.cancelled) {
        _onConnected();
      }
    };
    client.onDisconnected = () {
      if (identical(_client, client)) {
        _onDisconnected();
      }
    };
    client.onMessagesReceived = _onDataReceived;
    client.onSubscribed = _onSubscribed;
    client.onUnsubscribed = _onUnsubscribed;
    client.onSubscribeFailed = _onSubscribeFailed;

    try {
      await client.connect(mqttSettings, will: will);
    } catch (_) {
      if (attempt.cancelled) {
        throw _cancelledException();
      }
      _connecting = null;
      rethrow;
    }
    if (attempt.cancelled) {
      client.disconnect();
      throw _cancelledException();
    }
    _connecting = null;
  }

  void disconnect() {
    _connecting?.cancelled = true;
    _connecting = null;
    _client.disconnect();
  }

  // without DISCONNECT, so the broker publishes the will (a simulated Sparkplug edge node's "Drop connection" fault)
  void dropConnection() => _client.dropConnection();

  bool isConnected() {
    return _client.isConnected();
  }

  void subscribeToTopic(TopicSubscription subscription) {
    if (!isConnected()) {
      throw new SrxServiceException('Not connected to MQTT broker', ServiceError.MqttNotConnected);
    }
    _client.subscribe(subscription);
  }

  void unSubscribeFromTopic(String topic) {
    if (!isConnected()) {
      throw new SrxServiceException('Not connected to MQTT broker', ServiceError.MqttNotConnected);
    }
    _client.unsubscribe(topic);
  }

  // properties are only sent over MQTT 5 connections
  void publish(String topic, dynamic payload, MqttPayloadType payloadType, bool retain,
      [MqttQos qos = MqttQos.atMostOnce, MqttMessageProperties? properties]) {
    var payloadBuilder = MqttPayloadBuilder();
    switch (payloadType) {
      case MqttPayloadType.string:
        // Ensure proper UTF-8 encoding for German umlauts and other special characters
        var utf8Bytes = utf8.encode(payload as String);
        var buffer = Uint8Buffer();
        buffer.addAll(utf8Bytes);
        payloadBuilder.addBuffer(buffer);
        break;

      case MqttPayloadType.bool:
        payloadBuilder.addBool(val: payload);
        break;

      case MqttPayloadType.binary:
        payloadBuilder.addBuffer(payload);
        break;
    }

    _client.publish(topic, payloadBuilder.payload!, qos, retain, properties);
  }

  SrxServiceException _cancelledException() =>
      SrxServiceException('Connecting was cancelled', ServiceError.MqttConnectCancelled);

  MqttProtocolClient _createClient(MqttProtocolVersion protocolVersion) {
    if (_clientFactory != null) {
      return _clientFactory(protocolVersion);
    }
    switch (protocolVersion) {
      case MqttProtocolVersion.v311:
        return Mqtt311ProtocolClient();
      case MqttProtocolVersion.v5:
        return Mqtt5ProtocolClient();
    }
  }

  void _onConnected() {
    print('MQTT: connected (${_client.protocolVersion.displayName})');
    onConnectedEvent.broadcast();
  }

  void _onDisconnected() {
    print('MQTT: disconnected');
    onDisconnectedEvent.broadcast();
  }

  void _onDataReceived(List<ReceivedMqttMessage> messages) async {
    print("message received");
    await _lock.synchronized(() async {
      for (var msg in messages) {
        // a failing subscriber must not keep the rest of the batch from the others
        try {
          messageReceivedEvent.broadcast(msg);
        } catch (exc, stack) {
          print('MQTT: handling a message of ${msg.topicName} failed [$exc]\n$stack');
        }
      }
    });
  }

  void _onSubscribed(String topic) {
    _activeSubscriptions.add(topic);
  }

  void _onUnsubscribed(String topic) {
    _activeSubscriptions.remove(topic);
  }

  void _onSubscribeFailed(String topic, String? reason) {
    print('MQTT: subscribing to $topic failed [${reason ?? 'no reason given'}]');
    subscribeFailedEvent.broadcast(SubscribeFailedEventArgs(topic, reason));
  }
}

class _ConnectAttempt {
  bool cancelled = false;
}
