import 'package:mqtt_client/mqtt_client.dart';

class ReceivedMqttMessage {
  int? id;
  String topicName;
  String payload;
  MqttQos qos;
  late DateTime receivedOn;
  bool retain;

  ReceivedMqttMessage(this.id, this.topicName, this.payload, this.qos, this.receivedOn, this.retain);

  ReceivedMqttMessage.received(this.id, this.topicName, this.payload, this.qos, this.retain) {
    receivedOn = DateTime.now();
  }
}
