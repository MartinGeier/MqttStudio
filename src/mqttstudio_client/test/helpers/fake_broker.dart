import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:clock/clock.dart';
import 'package:event/event.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/broker_info.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/mqtt/mqtt_will.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:typed_data/typed_buffers.dart';

// a message as the broker routed it
class BrokerMessage {
  final String topic;
  final Uint8List payload;
  final MqttQos qos;
  final bool retain;
  // the client id of the connection that published it, null for a will the broker sent
  final String? from;
  final bool isWill;

  BrokerMessage(this.topic, this.payload, this.qos, this.retain, this.from, {this.isWill = false});

  String get text => utf8.decode(payload, allowMalformed: true);
}

// An in-memory MQTT broker for tests with several connections: subscriptions with wildcards, retained messages,
// last wills on a dropped connection and the takeover of a client id. Messages are delivered in a microtask, as
// over a network, so fake time and flushMicrotasks control them.
class FakeBroker {
  final List<FakeBrokerConnection> connections = [];
  final Map<String, BrokerMessage> retained = {};
  // every message the broker routed, wills included, in order
  final List<BrokerMessage> log = [];
  // refuses new connections, e.g. to test reconnecting
  bool refuseConnections = false;

  FakeBrokerConnection newConnection() => FakeBrokerConnection(this);

  List<FakeBrokerConnection> get online => connections.where((connection) => connection.connected).toList();

  FakeBrokerConnection? connectionOf(String clientId) =>
      online.where((connection) => connection.clientId == clientId).firstOrNull;

  List<BrokerMessage> messagesOn(String filter) =>
      log.where((message) => RecorderRules.matches(message.topic, filter)).toList();

  void _connect(FakeBrokerConnection connection) {
    // a second connection with the same client id takes over, the first one is dropped with its will
    connectionOf(connection.clientId!)?.drop();
    connections.add(connection);
  }

  void _publish(BrokerMessage message) {
    log.add(message);
    if (message.retain) {
      if (message.payload.isEmpty) {
        retained.remove(message.topic);
      } else {
        retained[message.topic] = message;
      }
    }
    for (var connection in online) {
      if (connection.subscriptions.any((filter) => RecorderRules.matches(message.topic, filter))) {
        connection._deliver(message, retain: false);
      }
    }
  }

  void _subscribed(FakeBrokerConnection connection, String filter) {
    for (var message in retained.values) {
      if (RecorderRules.matches(message.topic, filter)) {
        connection._deliver(message, retain: true);
      }
    }
  }
}

// one client connection of the fake broker, used where the app creates an MqttAdapter
class FakeBrokerConnection implements MqttAdapter {
  final FakeBroker broker;
  bool connected = false;
  String? clientId;
  MqttSettings? settings;
  MqttWill? will;
  final List<String> subscriptions = [];

  FakeBrokerConnection(this.broker);

  @override
  final onConnectedEvent = Event();
  @override
  final onDisconnectedEvent = Event();
  @override
  final messageReceivedEvent = Event<ReceivedMqttMessage>();
  @override
  final subscribeFailedEvent = Event<SubscribeFailedEventArgs>();

  @override
  BrokerInfo? brokerInfo;
  @override
  String? lastDisconnectReason;

  @override
  MqttProtocolVersion get protocolVersion => settings?.protocolVersion ?? MqttProtocolVersion.v5;

  @override
  Future connect(MqttSettings mqttSettings, {MqttWill? will}) async {
    if (broker.refuseConnections) {
      throw Exception('Connection refused');
    }
    clientId = mqttSettings.clientId;
    settings = mqttSettings;
    this.will = will;
    subscriptions.clear();
    broker._connect(this);
    connected = true;
    brokerInfo = BrokerInfo(mqttSettings.protocolVersion);
    onConnectedEvent.broadcast();
  }

  // a clean DISCONNECT: the broker drops the will
  @override
  void disconnect() {
    if (!connected) {
      return;
    }
    connected = false;
    will = null;
    brokerInfo = null;
    onDisconnectedEvent.broadcast();
  }

  @override
  void dropConnection() => drop();

  // the connection breaks without DISCONNECT: the broker publishes the will
  void drop() {
    if (!connected) {
      return;
    }
    connected = false;
    brokerInfo = null;
    var will = this.will;
    this.will = null;
    if (will != null) {
      broker._publish(BrokerMessage(will.topic, will.payload, will.qos, will.retain, null, isWill: true));
    }
    onDisconnectedEvent.broadcast();
  }

  @override
  bool isConnected() => connected;

  @override
  void subscribeToTopic(TopicSubscription subscription) {
    subscriptions.add(subscription.topic);
    broker._subscribed(this, subscription.topic);
  }

  @override
  void unSubscribeFromTopic(String topic) => subscriptions.remove(topic);

  @override
  void publish(
    String topic,
    dynamic payload,
    MqttPayloadType payloadType,
    bool retain, [
    MqttQos qos = MqttQos.atMostOnce,
    MqttMessageProperties? properties,
  ]) {
    if (!connected) {
      throw StateError('$clientId publishes while not connected');
    }
    var bytes = switch (payloadType) {
      MqttPayloadType.string => Uint8List.fromList(utf8.encode(payload as String)),
      MqttPayloadType.bool => Uint8List.fromList([payload == true ? 1 : 0]),
      MqttPayloadType.binary => Uint8List.fromList((payload as List<int>).toList()),
    };
    broker._publish(BrokerMessage(topic, bytes, qos, retain, clientId));
  }

  void _deliver(BrokerMessage message, {required bool retain}) {
    scheduleMicrotask(() {
      if (!connected) {
        return;
      }
      messageReceivedEvent.broadcast(
        ReceivedMqttMessage(
          0,
          message.topic,
          Uint8Buffer()..addAll(message.payload),
          message.qos,
          clock.now(),
          retain,
        ),
      );
    });
  }
}
