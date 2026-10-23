import 'package:event/event.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';

class PublishedMessage {
  final String topic;
  final dynamic payload;
  final MqttPayloadType payloadType;
  final bool retain;
  final MqttQos qos;

  PublishedMessage(this.topic, this.payload, this.payloadType, this.retain, this.qos);
}

// Replaces the connection to a broker. Records all calls so tests can check what would have been sent.
class FakeMqttAdapter implements MqttAdapter {
  bool connected = false;
  MqttSettings? connectedWith;
  int disconnectCount = 0;
  final List<String> subscribed = [];
  final List<String> unsubscribed = [];
  final List<PublishedMessage> published = [];

  @override
  final onConnectedEvent = Event();
  @override
  final onDisconnectedEvent = Event();
  @override
  final messageReceivedEvent = Event<ReceivedMqttMessage>();

  @override
  Future connect(MqttSettings mqttSettings) async {
    connected = true;
    connectedWith = mqttSettings;
    onConnectedEvent.broadcast();
  }

  @override
  void disconnect() {
    disconnectCount++;
    if (connected) {
      connected = false;
      onDisconnectedEvent.broadcast();
    }
  }

  @override
  bool isConnected() => connected;

  @override
  void subscribeToTopic(String topic, MqttQos qos) => subscribed.add(topic);

  @override
  void unSubscribeFromTopic(String topic) => unsubscribed.add(topic);

  @override
  void publish(String topic, dynamic payload, MqttPayloadType payloadType, bool retain,
      [MqttQos qos = MqttQos.atMostOnce]) {
    published.add(PublishedMessage(topic, payload, payloadType, retain, qos));
  }

  // simulates a message arriving from the broker
  void receive(ReceivedMqttMessage message) => messageReceivedEvent.broadcast(message);
}
