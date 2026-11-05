import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/mqtt/mqtt3_connect_attempt.dart';
import 'package:mqttstudio/mqtt/mqtt_protocol_client.dart';
import 'package:mqttstudio/mqtt/tls_context.dart';

MqttClient setup(String serverAddress, String uniqueID) {
  return _MqttServerClient(serverAddress, uniqueID);
}

void setupUserWebSockets(MqttClient client, bool useWebSockets) {
  (client as MqttServerClient).useWebSocket = useWebSockets;
}

void setupSecure(MqttClient client, bool secure, MqttSettings mqttSettings) {
  var serverClient = client as MqttServerClient;
  serverClient.secure = secure;
  if (secure) {
    serverClient.securityContext = TlsContext.of(mqttSettings) ?? SecurityContext.defaultContext;
  }
}

class _MqttServerClient extends MqttServerClient with Mqtt3ConnectAttempt {
  _MqttServerClient(super.server, super.clientIdentifier) : super(maxConnectionAttempts: MqttProtocolClient.maxConnectionAttempts);
}
