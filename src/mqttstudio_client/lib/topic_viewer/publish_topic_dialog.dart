import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
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
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(onPressed: () => _publishFile(context), child: Text('PUBLISH FILE')),
                      Spacer(),
                      OutlinedButton(
                          onPressed: () {
                            GetIt.I.get<SrxNavigationService>().pop(null);
                          },
                          child: Text('srx.common.cancel'.tr())),
                      SrxFormFieldSpacer(),
                      ElevatedButton(onPressed: () => _onOkPressed(context), child: Text('publishtopicdialog.publish.button'.tr())),
                    ],
                  ),
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
            Flexible(flex: 4, child: _buildTopicNameField(context)),
            SrxFormFieldSpacer(),
            Flexible(flex: 1, child: _buildRetainField(context)),
          ]),
          SrxFormRow(multipleLineHeight: 3, children: [Flexible(flex: 1, child: _buildPayloadField(context))]),
        ],
      ),
    );
  }

  Widget _buildTopicNameField(BuildContext context) {
    var vm = context.read<PublishTopicViewmodel>();
    var recentTopics = context.read<ProjectGlobalViewmodel>().currentProject?.recentTopics;
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
      validationMessages: (control) => {'maxLength': 'fieldcontenttolong.error'.tr(), 'required': 'srx.common.fieldrequired'.tr()},
      onSubmitted: () => _onOkPressed(context),
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
      validationMessages: (control) => {'required': 'srx.common.fieldrequired'.tr()},
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

    var filePickerResult = await FilePicker.platform.pickFiles();
    if (filePickerResult == null || filePickerResult.count != 1) {
      return;
    }

    try {
      if (await vm.publishTopicFromFile(filePickerResult.files.first.path!)) {
        GetIt.I.get<SrxNavigationService>().pop();
      }
    } on Exception {
      showDialog(context: context, builder: (_) => SrxDialogs.srxErrorDialog('Maximum file size is 500k!', context));
    }
  }
}
