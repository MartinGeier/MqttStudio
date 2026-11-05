import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/mqtt/mqtt_protocol_client.dart';

// A single connect attempt (MqttProtocolClient.maxConnectionAttempts) with the app's CONNACK wait
mixin Mqtt5ConnectAttempt on MqttClient {
  @override
  Future<MqttConnectionStatus?> connect([String? username, String? password]) async {
    var connecting = super.connect(username, password);
    // mqtt5_client has no setting for the CONNACK wait (fixed 5 s). connect() creates the connection handler before
    // its first await and only sleeps on the timer after the socket is open, so it can be replaced here.
    var handler = connectionHandler;
    handler.connectTimer = MqttCancellableAsyncSleep(MqttProtocolClient.connectTimeoutPeriod);
    try {
      return await connecting;
    } on Exception {
      // disconnect() leaves the socket of a failed attempt open, a late CONNACK would still start a session
      try {
        handler.connection.disconnect(auto: true);
      } on Error {
        // the attempt failed before the socket existed
      }
      rethrow;
    }
  }
}
