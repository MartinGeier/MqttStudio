import 'dart:convert';
import 'dart:typed_data';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_message_properties.dart';

// A message as it is stored in a recording
class RecordedMessage {
  // time since the start of the recording
  final int offsetMicros;
  final String topic;
  // the stored bytes, cut to the max payload size when truncated
  final Uint8List payload;
  // the size as published
  final int payloadLength;
  final MqttQos qos;
  final bool retain;
  // a retained message the broker sent because of the new subscription: the state at recording start
  final bool snapshot;
  final bool truncated;
  final MqttMessageProperties? properties;

  RecordedMessage({
    required this.offsetMicros,
    required this.topic,
    required this.payload,
    int? payloadLength,
    this.qos = MqttQos.atMostOnce,
    this.retain = false,
    this.snapshot = false,
    this.truncated = false,
    this.properties,
  }) : payloadLength = payloadLength ?? payload.length;

  Duration get offset => Duration(microseconds: offsetMicros);

  // the same message at another offset, e.g. counted from a start trigger
  RecordedMessage at(int newOffsetMicros) => RecordedMessage(
        offsetMicros: newOffsetMicros,
        topic: topic,
        payload: payload,
        payloadLength: payloadLength,
        qos: qos,
        retain: retain,
        snapshot: snapshot,
        truncated: truncated,
        properties: properties,
      );
}

// A marker in the recording, e.g. where the connection was lost
class RecordingMarker {
  static const String connectionLost = 'connectionLost';
  static const String reconnected = 'reconnected';
  static const String recovered = 'recovered';
  static const String triggerFired = 'triggerFired';

  final int offsetMicros;
  final String kind;

  RecordingMarker(this.offsetMicros, this.kind);

  Duration get offset => Duration(microseconds: offsetMicros);
}

// The MQTT 5 properties of a recorded message as JSON. Subscription identifiers are left out, they belong to the
// recorder's own subscription.
class RecordedProperties {
  static Map<String, dynamic> toJson(MqttMessageProperties properties) => {
        if (properties.contentType != null) 'contentType': properties.contentType,
        if (properties.responseTopic != null) 'responseTopic': properties.responseTopic,
        if (properties.correlationData != null) 'correlationData': base64Encode(properties.correlationData!),
        if (properties.messageExpiryInterval != null) 'messageExpiryInterval': properties.messageExpiryInterval,
        if (properties.payloadFormatUtf8) 'payloadFormatUtf8': true,
        if (properties.userProperties.isNotEmpty)
          'userProperties': [for (var entry in properties.userProperties) [entry.key, entry.value]],
      };

  static MqttMessageProperties fromJson(Map<String, dynamic> json) => MqttMessageProperties(
        contentType: json['contentType'] as String?,
        responseTopic: json['responseTopic'] as String?,
        correlationData: json['correlationData'] == null ? null : base64Decode(json['correlationData'] as String),
        messageExpiryInterval: json['messageExpiryInterval'] as int?,
        payloadFormatUtf8: json['payloadFormatUtf8'] as bool? ?? false,
        userProperties: [
          for (var entry in (json['userProperties'] as List<dynamic>? ?? []))
            MqttUserPropertyEntry((entry as List<dynamic>)[0] as String, entry[1] as String)
        ],
      );

  // true when there is something to store
  static bool hasContent(MqttMessageProperties? properties) {
    if (properties == null) {
      return false;
    }
    return properties.contentType != null ||
        properties.responseTopic != null ||
        properties.correlationData != null ||
        properties.messageExpiryInterval != null ||
        properties.payloadFormatUtf8 ||
        properties.userProperties.isNotEmpty;
  }
}
