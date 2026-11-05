import 'package:mqtt5_client/mqtt5_browser_client.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/mqtt/mqtt5_connect_attempt.dart';
import 'package:mqttstudio/mqtt/mqtt_protocol_client.dart';

MqttClient setup(String serverAddress, String uniqueID) {
  return _MqttBrowserClient(serverAddress, uniqueID);
}

void setupUserWebSockets(MqttClient client, bool useWebSockets) {
  // nothing to do
}

void setupSecure(MqttClient client, bool secure, MqttSettings mqttSettings) {
  // the browser makes the TLS connection
}

class _MqttBrowserClient extends MqttBrowserClient with Mqtt5ConnectAttempt {
  _MqttBrowserClient(super.server, super.clientIdentifier) : super(maxConnectionAttempts: MqttProtocolClient.maxConnectionAttempts);
}
