import 'dart:io';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqtt5_client/mqtt5_server_client.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:srx_flutter/srx_flutter.dart';

class MqttController {
  MqttClient _client = MqttServerClient('', '');
  Map<String, MqttSubscription> _activeSubscriptions = Map();
  Function? onConnected;
  Function? onDisconnected;
  Function(ReceivedMqttMessage msg)? onMessageReceived;

  Future connect(MqttSettings mqttSettings) async {
    _client = MqttServerClient(mqttSettings.hostname, mqttSettings.clientId);
    _client.port = mqttSettings.port;
    _client.onConnected = _onConnected;
    _client.onDisconnected = _onDisconnected;
    _client.onSubscribed = _onSubscribed;
    _client.onUnsubscribed = _onUnsubscribed;
    _client.connectionMessage = MqttConnectMessage().startClean();
    _client.logging(on: true);
    try {
      await _client.connect(mqttSettings.username, mqttSettings.password);
      _client.updates.listen((event) => _onDataReceived(event));
    } on SocketException catch (exc) {
      print('MQTT: error connecting [${exc.message}, ${exc.osError?.message}]');
      _client.disconnect();
      throw new SrxServiceException('${exc.message}, ${exc.osError}', ServiceError.MqttCannotConnect);
    } on MqttNoConnectionException catch (exc) {
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
    _client.unsubscribeStringTopic(topic);
  }

  void publish(String topic, dynamic payload, MqttPayloadType payloadType, bool retain) {
    var payloadBuilder = MqttPayloadBuilder();
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

    _client.publishMessage(topic, MqttQos.atLeastOnce, payloadBuilder.payload!, retain: retain);
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

  void _onDataReceived(List<MqttReceivedMessage<MqttMessage>> event) {
    if (onMessageReceived != null) {
      var rawMsg = event.first.payload as MqttPublishMessage;
      var payload = MqttUtilities.bytesToStringAsString(rawMsg.payload.message!);
      ReceivedMqttMessage msg = ReceivedMqttMessage.received(rawMsg.variableHeader!.topicName, payload, rawMsg.header!.qos);
      onMessageReceived!(msg);
    }
  }

  void _onSubscribed(MqttSubscription subscription) {
    _activeSubscriptions[subscription.topic.rawTopic!] = subscription;
  }

  void _onUnsubscribed(MqttSubscription subscription) {
    _activeSubscriptions.remove(subscription.topic.rawTopic!);
  }
}
