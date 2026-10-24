import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/mqtt/tls_context.dart';

MqttClient setup(String serverAddress, String uniqueID) {
  return MqttServerClient(serverAddress, uniqueID);
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
