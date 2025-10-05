import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqtt5_client/mqtt5_server_client.dart';

MqttClient setup(String serverAddress, String uniqueID) {
  return MqttServerClient(serverAddress, uniqueID);
}

void setupUserWebSockets(MqttClient client, bool useWebSockets) {
  (client as MqttServerClient).useWebSocket = useWebSockets;
}

void setupSecure(MqttClient client, bool secure) {
  (client as MqttServerClient).secure = secure;
}
