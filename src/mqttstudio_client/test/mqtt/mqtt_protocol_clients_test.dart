import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqtt_client/mqtt_client.dart' as v3;
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/mqtt/mqtt_protocol_client.dart';
import 'package:mqttstudio/mqtt/mqtt_reason_codes.dart';

void main() {
  group('describeReasonCode', () {
    test('turns the enum name into a sentence with the hex value', () {
      expect(describeReasonCode('badUserNameOrPassword', value: 0x86), 'Bad user name or password (0x86)');
      expect(describeReasonCode('success', value: 0), 'Success (0x00)');
    });

    test('adds the reason string of the broker', () {
      expect(describeReasonCode('notAuthorized', value: 0x87, reasonString: 'ACL denied'),
          'Not authorized (0x87): ACL denied');
    });

    test('works without a value', () {
      expect(describeReasonCode('topicFilterInvalid'), 'Topic filter invalid');
    });
  });

  group('MqttQos of both client packages', () {
    test('have the same values in the same order', () {
      // Mqtt311ProtocolClient maps between the two by index
      expect(v3.MqttQos.values.map((qos) => qos.name), MqttQos.values.map((qos) => qos.name));
    });
  });

  group('MqttProtocolClient.serverAddressOf', () {
    test('uses the hostname for TCP connections', () {
      expect(MqttProtocolClient.serverAddressOf(MqttSettings('broker.local', 'c', 1883)), 'broker.local');
    });

    test('adds ws:// or wss:// for websockets', () {
      var ws = MqttSettings('broker.local/mqtt', 'c', 8080)..useWebSockets = true;
      var wss = MqttSettings('broker.local/mqtt', 'c', 8081, useSsl: true)..useWebSockets = true;

      expect(MqttProtocolClient.serverAddressOf(ws), 'ws://broker.local/mqtt');
      expect(MqttProtocolClient.serverAddressOf(wss), 'wss://broker.local/mqtt');
    });

    test('uses a secure socket only for TLS over TCP', () {
      expect(MqttProtocolClient.useSecureSocket(MqttSettings('b', 'c', 8883, useSsl: true)), isTrue);
      expect(
          MqttProtocolClient.useSecureSocket(MqttSettings('b', 'c', 8081, useSsl: true)..useWebSockets = true), isFalse);
      expect(MqttProtocolClient.useSecureSocket(MqttSettings('b', 'c', 1883)), isFalse);
    });
  });
}
