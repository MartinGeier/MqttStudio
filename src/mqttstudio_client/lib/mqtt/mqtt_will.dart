import 'dart:typed_data';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;

// The last will a connection leaves with the broker: the broker publishes it when the connection drops without a
// DISCONNECT. The payload may be binary, e.g. a Sparkplug NDEATH (doc/sparkplug-design.md §10.2).
class MqttWill {
  final String topic;
  final Uint8List payload;
  final MqttQos qos;
  final bool retain;

  const MqttWill(this.topic, this.payload, {this.qos = MqttQos.atLeastOnce, this.retain = false});
}
