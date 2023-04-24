import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:mqttstudio/topic_viewer/add_topic_viewmodel.dart';
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
          SrxFormRow(children: [
            Flexible(flex: 3, child: _buildQosField(context)),
            SrxFormFieldSpacer(),
            Flexible(flex: 1, child: _buildColorField(context))
          ]),
        ],
      ),
    );
  }

  Widget _buildTopicNameField(BuildContext context) {
    var vm = context.read<AddTopicViewmodel>();
    var recentTopics = context.read<ProjectGlobalViewmodel>().currentProject?.recentTopics;
    return ReactiveTextField(
      autofocus: true,
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(
        border: OutlineInputBorder(),
        labelText: 'addtopicdialog.topicname.label'.tr(),
        isDense: true,
        suffixIcon: PopupMenuButton(
          onSelected: (topic) => vm.form.control(AddTopicViewmodel.topicNameField).value = topic,
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
      formControlName: AddTopicViewmodel.topicNameField,
      validationMessages: {'maxLength': (error) => 'fieldcontenttolong.error'.tr(), 'required': (error) => 'srx.common.fieldrequired'.tr()},
      onSubmitted: (_) => _onOkPressed(context),
    );
  }

  Widget _buildQosField(BuildContext context) {
    var items = List<DropdownMenuItem>.generate(
        3, (index) => DropdownMenuItem(value: MqttQos.values[index], child: Text(MqttQos.values[index].toString().tr())));
    return ReactiveDropdownField(
      items: items,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'addtopicdialog.qos.label'.tr(), isDense: true),
      formControlName: AddTopicViewmodel.qosField,
      validationMessages: {'required': (error) => 'srx.common.fieldrequired'.tr()},
    );
  }

  Widget _buildColorField(BuildContext context) {
    var items = List<DropdownMenuItem>.generate(
        TopicColor.defaultColors.length,
        (index) => DropdownMenuItem(
            value: TopicColor.defaultColors[index],
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SizedBox(height: 24, width: 80, child: Container(color: TopicColor.defaultColors[index])),
            )));
    return ReactiveDropdownField(
      items: items,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'addtopicdialog.color.label'.tr(), isDense: true),
      formControlName: AddTopicViewmodel.colorField,
      validationMessages: {'required': (error) => 'srx.common.fieldrequired'.tr()},
    );
  }
}
