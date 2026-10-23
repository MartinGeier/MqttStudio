import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';

// What the broker reported when the connection was accepted. For MQTT 3.1.1 only the protocol and the return code are
// known, all other values are only sent by MQTT 5 brokers in the CONNACK packet.
class BrokerInfo {
  final MqttProtocolVersion protocolVersion;
  final String? reasonCode;
  final String? reasonString;
  final bool? sessionPresent;
  final int? sessionExpiryInterval;
  final String? assignedClientIdentifier;
  final int? maximumQos;
  final bool? retainAvailable;
  final int? maximumPacketSize;
  final int? receiveMaximum;
  final int? topicAliasMaximum;
  final int? serverKeepAlive;
  final bool? wildcardSubscriptionsAvailable;
  final bool? subscriptionIdentifiersAvailable;
  final bool? sharedSubscriptionsAvailable;
  final String? responseInformation;
  final String? serverReference;
  final List<MqttUserPropertyEntry> userProperties;

  BrokerInfo(this.protocolVersion,
      {this.reasonCode,
      this.reasonString,
      this.sessionPresent,
      this.sessionExpiryInterval,
      this.assignedClientIdentifier,
      this.maximumQos,
      this.retainAvailable,
      this.maximumPacketSize,
      this.receiveMaximum,
      this.topicAliasMaximum,
      this.serverKeepAlive,
      this.wildcardSubscriptionsAvailable,
      this.subscriptionIdentifiersAvailable,
      this.sharedSubscriptionsAvailable,
      this.responseInformation,
      this.serverReference,
      this.userProperties = const []});
}
