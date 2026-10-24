import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:typed_data/typed_buffers.dart';

// Where the simulator sends its messages. Tests replace it with a fake that records them.
abstract class SimulatorPublisher {
  bool get isConnected;

  // MQTT 5 properties are only sent when the connection supports them
  bool get supportsProperties;

  void publish(String topic, Uint8Buffer payload, MqttQos qos, bool retain, MqttMessageProperties? properties);
}

class MqttAdapterPublisher implements SimulatorPublisher {
  final MqttAdapter adapter;

  MqttAdapterPublisher(this.adapter);

  @override
  bool get isConnected => adapter.isConnected();

  @override
  bool get supportsProperties => adapter.protocolVersion == MqttProtocolVersion.v5;

  @override
  void publish(String topic, Uint8Buffer payload, MqttQos qos, bool retain, MqttMessageProperties? properties) {
    adapter.publish(topic, payload, MqttPayloadType.binary, retain, qos, supportsProperties ? properties : null);
  }
}
