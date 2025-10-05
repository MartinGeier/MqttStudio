import 'package:mqtt5_client/mqtt5_browser_client.dart';
import 'package:mqtt5_client/mqtt5_client.dart';

MqttClient setup(String serverAddress, String uniqueID) {
  return MqttBrowserClient(serverAddress, uniqueID);
}

void setupUserWebSockets(MqttClient client, bool useWebSockets) {
  // nothing to do
}

void setupSecure(MqttClient client, bool secure) {
// nothing to do
}
