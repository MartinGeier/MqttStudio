import 'dart:io';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
// mqtt_client and mqtt5_client use the same class names, so the MQTT 3.1.1 package is only used with a prefix
import 'package:mqtt_client/mqtt_client.dart' as v3;
import 'mqtt3server.dart' if (dart.library.html) 'mqtt3browser.dart' as mqtt3setup;
import 'package:mqttstudio/model/broker_info.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_protocol_client.dart';
import 'package:mqttstudio/mqtt/mqtt_reason_codes.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:typed_data/typed_buffers.dart';

class Mqtt311ProtocolClient extends MqttProtocolClient {
  v3.MqttClient _client = mqtt3setup.setup('', '');
  BrokerInfo? _brokerInfo;

  @override
  MqttProtocolVersion get protocolVersion => MqttProtocolVersion.v311;

  @override
  BrokerInfo? get brokerInfo => _brokerInfo;

  @override
  String? get lastDisconnectReason => null;

  @override
  Future connect(MqttSettings mqttSettings) async {
    _brokerInfo = null;
    _client = mqtt3setup.setup(MqttProtocolClient.serverAddressOf(mqttSettings), mqttSettings.clientId);

    _client.port = mqttSettings.port;
    _client.onConnected = _onConnected;
    _client.onDisconnected = _onDisconnected;
    _client.onSubscribed = (topic) => onSubscribed?.call(topic);
    _client.onSubscribeFail = (topic) => onSubscribeFailed?.call(topic, null);
    _client.onUnsubscribed = (topic) {
      if (topic != null) {
        onUnsubscribed?.call(topic);
      }
    };
    _client.connectionMessage = v3.MqttConnectMessage().startClean().withClientIdentifier(mqttSettings.clientId);
    _client.keepAlivePeriod = MqttProtocolClient.keepAlivePeriod;
    _client.logging(on: true);
    _client.setProtocolV311();
    _client.websocketProtocols = v3.MqttClientConstants.protocolsSingleDefault;

    // setup for server client only
    mqtt3setup.setupSecure(_client, MqttProtocolClient.useSecureSocket(mqttSettings), mqttSettings);
    mqtt3setup.setupUserWebSockets(_client, mqttSettings.useWebSockets);

    try {
      await _client.connect(mqttSettings.username, mqttSettings.password);
    } on SocketException catch (exc) {
      print('MQTT: error connecting [${exc.message}, ${exc.osError?.message}]');
      _client.disconnect();
      throw new SrxServiceException('${exc.message}, ${exc.osError}', ServiceError.MqttCannotConnect);
    } on Exception catch (exc) {
      print('MQTT: error connecting [$exc]');
      var reason = _connectRefusedReason();
      _client.disconnect();
      throw new SrxServiceException(reason ?? exc.toString(), ServiceError.MqttCannotConnect);
    }

    if (!isConnected()) {
      var reason = _connectRefusedReason() ?? 'Connection refused';
      print('MQTT: error connecting [$reason]');
      _client.disconnect();
      throw new SrxServiceException(reason, ServiceError.MqttCannotConnect);
    }

    _client.updates!.listen(_onDataReceived);
  }

  @override
  void disconnect() {
    _client.disconnect();
  }

  @override
  bool isConnected() {
    return _client.connectionStatus?.state == v3.MqttConnectionState.connected;
  }

  @override
  void subscribe(TopicSubscription subscription) {
    _client.subscribe(subscription.topic, _toV3Qos(subscription.qos));
  }

  @override
  void unsubscribe(String topic) {
    _client.unsubscribe(topic, expectAcknowledge: true);
  }

  @override
  void publish(String topic, Uint8Buffer payload, MqttQos qos, bool retain, MqttMessageProperties? properties) {
    _client.publishMessage(topic, _toV3Qos(qos), payload, retain: retain);
  }

  String? _connectRefusedReason() {
    var code = _client.connectionStatus?.returnCode;
    if (code == null ||
        code == v3.MqttConnectReturnCode.connectionAccepted ||
        code == v3.MqttConnectReturnCode.noneSpecified) {
      return null;
    }
    // the enum is declared in the order of the protocol values
    return describeReasonCode(code.name, value: code.index);
  }

  void _onConnected() {
    _brokerInfo = BrokerInfo(MqttProtocolVersion.v311,
        reasonCode: describeReasonCode(v3.MqttConnectReturnCode.connectionAccepted.name, value: 0));
    onConnected?.call();
  }

  void _onDisconnected() {
    _brokerInfo = null;
    onDisconnected?.call();
  }

  void _onDataReceived(List<v3.MqttReceivedMessage<v3.MqttMessage>> messages) {
    var received = <ReceivedMqttMessage>[];
    for (var msg in messages) {
      var rawMsg = msg.payload as v3.MqttPublishMessage;
      received.add(ReceivedMqttMessage.received(rawMsg.variableHeader!.messageIdentifier,
          rawMsg.variableHeader!.topicName, rawMsg.payload.message, _fromV3Qos(rawMsg.header!.qos),
          rawMsg.header?.retain ?? false));
    }
    onMessagesReceived?.call(received);
  }

  // both packages declare MqttQos with the same values in the same order
  static v3.MqttQos _toV3Qos(MqttQos qos) => v3.MqttQos.values[qos.index];

  static MqttQos _fromV3Qos(v3.MqttQos qos) => MqttQos.values[qos.index];
}
