import 'package:mqtt_client/mqtt_client.dart';

// A single connect attempt, see Mqtt5ConnectAttempt
mixin Mqtt3ConnectAttempt on MqttClient {
  @override
  Future<MqttClientConnectionStatus?> connect([String? username, String? password]) async {
    var connecting = super.connect(username, password);
    var handler = connectionHandler;
    try {
      return await connecting;
    } on Exception {
      // disconnect() leaves the socket of a failed attempt open, a late CONNACK would still start a session
      try {
        handler?.stopListening();
      } on Error {
        // the attempt failed before the socket existed
      }
      rethrow;
    }
  }
}
