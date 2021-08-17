import 'package:mqtt5_client/mqtt5_client.dart';

class ReceivedMqttMessage {
  String topicName;
  String payload;
  MqttQos qos;
  late DateTime receivedOn;

  ReceivedMqttMessage(this.topicName, this.payload, this.qos, this.receivedOn);

  ReceivedMqttMessage.received(this.topicName, this.payload, this.qos) {
    receivedOn = DateTime.now();
  }
}
