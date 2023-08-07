import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:mqttstudio/project/project_edit_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

class ProjectEditDialog extends StatelessWidget {
  const ProjectEditDialog({Key? key}) : super(key: key);

  static const String MosquittoHostUrl = 'test.mosquitto.org';
  static const String HiveMqHostUrl = 'broker.hivemq.com';
  static const String EmqxHostUrl = 'broker.emqx.io';

  static const int MosquittoPort = 1883;
  static const int MosquittoSslPort = 8883;
  static const int MosquittoWsPort = 8080;
  static const int MosquittoWsSslPort = 8081;

  static const int HiveMqPort = 1883;
  static const int HiveMqSslPort = 8883;
  static const int HiveMqWsPort = 8000;
  static const int HiveMqWsSslPort = 8884;

  static const int EmqxPort = 1883;
  static const int EmqxSslPort = 8883;
  static const int EmqxWsPort = 8083;
  static const int EmqxWsSslPort = 8084;

  @override
  Widget build(BuildContext context) {
    var currentProject = context.read<ProjectGlobalViewmodel>().currentProject;

    return ChangeNotifierProvider<ProjectEditViewmodel>(
        create: (_) => ProjectEditViewmodel(currentProject),
        builder: (context, child) {
          return Consumer<ProjectEditViewmodel>(builder: (context, viewmodel, child) {
            return _buildBody(context);
          });
        });
  }

  Widget _buildBody(BuildContext context) {
    var viewmodel = context.read<ProjectEditViewmodel>();
    return SimpleDialog(title: Text('projectedit.title'.tr()), contentPadding: EdgeInsets.all(16), children: [
      ConstrainedBox(
        constraints: BoxConstraints(minWidth: 400, maxWidth: 400),
        child: Column(
          children: [
            ReactiveForm(formGroup: viewmodel.form, child: _buildForm(viewmodel, context)),
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                      onPressed: () {
                        GetIt.I.get<SrxNavigationService>().pop(null);
                      },
                      child: Text('srx.common.cancel'.tr())),
                  SrxFormFieldSpacer(),
                  ElevatedButton(onPressed: () => _onOkPressed(viewmodel), child: Text('srx.common.ok'.tr()))
                ],
              ),
            )
          ],
        ),
      )
    ]);
  }

  _buildForm(ProjectEditViewmodel viewmodel, BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SrxFormRow(children: [Expanded(child: _buildProjectNameField(viewmodel))]),
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          'projectedit.mqttsetting.label'.tr(),
          style: Theme.of(context).textTheme.titleSmall, //!.apply(fontWeightDelta: 1),
        ),
      ),
      SrxFormRow(
        children: [
          Flexible(flex: 3, child: _buildMqttHostnameField(viewmodel, context)),
          SrxFormFieldSpacer(),
          Flexible(flex: 1, child: _buildPortField(viewmodel)),
        ],
      ),
      SrxFormRow(children: [Expanded(child: _buildClientIdField(viewmodel))]),
      SrxFormRow(
        children: [
          Flexible(flex: 2, child: _buildUsernameField(viewmodel)),
          SrxFormFieldSpacer(),
          Flexible(flex: 2, child: _buildPasswordField(viewmodel)),
        ],
      ),
      SrxFormRow(
        children: [_buildSslCheckbox(viewmodel), SrxFormFieldSpacer(), _buildWebSocketCheckbox(viewmodel)],
      )
    ]);
  }

  Widget _buildSslCheckbox(ProjectEditViewmodel viewmodel) {
    return CheckboxField(
        formControlName: ProjectEditViewmodel.useSslField,
        form: viewmodel.form,
        label: 'projectedit.usessl'.tr(),
        onChanged: () => _setPortNumber(viewmodel));
  }

  _buildWebSocketCheckbox(ProjectEditViewmodel viewmodel) {
    return CheckboxField(
        formControlName: ProjectEditViewmodel.useWebSocketField,
        form: viewmodel.form,
        label: 'projectedit.usewebsockets'.tr(),
        onChanged: () => _setPortNumber(viewmodel));
  }

  ReactiveTextField<String> _buildProjectNameField(ProjectEditViewmodel viewmodel) {
    return ReactiveTextField(
      autofocus: true,
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'projectedit.projectname.label'.tr(), isDense: true),
      formControlName: ProjectEditViewmodel.projectNameField,
      validationMessages: {
        'minLength': (error) => 'common.fieldcontenttoshort.error'.tr(),
        'maxLength': (error) => 'common.fieldcontenttolong.error'.tr(),
        'required': (error) => 'srx.common.fieldrequired'.tr()
      },
    );
  }

  ReactiveTextField<String> _buildMqttHostnameField(ProjectEditViewmodel viewmodel, BuildContext context) {
    return ReactiveTextField(
      textInputAction: TextInputAction.next,
      maxLines: 1,
      enableInteractiveSelection: true,
      enableSuggestions: true,
      onChanged: (control) => _hostnameFieldChanged(viewmodel, control.value ?? ''),
      decoration: InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'projectedit.mqqthostname.label'.tr(),
          isDense: true,
          suffixIcon: PopupMenuButton(
            onSelected: (String host) => _hostnameFieldChanged(viewmodel, host),
            icon: Icon(Icons.arrow_drop_down),
            itemBuilder: (context) {
              return [
                PopupMenuItem(
                  child: Text(MosquittoHostUrl),
                  value: MosquittoHostUrl,
                ),
                PopupMenuItem(
                  child: Text(HiveMqHostUrl),
                  value: HiveMqHostUrl,
                ),
                PopupMenuItem(
                  child: Text(EmqxHostUrl),
                  value: EmqxHostUrl,
                ),
              ];
            },
          )),
      formControlName: ProjectEditViewmodel.mqttHostnameField,
      validationMessages: {
        'minLength': (error) => 'common.fieldcontenttoshort.error'.tr(),
        'maxLength': (error) => 'common.fieldcontenttolong.error'.tr(),
        'required': (error) => 'srx.common.fieldrequired'.tr()
      },
    );
  }

  ReactiveTextField<String> _buildClientIdField(ProjectEditViewmodel viewmodel) {
    return ReactiveTextField(
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'projectedit.clientid.label'.tr(), isDense: true),
      formControlName: ProjectEditViewmodel.clientIdField,
      validationMessages: {
        'minLength': (error) => 'fieldcontenttoshort.error'.tr(),
        'maxLength': (error) => 'fieldcontenttolong.error'.tr(),
        'required': (error) => 'srx.common.fieldrequired'.tr()
      },
    );
  }

  ReactiveTextField<int> _buildPortField(ProjectEditViewmodel viewmodel) {
    return ReactiveTextField(
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'projectedit.port.label'.tr(), isDense: true),
      formControlName: ProjectEditViewmodel.portField,
      validationMessages: {
        'min': (error) => 'projectedit.port.error'.tr(),
        'max': (error) => 'projectedit.port.error'.tr(),
      },
    );
  }

  ReactiveTextField<String?> _buildUsernameField(ProjectEditViewmodel viewmodel) {
    return ReactiveTextField(
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'projectedit.username.label'.tr(), isDense: true),
      formControlName: ProjectEditViewmodel.usernameField,
      validationMessages: {
        'maxLength': (error) => 'common.fieldcontenttolong.error'.tr(),
      },
    );
  }

  ReactiveTextField<String?> _buildPasswordField(ProjectEditViewmodel viewmodel) {
    return ReactiveTextField(
      textInputAction: TextInputAction.next,
      obscureText: viewmodel.isPasswordObscureText,
      maxLines: 1,
      decoration: InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'projectedit.password.label'.tr(),
          isDense: true,
          suffixIcon: IconButton(
              icon: Icon(Icons.visibility_rounded), onPressed: () => viewmodel.isPasswordObscureText = !viewmodel.isPasswordObscureText)),
      formControlName: ProjectEditViewmodel.passwordField,
      validationMessages: {
        'maxLength': (error) => 'common.fieldcontenttolong.error'.tr(),
      },
    );
  }

  _onOkPressed(ProjectEditViewmodel viewmodel) async {
    if (viewmodel.saveModel(validateForm: true)) {
      GetIt.I.get<SrxNavigationService>().pop(viewmodel.project);
    }
  }

  _hostnameFieldChanged(ProjectEditViewmodel viewmodel, String hostname) {
    viewmodel.form.control(ProjectEditViewmodel.mqttHostnameField).value = hostname;
    _setPortNumber(viewmodel);
  }

  void _setPortNumber(ProjectEditViewmodel viewmodel) {
    bool ws = viewmodel.form.control(ProjectEditViewmodel.useWebSocketField).value;
    bool ssl = viewmodel.form.control(ProjectEditViewmodel.useSslField).value;
    int port = 0;
    switch (viewmodel.form.control(ProjectEditViewmodel.mqttHostnameField).value) {
      case MosquittoHostUrl:
        if (ws && ssl) {
          port = MosquittoWsSslPort;
        } else if (ws) {
          port = MosquittoWsPort;
        } else if (ssl) {
          port = MosquittoSslPort;
        } else {
          port = MosquittoPort;
        }
        break;

      case HiveMqHostUrl:
        if (ws && ssl) {
          port = HiveMqWsSslPort;
        } else if (ws) {
          port = HiveMqWsPort;
        } else if (ssl) {
          port = HiveMqSslPort;
        } else {
          port = HiveMqPort;
        }
        break;

      case EmqxHostUrl:
        if (ws && ssl) {
          port = EmqxWsSslPort;
        } else if (ws) {
          port = EmqxWsPort;
        } else if (ssl) {
          port = EmqxSslPort;
        } else {
          port = EmqxPort;
        }
        break;
    }

    if (port > 0) {
      viewmodel.form.control(ProjectEditViewmodel.portField).value = port;
    }
  }
}
