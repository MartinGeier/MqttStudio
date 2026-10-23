import 'package:event/event.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:typed_data/typed_buffers.dart';

class ReceivedMqttMessage extends EventArgs {
  int? id;
  String topicName;
  Uint8Buffer payload;
  MqttQos qos;
  late DateTime receivedOn;
  bool retain;
  // MQTT 5 properties, null for MQTT 3.1.1 connections
  MqttMessageProperties? properties;

  ReceivedMqttMessage(this.id, this.topicName, this.payload, this.qos, this.receivedOn, this.retain, {this.properties});

  ReceivedMqttMessage.received(this.id, this.topicName, this.payload, this.qos, this.retain, {this.properties}) {
    receivedOn = DateTime.now();
  }
}
