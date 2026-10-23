enum MqttProtocolVersion {
  v311,
  v5,
}

extension MqttProtocolVersionEx on MqttProtocolVersion {
  String get displayName {
    switch (this) {
      case MqttProtocolVersion.v311:
        return 'MQTT 3.1.1';
      case MqttProtocolVersion.v5:
        return 'MQTT 5';
    }
  }
}
