import 'dart:math';

import 'package:mqttstudio/model/project.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

class ProjectEditViewmodel extends SrxBaseFormViewModel<Project> {
  static String projectNameField = 'projectName';
  static String mqttHostnameField = 'mqttHostname';
  static String clientIdField = 'clientId';

  ProjectEditViewmodel(String? projectId) : super(projectId);

  @override
  FormGroup buildFormGroup() {
    return FormGroup({
      projectNameField: FormControl<String>(validators: [Validators.required, Validators.maxLength(30), Validators.minLength(3)]),
      mqttHostnameField: FormControl<String>(validators: [Validators.required, Validators.maxLength(100), Validators.minLength(5)]),
      clientIdField: FormControl<String>(
          validators: [Validators.required, Validators.maxLength(100), Validators.minLength(3)],
          value: model == null ? Random().nextInt(999999).toString() : null),
    });
  }

  @override
  void fromModel() {
    if (model != null) {
      form.control(projectNameField).value = model!.name;
      form.control(mqttHostnameField).value = model!.mqttHostname;
      form.control(clientIdField).value = model!.clientId;
    }
  }

  @override
  void toModel() {
    if (model == null) {
      model = Project(form.control(mqttHostnameField).value, form.control(clientIdField).value, name: form.control(projectNameField).value);
    } else {
      model!.name = form.control(projectNameField).value;
      model!.mqttHostname = form.control(mqttHostnameField).value;
      model!.clientId = form.control(clientIdField).value;
    }
  }
}
