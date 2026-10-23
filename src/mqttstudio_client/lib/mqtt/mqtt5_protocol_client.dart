import 'dart:io';
import 'dart:typed_data';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'mqttserver.dart' if (dart.library.html) 'mqttbrowser.dart' as mqttsetup;
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

class Mqtt5ProtocolClient extends MqttProtocolClient {
  // mqtt5_client returns this when a message has no expiry interval, see _readProperties
  static const int _noMessageExpiryInterval = 65535;

  MqttClient _client = mqttsetup.setup('', '');
  BrokerInfo? _brokerInfo;
  String? _lastDisconnectReason;

  @override
  MqttProtocolVersion get protocolVersion => MqttProtocolVersion.v5;

  @override
  BrokerInfo? get brokerInfo => _brokerInfo;

  @override
  String? get lastDisconnectReason => _lastDisconnectReason;

  @override
  Future connect(MqttSettings mqttSettings) async {
    _brokerInfo = null;
    _lastDisconnectReason = null;
    _client = mqttsetup.setup(MqttProtocolClient.serverAddressOf(mqttSettings), mqttSettings.clientId);

    _client.port = mqttSettings.port;
    _client.onConnected = _onConnected;
    _client.onDisconnected = _onDisconnected;
    _client.onSubscribed = _onSubscribed;
    _client.onSubscribeFail = _onSubscribeFail;
    _client.onUnsubscribed = _onUnsubscribed;
    _client.connectionMessage = _buildConnectMessage(mqttSettings);
    _client.keepAlivePeriod = MqttProtocolClient.keepAlivePeriod;
    _client.logging(on: true);
    _client.websocketProtocols = ['mqtt'];

    // setup for server client only
    mqttsetup.setupSecure(_client, MqttProtocolClient.useSecureSocket(mqttSettings));
    mqttsetup.setupUserWebSockets(_client, mqttSettings.useWebSockets);

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

    // a broker that refuses the connection answers with a reason code instead of closing the socket
    if (!isConnected()) {
      var reason = _connectRefusedReason() ?? 'Connection refused';
      print('MQTT: error connecting [$reason]');
      _client.disconnect();
      throw new SrxServiceException(reason, ServiceError.MqttCannotConnect);
    }

    _client.updates.listen(_onDataReceived);
  }

  @override
  void disconnect() {
    _client.disconnect();
  }

  @override
  bool isConnected() {
    return _client.connectionStatus?.state == MqttConnectionState.connected;
  }

  @override
  void subscribe(TopicSubscription subscription) {
    var option = MqttSubscriptionOption()
      ..maximumQos = subscription.qos
      // No Local on a shared subscription is a protocol error, the broker would close the connection
      ..noLocal = subscription.noLocal && !subscription.topic.startsWith(TopicSubscription.sharePrefix)
      ..retainAsPublished = subscription.retainAsPublished
      ..retainHandling = MqttRetainHandling.values[subscription.retainHandling.index];
    _client.subscribeWithSubscription(MqttSubscription(MqttSubscriptionTopic(subscription.topic), option));
  }

  @override
  void unsubscribe(String topic) {
    _client.unsubscribeStringTopic(topic);
  }

  @override
  void publish(String topic, Uint8Buffer payload, MqttQos qos, bool retain, MqttMessageProperties? properties) {
    if (properties == null || properties.isEmpty) {
      _client.publishMessage(topic, qos, payload, retain: retain);
      return;
    }

    var message = MqttPublishMessage().toTopic(topic).withQos(qos).publishData(payload);
    message.setRetain(state: retain);
    if (properties.contentType != null && properties.contentType!.isNotEmpty) {
      message.withContentType(properties.contentType!);
    }
    if (properties.responseTopic != null && properties.responseTopic!.isNotEmpty) {
      message.withResponseTopic(properties.responseTopic!);
    }
    if (properties.correlationData != null && properties.correlationData!.isNotEmpty) {
      message.withResponseCorrelationdata(Uint8Buffer()..addAll(properties.correlationData!));
    }
    if (properties.messageExpiryInterval != null) {
      message.withMessageExpiryInterval(properties.messageExpiryInterval!);
    }
    if (properties.payloadFormatUtf8) {
      message.withPayloadFormatIndicator(true);
    }
    if (properties.userProperties.isNotEmpty) {
      message.withUserProperties(properties.userProperties
          .map((entry) => MqttUserProperty()
            ..pairName = entry.key
            ..pairValue = entry.value)
          .toList());
    }
    _client.publishUserMessage(message);
  }

  MqttConnectMessage _buildConnectMessage(MqttSettings mqttSettings) {
    var message = MqttConnectMessage().withClientIdentifier(mqttSettings.clientId).withRequestProblemInformation(true);
    // clean start is off by default. startSession() is not used because it turns an interval of 0 into
    // "never expires".
    if (mqttSettings.cleanStart) {
      message.startClean();
    }
    if (mqttSettings.sessionExpiryInterval > 0) {
      message.withSessionExpiryInterval(mqttSettings.sessionExpiryInterval);
    }
    return message;
  }

  String? _connectRefusedReason() {
    var status = _client.connectionStatus;
    var code = status?.reasonCode;
    if (code == null || code == MqttConnectReasonCode.notSet || code == MqttConnectReasonCode.success) {
      return null;
    }
    return describeReasonCode(MqttConnectReasonCodeSupport.mqttConnectReasonCode.asString(code),
        value: MqttConnectReasonCodeSupport.mqttConnectReasonCode.asInt(code), reasonString: status?.reasonString);
  }

  void _onConnected() {
    // the CONNACK is stored before this callback is called, so the broker info is ready for the connected event
    var ack = _client.connectionStatus!.connectAckMessage;
    var header = ack.variableHeader!;
    _brokerInfo = BrokerInfo(MqttProtocolVersion.v5,
        reasonCode: header.reasonCode == null
            ? null
            : describeReasonCode(MqttConnectReasonCodeSupport.mqttConnectReasonCode.asString(header.reasonCode),
                value: MqttConnectReasonCodeSupport.mqttConnectReasonCode.asInt(header.reasonCode)),
        reasonString: header.reasonString,
        sessionPresent: header.sessionPresent,
        sessionExpiryInterval: header.sessionExpiryInterval,
        assignedClientIdentifier: header.assignedClientIdentifier,
        maximumQos: header.maximumQos,
        // mqtt5_client reports false when the broker leaves the property out, which in MQTT 5 means retain is
        // supported. As the two cases cannot be told apart the value is not shown.
        retainAvailable: null,
        maximumPacketSize: header.maximumPacketSize,
        receiveMaximum: header.receiveMaximum,
        topicAliasMaximum: header.topicAliasMaximum,
        serverKeepAlive: header.serverKeepAlive,
        wildcardSubscriptionsAvailable: header.wildcardSubscriptionsAvailable,
        subscriptionIdentifiersAvailable: header.subscriptionIdentifiersAvailable,
        sharedSubscriptionsAvailable: header.sharedSubscriptionAvailable,
        responseInformation: header.responseInformation,
        serverReference: header.serverReference,
        userProperties: _toEntries(header.userProperty ?? []));
    onConnected?.call();
  }

  void _onDisconnected() {
    _brokerInfo = null;
    _lastDisconnectReason = null;
    var status = _client.connectionStatus;
    if (status != null && status.disconnectionOrigin == MqttDisconnectionOrigin.brokerSolicited) {
      var disconnectMessage = status.disconnectMessage;
      var code = disconnectMessage.reasonCode;
      _lastDisconnectReason = code == null
          ? disconnectMessage.reasonString
          : describeReasonCode(MqttDisconnectReasonCodeSupport.mqttDisconnectReasonCode.asString(code),
              value: MqttDisconnectReasonCodeSupport.mqttDisconnectReasonCode.asInt(code),
              reasonString: disconnectMessage.reasonString);
    }
    onDisconnected?.call();
  }

  void _onDataReceived(List<MqttReceivedMessage<MqttMessage>> messages) {
    var received = <ReceivedMqttMessage>[];
    for (var msg in messages) {
      var rawMsg = msg.payload as MqttPublishMessage;
      var payload = rawMsg.payload.message ?? Uint8Buffer(0);
      var header = rawMsg.variableHeader!;
      received.add(ReceivedMqttMessage.received(
          header.messageIdentifier, header.topicName, payload, rawMsg.header!.qos, rawMsg.header?.retain ?? false,
          properties: _readProperties(header)));
    }
    onMessagesReceived?.call(received);
  }

  // mqtt5_client does not tell whether a property was sent and returns defaults instead: empty strings and an expiry
  // interval of 65535 seconds. These are treated as not sent.
  MqttMessageProperties _readProperties(MqttPublishVariableHeader header) {
    var expiry = header.messageExpiryInterval;
    var correlationData = header.correlationData;
    return MqttMessageProperties(
        contentType: _nullIfEmpty(header.contentType),
        responseTopic: _nullIfEmpty(header.responseTopic),
        correlationData:
            correlationData == null || correlationData.isEmpty ? null : Uint8List.fromList(correlationData),
        messageExpiryInterval: expiry == null || expiry == _noMessageExpiryInterval ? null : expiry,
        payloadFormatUtf8: header.payloadFormatIndicator,
        userProperties: _toEntries(header.userProperty),
        subscriptionIdentifiers: header.subscriptionIdentifier.whereType<int>().toList());
  }

  void _onSubscribed(MqttSubscription subscription) {
    if (subscription.topic.rawTopic != null) {
      onSubscribed?.call(subscription.topic.rawTopic!);
    }
  }

  void _onSubscribeFail(MqttSubscription subscription) {
    var code = subscription.reasonCode;
    var reason = code == null
        ? null
        : describeReasonCode(MqttSubscribeReasonCodeSupport.mqttSubscribeReasonCode.asString(code),
            value: MqttSubscribeReasonCodeSupport.mqttSubscribeReasonCode.asInt(code));
    onSubscribeFailed?.call(subscription.topic.rawTopic ?? '', reason);
  }

  void _onUnsubscribed(MqttSubscription? subscription) {
    if (subscription != null && subscription.topic.rawTopic != null) {
      onUnsubscribed?.call(subscription.topic.rawTopic!);
    }
  }

  static String? _nullIfEmpty(String? value) => value == null || value.isEmpty ? null : value;

  static List<MqttUserPropertyEntry> _toEntries(List<MqttUserProperty> properties) =>
      properties.map((property) => MqttUserPropertyEntry(property.pairName ?? '', property.pairValue ?? '')).toList();
}
