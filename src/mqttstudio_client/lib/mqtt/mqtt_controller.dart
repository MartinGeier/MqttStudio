import 'dart:io';
import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'mqttserver.dart' if (dart.library.html) 'mqttbrowser.dart' as mqttsetup;
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart' as lock;

// Keeps the connection to the MQTT broker and offers basic operations such as publishing a topic and subscribing to a topic.
// Publishes the onMessageReceived event for further processing of incoming messages.
class MqttController {
  static const String WebSocketPrefix = "ws://";
  static const String SecureWebSocketPrefix = "wss://";

  MqttClient _client = mqttsetup.setup('', '');
  List<String> _activeSubscriptions = List.empty(growable: true);
  Function? onConnected;
  Function? onDisconnected;
  Function(ReceivedMqttMessage msg)? onMessageReceived;
  var _lock = new lock.Lock();

  MqttController() {
    if (!kIsWeb) {
      rootBundle
          .load('assets/cert/mosquitto.org.crt')
          .then((value) => SecurityContext.defaultContext.setTrustedCertificatesBytes(value.buffer.asUint8List()));
    }
  }

  Future connect(MqttSettings mqttSettings) async {
    var hostname = mqttSettings.hostname;
    if (mqttSettings.useWebSockets) {
      hostname = (mqttSettings.useSsl ? SecureWebSocketPrefix : WebSocketPrefix) + hostname + "/mqtt";
    }

    _client = mqttsetup.setup(hostname, mqttSettings.clientId);

    _client.port = mqttSettings.port;
    _client.onConnected = _onConnected;
    _client.onDisconnected = _onDisconnected;
    _client.onSubscribed = _onSubscribed;
    _client.onUnsubscribed = _onUnsubscribed;
    _client.connectionMessage = MqttConnectMessage().startClean().withClientIdentifier(mqttSettings.clientId);
    _client.keepAlivePeriod = 20;
    _client.logging(on: true);
    _client.setProtocolV311();
    _client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;

    // setup for server client only
    mqttsetup.setupSecure(
        _client,
        mqttSettings.useSsl
            ? mqttSettings.useWebSockets
                ? false
                : true
            : false);
    mqttsetup.setupUserWebSockets(_client, mqttSettings.useWebSockets);

    try {
      await _client.connect(mqttSettings.username, mqttSettings.password);
      _client.updates!.listen((event) => _onDataReceived(event));
    } on SocketException catch (exc) {
      print('MQTT: error connecting [${exc.message}, ${exc.osError?.message}]');
      _client.disconnect();
      throw new SrxServiceException('${exc.message}, ${exc.osError}', ServiceError.MqttCannotConnect);
    } on NoConnectionException catch (exc) {
      print('MQTT: error connecting [$exc]');
      _client.disconnect();
      throw new SrxServiceException(exc.toString(), ServiceError.MqttCannotConnect);
    } on Exception catch (exc) {
      print('MQTT: error connecting [$exc]');
      _client.disconnect();
      throw new SrxServiceException(exc.toString(), ServiceError.MqttCannotConnect);
    }
  }

  void disconnect() {
    _client.disconnect();
  }

  bool isConnected() {
    return _client.connectionStatus!.state == MqttConnectionState.connected;
  }

  void subscribeToTopic(String topic, MqttQos qos) {
    if (!isConnected()) {
      throw new SrxServiceException('Not connected to MQTT broker', ServiceError.MqttNotConnected);
    }
    _client.subscribe(topic, qos);
  }

  void unSubscribeFromTopic(String topic) {
    if (!isConnected()) {
      throw new SrxServiceException('Not connected to MQTT broker', ServiceError.MqttNotConnected);
    }
    _client.unsubscribe(topic, expectAcknowledge: true);
  }

  void publish(String topic, dynamic payload, MqttPayloadType payloadType, bool retain, [MqttQos qos = MqttQos.atMostOnce]) {
    var payloadBuilder = MqttClientPayloadBuilder();
    switch (payloadType) {
      case MqttPayloadType.string:
        payloadBuilder.addString(payload);
        break;

      case MqttPayloadType.bool:
        payloadBuilder.addBool(val: payload);
        break;

      case MqttPayloadType.binary:
        payloadBuilder.addBuffer(payload);
        break;
    }

    _client.publishMessage(topic, qos, payloadBuilder.payload!, retain: retain);
  }

  void _onConnected() {
    if (onConnected != null) {
      print('MQTT: connected');
      onConnected!();
    }
  }

  void _onDisconnected() {
    if (onDisconnected != null) {
      print('MQTT: disconnected');
      onDisconnected!();
    }
  }

  void _onDataReceived(List<MqttReceivedMessage<MqttMessage>> messages) async {
    await _lock.synchronized(() async {
      if (onMessageReceived != null) {
        for (var msg in messages) {
          var rawMsg = msg.payload as MqttPublishMessage;
          var payload = rawMsg.payload.message;
          ReceivedMqttMessage receivedMsg = ReceivedMqttMessage.received(rawMsg.variableHeader!.messageIdentifier,
              rawMsg.variableHeader!.topicName, payload, rawMsg.header!.qos, rawMsg.header?.retain ?? false);
          onMessageReceived!(receivedMsg);
        }
      }
    });
  }

  void _onSubscribed(String topic) {
    _activeSubscriptions.add(topic);
  }

  void _onUnsubscribed(String? topic) {
    _activeSubscriptions.remove(topic);
  }
}
