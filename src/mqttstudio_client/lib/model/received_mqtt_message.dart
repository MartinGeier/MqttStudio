import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:typed_data/typed_buffers.dart';

class ReceivedMqttMessage {
  int? id;
  String topicName;
  Uint8Buffer payload;
  MqttQos qos;
  late DateTime receivedOn;
  bool retain;

  ReceivedMqttMessage(this.id, this.topicName, this.payload, this.qos, this.receivedOn, this.retain);

  ReceivedMqttMessage.received(this.id, this.topicName, this.payload, this.qos, this.retain) {
    receivedOn = DateTime.now();
  }
}
