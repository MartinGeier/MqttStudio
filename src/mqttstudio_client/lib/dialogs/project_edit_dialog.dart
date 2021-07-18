import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/viewmodel/project_global_viewmodel.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/viewmodel/project_edit_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

class ProjectEditDialog extends StatelessWidget {
  const ProjectEditDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var currentProjectId = context.read<ProjectGlobalViewmodel>().currentProject?.id;

    return ChangeNotifierProvider<ProjectEditViewmodel>(
        create: (_) => ProjectEditViewmodel(currentProjectId),
        builder: (context, child) {
          return _buildBody(context);
        });
  }

  Widget _buildBody(BuildContext context) {
    return SimpleDialog(title: Text('New project'), contentPadding: EdgeInsets.all(16), children: [
      ConstrainedBox(
        constraints: BoxConstraints(minWidth: 400),
        child: Column(
          children: [
            SrxBaseFormWidget<Project, ProjectEditViewmodel>(
              formWidget: (viewmodel) => _buildForm(viewmodel as ProjectEditViewmodel, context),
              loadingView: SrxLoadingIndicatorWidget(),
              errorView: (errorMessage) =>
                  SrxBaseErrorWidget(errorMessage: errorMessage, onRetry: () => context.read<ProjectEditViewmodel>().loadModel()),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('CANCEL')),
                  SizedBox(width: 6),
                  ElevatedButton(onPressed: () => _onOkPressed(context.read<ProjectEditViewmodel>()), child: Text('OK'))
                ],
              ),
            )
          ],
        ),
      )
    ]);
  }

  _buildForm(ProjectEditViewmodel viewmodel, BuildContext context) {
    return ReactiveForm(
        formGroup: viewmodel.form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildProjectNameField(viewmodel),
          SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'MQTT settings',
              style: Theme.of(context).textTheme.subtitle2!.apply(fontWeightDelta: 1),
            ),
          ),
          Row(
            children: [
              Flexible(flex: 3, child: _buildMqttHostnameField(viewmodel)),
              SizedBox(
                width: 12,
              ),
              Flexible(flex: 1, child: _buildPortField(viewmodel)),
            ],
          ),
          SizedBox(height: 16),
          _buildClientIdField(viewmodel),
          SizedBox(height: 16),
          Row(
            children: [
              Flexible(flex: 2, child: _buildUsernameField(viewmodel)),
              SizedBox(
                width: 12,
              ),
              Flexible(flex: 2, child: _buildPasswordField(viewmodel)),
            ],
          ),
        ]));
  }

  ReactiveTextField<String> _buildProjectNameField(ProjectEditViewmodel viewmodel) {
    return ReactiveTextField(
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

  ReactiveTextField<String> _buildMqttHostnameField(ProjectEditViewmodel viewmodel) {
    return ReactiveTextField(
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'projectedit.mqqthostname.label'.tr(), isDense: true),
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
    viewmodel.form.markAllAsTouched();
    if (await viewmodel.saveModel(validateForm: true)) {
      GetIt.I.get<SrxNavigationService>().pop(viewmodel.model);
    }
  }
}
