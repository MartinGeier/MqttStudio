import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/broker_info.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_will.dart';
import 'package:typed_data/typed_buffers.dart';

// Connection to a broker with one MQTT protocol version. MqttAdapter picks the implementation from the project
// settings and hides the differences between the client packages from the rest of the app.
abstract class MqttProtocolClient {
  static const String webSocketPrefix = 'ws://';
  static const String secureWebSocketPrefix = 'wss://';
  static const int keepAlivePeriod = 20;

  void Function()? onConnected;
  void Function()? onDisconnected;
  void Function(List<ReceivedMqttMessage> messages)? onMessagesReceived;
  void Function(String topic)? onSubscribed;
  void Function(String topic)? onUnsubscribed;
  void Function(String topic, String? reason)? onSubscribeFailed;

  MqttProtocolVersion get protocolVersion;

  // what the broker reported when it accepted the connection, null while not connected
  BrokerInfo? get brokerInfo;

  // the reason the broker gave when it closed the connection, MQTT 5 only
  String? get lastDisconnectReason;

  // throws a SrxServiceException if the connection cannot be established; the broker publishes the will when the
  // connection drops without a DISCONNECT
  Future connect(MqttSettings mqttSettings, {MqttWill? will});

  void disconnect();

  // closes the socket without DISCONNECT, as a broken network would, so the broker publishes the will
  void dropConnection();

  bool isConnected();

  void subscribe(TopicSubscription subscription);

  void unsubscribe(String topic);

  // properties are only sent with MQTT 5 and ignored otherwise
  void publish(String topic, Uint8Buffer payload, MqttQos qos, bool retain, MqttMessageProperties? properties);

  static String serverAddressOf(MqttSettings mqttSettings) {
    if (!mqttSettings.useWebSockets) {
      return mqttSettings.hostname;
    }
    return (mqttSettings.useSsl ? secureWebSocketPrefix : webSocketPrefix) + mqttSettings.hostname;
  }

  // TLS over TCP. For websockets the wss:// prefix of the server address enables TLS.
  static bool useSecureSocket(MqttSettings mqttSettings) => mqttSettings.useSsl && !mqttSettings.useWebSockets;
}
