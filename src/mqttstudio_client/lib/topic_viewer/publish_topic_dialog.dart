import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'publish_topic_viewmodel.dart';

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
    if (vm.publishTopic()) {
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
    return ReactiveTextField(
      autofocus: true,
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'publishtopicdialog.topicname.label'.tr(), isDense: true),
      formControlName: PublishTopicViewmodel.topicNameField,
      validationMessages: (control) => {'maxLength': 'fieldcontenttolong.error'.tr(), 'required': 'srx.common.fieldrequired'.tr()},
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
      maxLength: 2000,
      maxLines: 10,
    );
  }
}
