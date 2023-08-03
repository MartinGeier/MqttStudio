import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

MqttClient setup(String serverAddress, String uniqueID) {
  return MqttBrowserClient(serverAddress, uniqueID);
}

void setupUserWebSockets(MqttClient client, bool useWebSockets) {
  // nothing to do
}

void setupSecure(MqttClient client, bool secure) {
// nothing to do
}
