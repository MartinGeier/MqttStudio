import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/common/widgets/mqtt5_section.dart';
import 'package:mqttstudio/project/project_viewmodel.dart';
import 'package:mqttstudio/service/piwik_tracking_service.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'publish_topic_viewmodel.dart';
import 'package:file_picker/file_picker.dart';

class PublishTopicDialog extends StatelessWidget {
  const PublishTopicDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PublishTopicViewmodel>(
      create: (_) => PublishTopicViewmodel(),
      builder: (context, child) {
        return SimpleDialog(title: Text('publishtopicdialog.title'.tr()), contentPadding: EdgeInsets.all(16), children: [
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: 600, maxWidth: 600),
            child: Column(
              children: [
                _buildForm(context),
                SrxFormRow(
                  alignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: OutlinedButton(
                          onPressed: () => _publishFile(context), child: Text('publishtopicdialog.publishfilebutton.label'.tr())),
                    ),
                    Spacer(),
                    Expanded(
                      child: OutlinedButton(
                          onPressed: () {
                            GetIt.I.get<SrxNavigationService>().pop(null);
                          },
                          child: Text('srx.common.cancel'.tr())),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                        child:
                            ElevatedButton(onPressed: () => _onOkPressed(context), child: Text('publishtopicdialog.publish.button'.tr()))),
                  ],
                )
              ],
            ),
          )
        ]);
      },
    );
  }

  _onOkPressed(BuildContext context) async {
    var vm = context.read<PublishTopicViewmodel>();
    PiwikTrackingService().trackAction('Message published');
    if (await vm.publishTopic()) {
      GetIt.I.get<SrxNavigationService>().pop();
    }
  }

  _buildForm(BuildContext context) {
    return ReactiveForm(
      formGroup: context.read<PublishTopicViewmodel>().form,
      child: Column(
        children: [
          SrxFormRow(children: [
            Expanded(flex: 4, child: _buildTopicNameField(context)),
            SizedBox(width: 16),
            Expanded(flex: 1, child: _buildRetainField(context)),
          ]),
          SrxFormRow(multipleLineHeight: 3, children: [Flexible(flex: 1, child: _buildPayloadField(context))]),
          _buildMqtt5Properties(context),
        ],
      ),
    );
  }

  Widget _buildMqtt5Properties(BuildContext context) {
    var vm = context.read<PublishTopicViewmodel>();
    return Mqtt5Section(title: 'publishtopicdialog.mqtt5properties.label'.tr(), enabled: vm.isMqtt5, children: [
      SrxFormRow(children: [
        Expanded(flex: 2, child: _buildTextField(PublishTopicViewmodel.contentTypeField, 'publishtopicdialog.contenttype.label')),
        SizedBox(width: 16),
        Expanded(
            flex: 2,
            child: _buildTextField(PublishTopicViewmodel.messageExpiryIntervalField, 'publishtopicdialog.messageexpiry.label')),
        SizedBox(width: 16),
        Expanded(
            flex: 2,
            child: CheckboxField(
                formControlName: PublishTopicViewmodel.payloadFormatUtf8Field,
                form: vm.form,
                label: 'publishtopicdialog.payloadformatutf8.label'.tr())),
      ]),
      SrxFormRow(children: [
        Expanded(child: _buildTextField(PublishTopicViewmodel.responseTopicField, 'publishtopicdialog.responsetopic.label')),
        SizedBox(width: 16),
        Expanded(
            child: _buildTextField(PublishTopicViewmodel.correlationDataField, 'publishtopicdialog.correlationdata.label')),
      ]),
      _buildUserProperties(context),
    ]);
  }

  Widget _buildUserProperties(BuildContext context) {
    var vm = context.watch<PublishTopicViewmodel>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < vm.userProperties.controls.length; i++)
        _buildUserPropertyRow(context, vm.userProperties.controls[i] as FormGroup, i),
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextButton.icon(
            onPressed: vm.addUserProperty,
            icon: Icon(Icons.playlist_add),
            label: Text('publishtopicdialog.adduserproperty.button'.tr())),
      ),
    ]);
  }

  Widget _buildUserPropertyRow(BuildContext context, FormGroup group, int index) {
    var vm = context.read<PublishTopicViewmodel>();
    return SrxFormRow(children: [
      Expanded(
          flex: 2,
          child: ReactiveTextField<String>(
            formControl: group.control(PublishTopicViewmodel.userPropertyKeyField) as FormControl<String>,
            maxLines: 1,
            decoration: InputDecoration(
                border: OutlineInputBorder(), labelText: 'publishtopicdialog.userpropertykey.label'.tr(), isDense: true),
            validationMessages: {
              'required': (error) => 'srx.common.fieldrequired'.tr(),
              'maxLength': (error) => 'common.fieldcontenttolong.error'.tr(),
            },
          )),
      SizedBox(width: 16),
      Expanded(
          flex: 3,
          child: ReactiveTextField<String>(
            formControl: group.control(PublishTopicViewmodel.userPropertyValueField) as FormControl<String>,
            maxLines: 1,
            decoration: InputDecoration(
                border: OutlineInputBorder(), labelText: 'publishtopicdialog.userpropertyvalue.label'.tr(), isDense: true),
            validationMessages: {'maxLength': (error) => 'common.fieldcontenttolong.error'.tr()},
          )),
      IconButton(
          onPressed: () => vm.removeUserProperty(index),
          tooltip: 'publishtopicdialog.removeuserproperty.tooltip'.tr(),
          icon: Icon(Icons.remove_circle_outline)),
    ]);
  }

  Widget _buildTextField(String formControlName, String labelKey) {
    return ReactiveTextField(
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: labelKey.tr(), isDense: true),
      formControlName: formControlName,
      validationMessages: {
        'maxLength': (error) => 'common.fieldcontenttolong.error'.tr(),
        'min': (error) => 'publishtopicdialog.messageexpiry.error'.tr(),
        'max': (error) => 'publishtopicdialog.messageexpiry.error'.tr(),
        'number': (error) => 'publishtopicdialog.messageexpiry.error'.tr(),
      },
    );
  }

  Widget _buildTopicNameField(BuildContext context) {
    var vm = context.read<PublishTopicViewmodel>();
    var recentTopics = context.read<ProjectViewmodel>().currentProject?.recentTopics;
    return ReactiveTextField(
      autofocus: true,
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(
        border: OutlineInputBorder(),
        labelText: 'publishtopicdialog.topicname.label'.tr(),
        isDense: true,
        suffixIcon: PopupMenuButton(
          onSelected: (topic) => vm.form.control(PublishTopicViewmodel.topicNameField).value = topic,
          icon: Icon(Icons.arrow_drop_down),
          itemBuilder: (context) {
            return List<PopupMenuItem>.generate(
                recentTopics?.length ?? 0,
                (index) => PopupMenuItem(
                      child: Text(recentTopics?[index] ?? ''),
                      value: recentTopics?[index] ?? '',
                    ));
          },
        ),
      ),
      formControlName: PublishTopicViewmodel.topicNameField,
      validationMessages: {'maxLength': (error) => 'fieldcontenttolong.error'.tr(), 'required': (error) => 'srx.common.fieldrequired'.tr()},
      onSubmitted: (_) => _onOkPressed(context),
    );
  }

  Widget _buildRetainField(BuildContext context) {
    return CheckboxField(
        label: 'publishtopicdialog.retain.label'.tr(),
        formControlName: PublishTopicViewmodel.retainField,
        form: context.read<PublishTopicViewmodel>().form);
  }

  Widget _buildPayloadField(BuildContext context) {
    return ReactiveTextField(
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'publishtopicdialog.payload.label'.tr(), isDense: true),
      formControlName: PublishTopicViewmodel.payloadField,
      validationMessages: {'required': (error) => 'srx.common.fieldrequired'.tr()},
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      maxLength: 20000,
      maxLines: 10,
    );
  }

  _publishFile(BuildContext context) async {
    var vm = context.read<PublishTopicViewmodel>();
    vm.form.markAllAsTouched();
    if (!vm.form.valid) {
      return false;
    }

    var filePickerResult = await FilePicker.pickFiles();
    if (filePickerResult == null || filePickerResult.count != 1) {
      return;
    }

    try {
      if (await vm.publishTopicFromFile(filePickerResult.files.first.path!)) {
        GetIt.I.get<SrxNavigationService>().pop();
      }
    } on Exception {
      showDialog(context: context, builder: (_) => SrxDialog.error(bodyText: 'publishtopicdialog.maxfilesize.error'.tr()));
    }
  }
}
