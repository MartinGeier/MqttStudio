import 'package:json_annotation/json_annotation.dart';

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

  MqttSettings(this.hostname, this.clientId, this.port, {this.username, this.password, this.useSsl = false});

  bool connectionSettingsChanged(MqttSettings otherProject) {
    return this.hostname != otherProject.hostname ||
        this.clientId != otherProject.clientId ||
        this.username != otherProject.username ||
        this.password != otherProject.password ||
        this.useSsl != otherProject.useSsl ||
        this.useWebSockets != otherProject.useWebSockets;
  }

  factory MqttSettings.fromJson(Map<String, dynamic> json) => _$MqttSettingsFromJson(json);
  Map<String, dynamic> toJson() => _$MqttSettingsToJson(this);
}
