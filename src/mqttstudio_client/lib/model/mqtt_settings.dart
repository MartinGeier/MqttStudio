import 'package:json_annotation/json_annotation.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';

// use 'flutter pub run build_runner build' to run the code generator
part 'mqtt_settings.g.dart';

@JsonSerializable(explicitToJson: true)
class MqttSettings {
  String hostname;
  late String clientId;
  int port;
  String? username;
  String? password;

  @JsonKey(defaultValue: false)
  bool useSsl = false;

  @JsonKey(defaultValue: false)
  bool useWebSockets = false;

  // projects saved before the protocol could be chosen were connected with MQTT 3.1.1
  @JsonKey(defaultValue: MqttProtocolVersion.v311)
  MqttProtocolVersion protocolVersion = MqttProtocolVersion.v311;

  // MQTT 5 only
  @JsonKey(defaultValue: true)
  bool cleanStart = true;

  // MQTT 5 only, in seconds. 0 ends the session when the connection closes.
  @JsonKey(defaultValue: 0)
  int sessionExpiryInterval = 0;

  MqttSettings(this.hostname, this.clientId, this.port, {this.username, this.password, this.useSsl = false});

  bool get isMqtt5 => protocolVersion == MqttProtocolVersion.v5;

  bool connectionSettingsChanged(MqttSettings otherProject) {
    return this.hostname != otherProject.hostname ||
        this.clientId != otherProject.clientId ||
        this.username != otherProject.username ||
        this.password != otherProject.password ||
        this.useSsl != otherProject.useSsl ||
        this.useWebSockets != otherProject.useWebSockets ||
        this.protocolVersion != otherProject.protocolVersion ||
        this.cleanStart != otherProject.cleanStart ||
        this.sessionExpiryInterval != otherProject.sessionExpiryInterval;
  }

  factory MqttSettings.fromJson(Map<String, dynamic> json) => _$MqttSettingsFromJson(json);
  Map<String, dynamic> toJson() => _$MqttSettingsToJson(this);
}
