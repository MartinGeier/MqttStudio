import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqtt_client/mqtt_client.dart' as v3;
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/mqtt/mqtt311_protocol_client.dart';
import 'package:mqttstudio/mqtt/mqtt5_protocol_client.dart';
import 'package:mqttstudio/mqtt/mqtt_will.dart';
import 'package:typed_data/typed_buffers.dart';

// bytes that are not valid UTF-8, as in a Protobuf payload
final _payload = Uint8List.fromList([0x08, 0xff, 0x00, 0xc3, 0x28, 0x12]);
const _topic = 'spBv1.0/G/NDEATH/E';

// the index of needle in haystack, -1 when it is missing
int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var found = true;
    for (var j = 0; j < needle.length && found; j++) {
      found = haystack[i + j] == needle[j];
    }
    if (found) {
      return i;
    }
  }
  return -1;
}

void main() {
  var settings = MqttSettings('broker', 'edge-1', 1883);

  test('MQTT 3.1.1 writes a binary will unchanged, length-prefixed after the will topic', () {
    var message = Mqtt311ProtocolClient.buildConnectMessage(
      settings,
      MqttWill(_topic, _payload, qos: MqttQos.atLeastOnce),
    );
    var stream = v3.MqttByteBuffer(Uint8Buffer());
    message.writeTo(stream);
    var bytes = stream.buffer!.toList();
    var flags = message.variableHeader!.connectFlags;
    expect(flags.willFlag, isTrue);
    expect(flags.willQos, v3.MqttQos.atLeastOnce);
    expect(flags.willRetain, isFalse);
    var willTopic = _indexOf(bytes, [0, _topic.length, ..._topic.codeUnits]);
    expect(willTopic, greaterThan(0));
    var willMessage = willTopic + 2 + _topic.length;
    expect(bytes.sublist(willMessage, willMessage + 2 + _payload.length), [0, _payload.length, ..._payload]);
    // the remaining length in the fixed header covers the binary will
    expect(bytes.length, message.header!.messageSize + 2);
  });

  test('MQTT 3.1.1 without a will stays as before', () {
    var message = Mqtt311ProtocolClient.buildConnectMessage(settings, null);
    expect(message.variableHeader!.connectFlags.willFlag, isFalse);
    expect(message.payload.runtimeType, v3.MqttConnectPayload);
  });

  test('MQTT 5 takes the will payload as bytes', () {
    var message = Mqtt5ProtocolClient.buildConnectMessage(
      settings,
      MqttWill(_topic, _payload, qos: MqttQos.atLeastOnce, retain: true),
    );
    expect(message.variableHeader!.connectFlags.willFlag, isTrue);
    expect(message.variableHeader!.connectFlags.willRetain, isTrue);
    expect(message.payload.willTopic, _topic);
    expect(message.payload.willPayload.toList(), _payload);
  });
}
