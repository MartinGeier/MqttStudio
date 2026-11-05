import 'dart:io';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqtt5_client/mqtt5_server_client.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/mqtt/mqtt5_connect_attempt.dart';
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

class _MqttServerClient extends MqttServerClient with Mqtt5ConnectAttempt {
  _MqttServerClient(super.server, super.clientIdentifier) : super(maxConnectionAttempts: MqttProtocolClient.maxConnectionAttempts);
}
