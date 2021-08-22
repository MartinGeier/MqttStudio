import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/viewmodel/project_global_viewmodel.dart';
import 'package:mqttstudio/viewmodel/project_edit_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

class ProjectEditDialog extends StatelessWidget {
  const ProjectEditDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var currentProject = context.read<ProjectGlobalViewmodel>().currentProject;

    return ChangeNotifierProvider<ProjectEditViewmodel>(
        create: (_) => ProjectEditViewmodel(currentProject),
        builder: (context, child) {
          return _buildBody(context);
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
          style: Theme.of(context).textTheme.subtitle2, //!.apply(fontWeightDelta: 1),
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
    ]);
  }

  ReactiveTextField<String> _buildProjectNameField(ProjectEditViewmodel viewmodel) {
    return ReactiveTextField(
      autofocus: true,
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'projectedit.projectname.label'.tr(), isDense: true),
      formControlName: ProjectEditViewmodel.projectNameField,
      validationMessages: (control) => {
        'minLength': 'common.fieldcontenttoshort.error'.tr(),
        'maxLength': 'common.fieldcontenttolong.error'.tr(),
        'required': 'srx.common.fieldrequired'.tr()
      },
    );
  }

  ReactiveTextField<String> _buildMqttHostnameField(ProjectEditViewmodel viewmodel, BuildContext context) {
    return ReactiveTextField(
      textInputAction: TextInputAction.next,
      maxLines: 1,
      enableInteractiveSelection: true,
      enableSuggestions: true,
      decoration: InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'projectedit.mqqthostname.label'.tr(),
          isDense: true,
          suffixIcon: PopupMenuButton(
            onSelected: (broker) => viewmodel.form.control(ProjectEditViewmodel.mqttHostnameField).value = broker,
            icon: Icon(Icons.arrow_drop_down),
            itemBuilder: (context) {
              return [
                PopupMenuItem(
                  child: Text('test.mosquitto.org'),
                  value: 'test.mosquitto.org',
                ),
                PopupMenuItem(
                  child: Text('broker.hivemq.com'),
                  value: 'broker.hivemq.com',
                ),
                PopupMenuItem(
                  child: Text('broker.emqx.io'),
                  value: 'broker.emqx.io',
                ),
              ];
            },
          )),
      formControlName: ProjectEditViewmodel.mqttHostnameField,
      validationMessages: (control) => {
        'minLength': 'common.fieldcontenttoshort.error'.tr(),
        'maxLength': 'common.fieldcontenttolong.error'.tr(),
        'required': 'srx.common.fieldrequired'.tr()
      },
    );
  }

  ReactiveTextField<String> _buildClientIdField(ProjectEditViewmodel viewmodel) {
    return ReactiveTextField(
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'projectedit.clientid.label'.tr(), isDense: true),
      formControlName: ProjectEditViewmodel.clientIdField,
      validationMessages: (control) => {
        'minLength': 'fieldcontenttoshort.error'.tr(),
        'maxLength': 'fieldcontenttolong.error'.tr(),
        'required': 'srx.common.fieldrequired'.tr()
      },
    );
  }

  ReactiveTextField<int> _buildPortField(ProjectEditViewmodel viewmodel) {
    return ReactiveTextField(
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'projectedit.port.label'.tr(), isDense: true),
      formControlName: ProjectEditViewmodel.portField,
      validationMessages: (control) => {
        'min': 'projectedit.port.error'.tr(),
        'max': 'projectedit.port.error'.tr(),
      },
    );
  }

  ReactiveTextField<String?> _buildUsernameField(ProjectEditViewmodel viewmodel) {
    return ReactiveTextField(
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'projectedit.username.label'.tr(), isDense: true),
      formControlName: ProjectEditViewmodel.usernameField,
      validationMessages: (control) => {
        'maxLength': 'common.fieldcontenttolong.error'.tr(),
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
      validationMessages: (control) => {
        'maxLength': 'common.fieldcontenttolong.error'.tr(),
      },
    );
  }

  _onOkPressed(ProjectEditViewmodel viewmodel) async {
    if (viewmodel.saveModel(validateForm: true)) {
      GetIt.I.get<SrxNavigationService>().pop(viewmodel.project);
    }
  }
}
