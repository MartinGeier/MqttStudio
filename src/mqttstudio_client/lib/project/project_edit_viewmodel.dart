import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

class ProjectEditViewmodel extends SrxChangeNotifier {
  static String projectNameField = 'projectName';
  static String mqttHostnameField = 'mqttHostname';
  static String clientIdField = 'clientId';
  static String portField = 'port';
  static String usernameField = 'username';
  static String passwordField = 'password';
  static String useSslField = 'useSsl';
  static String useWebSocketField = 'useWebSocket';
  static String protocolVersionField = 'protocolVersion';
  static String cleanStartField = 'cleanStart';
  static String sessionExpiryIntervalField = 'sessionExpiryInterval';

  // largest session expiry interval MQTT 5 allows, it means the session never expires
  static const int maxSessionExpiryInterval = 4294967295;

  bool _isPasswordObscureText = true;
  Project? project;
  late FormGroup form;
  StreamSubscription? _protocolVersionSubscription;

  bool get isPasswordObscureText => _isPasswordObscureText;

  set isPasswordObscureText(bool isPasswordObscureText) {
    _isPasswordObscureText = isPasswordObscureText;
    notifyListeners();
  }

  bool get isMqtt5 => form.control(protocolVersionField).value == MqttProtocolVersion.v5;

  ProjectEditViewmodel(this.project) {
    form = buildFormGroup();
    fromProject();
    _updateMqtt5Controls();
    _protocolVersionSubscription = form.control(protocolVersionField).valueChanges.listen((_) {
      _updateMqtt5Controls();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _protocolVersionSubscription?.cancel();
    super.dispose();
  }

  FormGroup buildFormGroup() {
    return FormGroup({
      projectNameField:
          FormControl<String>(validators: [Validators.required, Validators.maxLength(30), Validators.minLength(3)]),
      mqttHostnameField:
          FormControl<String>(validators: [Validators.required, Validators.maxLength(100), Validators.minLength(5)]),
      clientIdField: FormControl<String>(
          validators: [Validators.required, Validators.maxLength(100), Validators.minLength(3)],
          value: project == null ? Random().nextInt(999999).toString() : null),
      portField: FormControl<int>(validators: [Validators.min(1), Validators.max(65535)], value: 1883),
      usernameField: FormControl<String>(validators: [Validators.maxLength(100)]),
      passwordField: FormControl<String>(validators: [Validators.maxLength(100)]),
      useSslField: FormControl<bool>(value: kIsWeb, disabled: kIsWeb),
      useWebSocketField: FormControl<bool>(value: kIsWeb, disabled: kIsWeb),
      // new projects use MQTT 5, existing ones keep the version they were saved with
      protocolVersionField:
          FormControl<MqttProtocolVersion>(validators: [Validators.required], value: MqttProtocolVersion.v5),
      cleanStartField: FormControl<bool>(value: true),
      sessionExpiryIntervalField: FormControl<int>(
          validators: [Validators.required, Validators.min(0), Validators.max(maxSessionExpiryInterval)], value: 0),
    });
  }

  void fromProject() {
    if (project != null) {
      form.control(projectNameField).value = project!.name;
      form.control(mqttHostnameField).value = project!.mqttSettings.hostname;
      form.control(clientIdField).value = project!.mqttSettings.clientId;
      form.control(portField).value = project!.mqttSettings.port;
      form.control(usernameField).value = project!.mqttSettings.username;
      form.control(passwordField).value = project!.mqttSettings.password;
      form.control(useSslField).value = project!.mqttSettings.useSsl;
      form.control(useWebSocketField).value = project!.mqttSettings.useWebSockets;
      form.control(protocolVersionField).value = project!.mqttSettings.protocolVersion;
      form.control(cleanStartField).value = project!.mqttSettings.cleanStart;
      form.control(sessionExpiryIntervalField).value = project!.mqttSettings.sessionExpiryInterval;
    }
  }

  void toProject() {
    if (project == null) {
      project = Project(
        MqttSettings(
            form.control(mqttHostnameField).value, form.control(clientIdField).value, form.control(portField).value,
            username: form.control(usernameField).value, password: form.control(passwordField).value),
        name: form.control(projectNameField).value,
      );
      project!.mqttSettings.useSsl = form.control(useSslField).value ?? false;
      project!.mqttSettings.useWebSockets = form.control(useWebSocketField).value ?? false;
    } else {
      project!.name = form.control(projectNameField).value;
      project!.mqttSettings.hostname = form.control(mqttHostnameField).value;
      project!.mqttSettings.clientId = form.control(clientIdField).value;
      project!.mqttSettings.port = form.control(portField).value;
      project!.mqttSettings.username = form.control(usernameField).value;
      project!.mqttSettings.password = form.control(passwordField).value;
      project!.mqttSettings.useSsl = form.control(useSslField).value;
      project!.mqttSettings.useWebSockets = form.control(useWebSocketField).value;
    }
    project!.mqttSettings.protocolVersion = form.control(protocolVersionField).value;
    project!.mqttSettings.cleanStart = form.control(cleanStartField).value ?? true;
    project!.mqttSettings.sessionExpiryInterval = form.control(sessionExpiryIntervalField).value ?? 0;
  }

  bool saveModel({bool validateForm = true}) {
    if (validateForm) {
      form.markAllAsTouched();
      if (!form.valid) {
        return false;
      }
    }

    toProject();
    return true;
  }

  // the session settings only exist in MQTT 5, they are kept but not editable for MQTT 3.1.1
  void _updateMqtt5Controls() {
    for (var name in [cleanStartField, sessionExpiryIntervalField]) {
      var control = form.control(name);
      if (isMqtt5) {
        control.markAsEnabled(emitEvent: false);
      } else {
        control.markAsDisabled(emitEvent: false);
      }
    }
  }
}
