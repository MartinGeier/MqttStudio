import 'dart:math';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

class ProjectEditViewmodel extends SrxChangeNotifier {
  static String projectNameField = 'projectName';
  static String mqttHostnameField = 'mqttHostname';
  static String clientIdField = 'clientId';
  static String portField = 'port';
  static String usernameField = 'username';
  static String passwordField = 'password';

  bool _isPasswordObscureText = true;
  Project? project;
  late FormGroup form;

  bool get isPasswordObscureText => _isPasswordObscureText;

  set isPasswordObscureText(bool isPasswordObscureText) {
    _isPasswordObscureText = isPasswordObscureText;
    notifyListeners();
  }

  ProjectEditViewmodel(this.project) {
    form = buildFormGroup();
    fromProject();
  }

  FormGroup buildFormGroup() {
    return FormGroup({
      projectNameField: FormControl<String>(validators: [Validators.required, Validators.maxLength(30), Validators.minLength(3)]),
      mqttHostnameField: FormControl<String>(validators: [Validators.required, Validators.maxLength(100), Validators.minLength(5)]),
      clientIdField: FormControl<String>(
          validators: [Validators.required, Validators.maxLength(100), Validators.minLength(3)],
          value: project == null ? Random().nextInt(999999).toString() : null),
      portField: FormControl<int>(validators: [Validators.min(1), Validators.max(65535)], value: 1883),
      usernameField: FormControl<String>(validators: [Validators.maxLength(100)]),
      passwordField: FormControl<String>(validators: [Validators.maxLength(100)]),
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
    }
  }

  void toProject() {
    if (project == null) {
      project = Project(
        MqttSettings(form.control(mqttHostnameField).value, form.control(clientIdField).value, form.control(portField).value,
            username: form.control(usernameField).value, password: form.control(passwordField).value),
        name: form.control(projectNameField).value,
      );
    } else {
      project!.name = form.control(projectNameField).value;
      project!.mqttSettings.hostname = form.control(mqttHostnameField).value;
      project!.mqttSettings.clientId = form.control(clientIdField).value;
      project!.mqttSettings.port = form.control(portField).value;
      project!.mqttSettings.username = form.control(usernameField).value;
      project!.mqttSettings.password = form.control(passwordField).value;
    }
  }

  bool saveModel({bool validateForm = true}) {
    if (validateForm) {
      form.markAllAsTouched();
      if (!form.valid) {
        return false;
      }
    }

    toProject();
    GetIt.I.get<ProjectGlobalViewmodel>().openProject(project);
    return true;
  }
}
