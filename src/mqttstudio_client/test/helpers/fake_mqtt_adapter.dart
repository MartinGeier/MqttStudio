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

class PublishedMessage {
  final String topic;
  final dynamic payload;
  final MqttPayloadType payloadType;
  final bool retain;
  final MqttQos qos;
  final MqttMessageProperties? properties;

  PublishedMessage(this.topic, this.payload, this.payloadType, this.retain, this.qos, this.properties);
}

// Replaces the connection to a broker. Records all calls so tests can check what would have been sent.
class FakeMqttAdapter implements MqttAdapter {
  bool connected = false;
  MqttSettings? connectedWith;
  // the last will of the last connect
  MqttWill? will;
  int disconnectCount = 0;
  final List<String> subscribed = [];
  final List<TopicSubscription> subscriptions = [];
  final List<String> unsubscribed = [];
  final List<PublishedMessage> published = [];

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
  MqttProtocolVersion get protocolVersion => connectedWith?.protocolVersion ?? MqttProtocolVersion.v5;

  @override
  Future connect(MqttSettings mqttSettings, {MqttWill? will}) async {
    connected = true;
    connectedWith = mqttSettings;
    this.will = will;
    brokerInfo = BrokerInfo(mqttSettings.protocolVersion);
    onConnectedEvent.broadcast();
  }

  @override
  void disconnect() {
    disconnectCount++;
    if (connected) {
      connected = false;
      brokerInfo = null;
      onDisconnectedEvent.broadcast();
    }
  }

  @override
  bool isConnected() => connected;

  @override
  void subscribeToTopic(TopicSubscription subscription) {
    subscribed.add(subscription.topic);
    subscriptions.add(subscription);
  }

  @override
  void unSubscribeFromTopic(String topic) => unsubscribed.add(topic);

  @override
  void publish(String topic, dynamic payload, MqttPayloadType payloadType, bool retain,
      [MqttQos qos = MqttQos.atMostOnce, MqttMessageProperties? properties]) {
    published.add(PublishedMessage(topic, payload, payloadType, retain, qos, properties));
  }

  // simulates a message arriving from the broker
  void receive(ReceivedMqttMessage message) => messageReceivedEvent.broadcast(message);

  // simulates the broker rejecting a subscription
  void failSubscription(String topic, String? reason) =>
      subscribeFailedEvent.broadcast(SubscribeFailedEventArgs(topic, reason));

  // simulates the broker closing the connection
  void dropConnection({String? reason}) {
    lastDisconnectReason = reason;
    connected = false;
    brokerInfo = null;
    onDisconnectedEvent.broadcast();
  }
}
