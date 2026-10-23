import 'dart:typed_data';

class MqttUserPropertyEntry {
  final String key;
  final String value;

  const MqttUserPropertyEntry(this.key, this.value);
}

// MQTT 5 properties of a PUBLISH packet. Independent of the MQTT client package so the rest of the app does not
// depend on it.
class MqttMessageProperties {
  String? contentType;
  String? responseTopic;
  Uint8List? correlationData;
  int? messageExpiryInterval;
  bool payloadFormatUtf8;
  List<MqttUserPropertyEntry> userProperties;
  List<int> subscriptionIdentifiers;

  MqttMessageProperties(
      {this.contentType,
      this.responseTopic,
      this.correlationData,
      this.messageExpiryInterval,
      this.payloadFormatUtf8 = false,
      List<MqttUserPropertyEntry>? userProperties,
      List<int>? subscriptionIdentifiers})
      : userProperties = userProperties ?? [],
        subscriptionIdentifiers = subscriptionIdentifiers ?? [];

  bool get isEmpty =>
      (contentType == null || contentType!.isEmpty) &&
      (responseTopic == null || responseTopic!.isEmpty) &&
      (correlationData == null || correlationData!.isEmpty) &&
      messageExpiryInterval == null &&
      !payloadFormatUtf8 &&
      userProperties.isEmpty &&
      subscriptionIdentifiers.isEmpty;
}
