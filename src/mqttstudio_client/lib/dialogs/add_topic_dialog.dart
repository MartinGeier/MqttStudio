import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:mqttstudio/viewmodel/add_topic_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

class AddTopicDialog extends StatelessWidget {
  const AddTopicDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AddTopicViewmodel>(
      create: (_) => AddTopicViewmodel(),
      builder: (context, child) {
        return SimpleDialog(title: Text('addtopicdialog.title'.tr()), contentPadding: EdgeInsets.all(16), children: [
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: 480, maxWidth: 480),
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
                      ElevatedButton(onPressed: () => _onOkPressed(context), child: Text('addtopicdialog.subscribe.button'.tr())),
                      SrxFormFieldSpacer(),
                      ElevatedButton(onPressed: () => _onOkPressed(context, true), child: Text('addtopicdialog.subscribenew.button'.tr()))
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

  _onOkPressed(BuildContext context, [bool subscribeAndNew = false]) async {
    try {
      var vm = context.read<AddTopicViewmodel>();
      if (vm.addTopic()) {
        if (!subscribeAndNew) {
          GetIt.I.get<SrxNavigationService>().pop();
        } else {
          vm.form.control(AddTopicViewmodel.topicNameField).reset();
        }
      }
    } on SrxServiceException catch (exc) {
      if (exc.serviceError == ServiceError.DuplicateTopic) {
        await showDialog(
            builder: (context) => SrxDialogs.srxErrorDialog('addtopicdialog.duplicatetopic.error'.tr(), context), context: context);
      } else {
        throw exc;
      }
    }
  }

  _buildForm(BuildContext context) {
    return ReactiveForm(
      formGroup: context.read<AddTopicViewmodel>().form,
      child: Column(
        children: [
          SrxFormRow(children: [Expanded(child: _buildTopicNameField(context))]),
          SrxFormRow(children: [Expanded(child: _buildQosField(context))]),
        ],
      ),
    );
  }

  _buildTopicNameField(BuildContext context) {
    return ReactiveTextField(
      autofocus: true,
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'addtopicdialog.topicname.label'.tr(), isDense: true),
      formControlName: AddTopicViewmodel.topicNameField,
      validationMessages: (control) => {'maxLength': 'fieldcontenttolong.error'.tr(), 'required': 'srx.common.fieldrequired'.tr()},
    );
  }

  _buildQosField(BuildContext context) {
    var items = List<DropdownMenuItem>.generate(
        3, (index) => DropdownMenuItem(value: MqttQos.values[index], child: Text(MqttQos.values[index].toString().tr())));
    return ReactiveDropdownField(
      items: items,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'addtopicdialog.qos.label'.tr(), isDense: true),
      formControlName: AddTopicViewmodel.qosField,
      validationMessages: (control) => {'required': 'srx.common.fieldrequired'.tr()},
    );
  }
}
