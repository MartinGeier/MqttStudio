import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqtt5_client/mqtt5_server_client.dart';
import 'package:mqttstudio_client/service/service_error.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

class MqttController {
  MqttClient _client = MqttServerClient('', '');
  Map<String, MqttSubscription> _activeSubscriptions = Map();
  Function? onConnected;
  Function? onDisconnected;

  Future connect(String hostname, String clientId) async {
    _client = MqttServerClient(hostname, clientId);
    _client.onConnected = _onConnected;
    _client.onDisconnected = _onDisconnected;
    _client.onSubscribed = _onSubscribed;
    _client.onUnsubscribed = _onUnsubscribed;
    try {
      await _client.connect();
      _client.updates.listen((event) => _onDataReceived(event));
      print('MQTT: connected');
    } on Exception catch (exc) {
      print('MQTT: error connecting [$exc]');
      _client.disconnect();
      throw new SrxServiceException('mqtt.cannotconnect.error'.tr(), ServiceError.MqttCannotConnect);
    }
  }

  void disconnect() {
    _client.disconnect();
  }

  bool isConnected() {
    return _client.connectionStatus!.state == MqttConnectionState.connected;
  }

  void subscribeToTopic(
    String topic,
  ) {
    _client.subscribe(topic, MqttQos.exactlyOnce);
  }

  void publish(String topic, String payload, bool retain) {
    var payloadBuilder = MqttPayloadBuilder();
    payloadBuilder.addString(payload);
    _client.publishMessage(topic, MqttQos.exactlyOnce, payloadBuilder.payload!, retain: retain);
  }

  void _onConnected() {
    if (onConnected != null) {
      onConnected!();
    }
  }

  void _onDisconnected() {
    if (onDisconnected != null) {
      onDisconnected!();
    }
  }

  String _onDataReceived(List<MqttReceivedMessage<MqttMessage>> event) {
    var msg = event.first.payload as MqttPublishMessage;
    return MqttUtilities.bytesToStringAsString(msg.payload.message!);
  }

  void _onSubscribed(MqttSubscription subscription) {
    _activeSubscriptions[subscription.topic.rawTopic!] = subscription;
  }

  void _onUnsubscribed(MqttSubscription subscription) {
    _activeSubscriptions.remove(subscription.topic.rawTopic!);
  }
}
