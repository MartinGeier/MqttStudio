import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/topic_edit_viewmodel.dart';
import 'package:mqttstudio/simulator/widgets/generator_editor.dart';
import 'package:mqttstudio/simulator/widgets/simulator_format.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

typedef T = TopicEditViewmodel;

// Adds or edits a simulated topic. The payload settings and the MQTT settings are on two tabs, so the dialog fits
// the window. Returns the SimulatedTopic or null.
class TopicEditDialog extends StatefulWidget {
  final SimulatedDevice device;
  final SimulatedTopic? topic;

  const TopicEditDialog({Key? key, required this.device, this.topic}) : super(key: key);

  @override
  State<TopicEditDialog> createState() => _TopicEditDialogState();
}

class _TopicEditDialogState extends State<TopicEditDialog> with SingleTickerProviderStateMixin {
  late final TopicEditViewmodel _viewmodel;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _viewmodel = TopicEditViewmodel(widget.device, widget.topic);
    _tabController = TabController(length: 2, vsync: this)..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _viewmodel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewmodel,
      child: Consumer<TopicEditViewmodel>(builder: (context, vm, _) {
        var theme = Theme.of(context);
        return SimpleDialog(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((vm.isNew ? 'simulator.topicdialog.add.title' : 'simulator.topicdialog.edit.title').tr()),
            SizedBox(height: 4),
            Text('${widget.device.name} · ${SimulatorFormat.instances(widget.device)} · ${vm.mqttSummary}',
                style: theme.textTheme.bodySmall),
          ]),
          contentPadding: EdgeInsets.all(16),
          // the height changes with the tab and the generator, at the top the tabs stay where they are
          alignment: Alignment.topCenter,
          insetPadding: EdgeInsets.symmetric(horizontal: 40, vertical: 40),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 960, maxWidth: 960),
              child: ReactiveForm(
                formGroup: vm.form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _buildTabs(context),
                  SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(minHeight: 460),
                    child: _tabController.index == 0 ? _buildPayloadTab(context, vm) : _buildMqttTab(context, vm),
                  ),
                  SizedBox(height: 16),
                  _buildActions(context, vm),
                ]),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildTabs(BuildContext context) {
    var theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.hintColor,
        indicatorColor: theme.colorScheme.primary,
        tabs: [Tab(text: 'simulator.topicdialog.payload.tab'.tr()), Tab(text: 'simulator.topicdialog.mqtt.tab'.tr())],
      ),
    );
  }

  Widget _buildPayloadTab(BuildContext context, TopicEditViewmodel vm) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SrxFormRow(children: [
        Expanded(flex: 8, child: _buildTopicField(context, vm)),
        SizedBox(width: 16),
        Expanded(flex: 3, child: _intField(T.intervalField, 'simulator.topicdialog.interval.label')),
        SizedBox(width: 16),
        Expanded(
            flex: 3,
            child: _intField(T.upToField, 'simulator.topicdialog.upto.label',
                hint: 'simulator.topicdialog.upto.hint', helper: 'simulator.topicdialog.upto.helper')),
        SizedBox(width: 16),
        Expanded(flex: 5, child: _buildGeneratorTypeField(vm)),
      ]),
      SizedBox(height: 8),
      GeneratorEditor(
        model: vm.generator,
        previewInstance: widget.device.firstInstance,
        deviceName: widget.device.name,
        previewInterval: vm.previewInterval,
      ),
    ]);
  }

  Widget _buildTopicField(BuildContext context, TopicEditViewmodel vm) {
    return ReactiveTextField<String>(
      formControlName: T.topicField,
      autofocus: true,
      maxLines: 1,
      decoration: InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'simulator.topicdialog.topic.label'.tr(),
          helperText: vm.resolvedRange,
          suffixIcon: Tooltip(
              message: 'simulator.topicdialog.topic.tooltip'.tr(),
              child: Icon(Icons.help_outline, size: 20)),
          suffixIconConstraints: BoxConstraints(minWidth: 40),
          isDense: true),
      validationMessages: {
        ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
        ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr(),
        'wildcards': (_) => 'simulator.issue.topicWildcard'.tr(),
        'needsInstance': (_) => 'simulator.issue.topicNeedsInstance'.tr(),
      },
      onSubmitted: (_) => _onOkPressed(context),
    );
  }

  Widget _buildGeneratorTypeField(TopicEditViewmodel vm) {
    return ReactiveDropdownField(
      formControl: vm.generator.typeControl,
      decoration:
          InputDecoration(border: OutlineInputBorder(), labelText: 'simulator.field.generator.label'.tr(), isDense: true),
      items: [
        for (var type in vm.generator.availableTypes)
          DropdownMenuItem(value: type, child: Text(SimulatorFormat.generatorName(type)))
      ],
    );
  }

  Widget _intField(String name, String labelKey, {String? hint, String? helper}) {
    return ReactiveTextField<int>(
      formControlName: name,
      maxLines: 1,
      decoration: InputDecoration(
          border: OutlineInputBorder(),
          labelText: labelKey.tr(),
          hintText: hint?.tr(),
          helperText: helper?.tr(),
          isDense: true),
      validationMessages: {
        ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
        ValidationMessage.min: (_) => 'simulator.issue.intervalTooShort'.tr(),
        ValidationMessage.number: (_) => 'simulator.value.number.error'.tr(),
        'upTo': (_) => 'simulator.issue.intervalRange'.tr(),
        'expiry': (_) => 'publishtopicdialog.messageexpiry.error'.tr(),
      },
    );
  }

  Widget _buildMqttTab(BuildContext context, TopicEditViewmodel vm) {
    var theme = Theme.of(context);
    var enabled = vm.isMqtt5;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SrxFormRow(children: [
        Expanded(
            flex: 2,
            child: ReactiveDropdownField<MqttQos>(
              formControlName: T.qosField,
              decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'addtopicdialog.qos.label'.tr(), isDense: true),
              items: [
                for (var qos in [MqttQos.atMostOnce, MqttQos.atLeastOnce, MqttQos.exactlyOnce])
                  DropdownMenuItem(value: qos, child: Text(qos.toString().tr())),
              ],
            )),
        SizedBox(width: 16),
        Expanded(
            flex: 1,
            child: CheckboxField(
                formControlName: T.retainField, form: vm.form, label: 'publishtopicdialog.retain.label'.tr())),
        SizedBox(width: 16),
        Expanded(
            flex: 2,
            child: ReactiveTextField<String>(
              formControlName: T.contentTypeField,
              readOnly: !enabled,
              decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'publishtopicdialog.contenttype.label'.tr(),
                  helperText: 'simulator.topicdialog.contenttype.helper'.tr(),
                  enabled: enabled,
                  isDense: true),
            )),
        SizedBox(width: 16),
        Expanded(flex: 2, child: _expiryField(enabled)),
      ]),
      if (!enabled) Text('mqtt5section.disabled.hint'.tr(), style: theme.textTheme.bodySmall),
      SizedBox(height: 8),
      Text('simulator.topicdialog.userproperties.label'.tr(), style: theme.textTheme.titleMedium),
      SizedBox(height: 8),
      if (vm.userProperties.controls.isEmpty)
        Text('simulator.topicdialog.nouserproperties.label'.tr(), style: TextStyle(color: theme.hintColor)),
      for (var i = 0; i < vm.userProperties.controls.length; i++)
        _buildUserPropertyRow(vm, vm.userProperties.controls[i] as FormGroup, i, enabled),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
            onPressed: enabled ? vm.addUserProperty : null,
            icon: Icon(Icons.playlist_add),
            label: Text('publishtopicdialog.adduserproperty.button'.tr())),
      ),
      Text('simulator.topicdialog.userproperties.helper'.tr(), style: theme.textTheme.bodySmall),
    ]);
  }

  Widget _expiryField(bool enabled) {
    return ReactiveTextField<int>(
      formControlName: T.messageExpiryField,
      readOnly: !enabled,
      decoration: InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'publishtopicdialog.messageexpiry.label'.tr(),
          hintText: 'simulator.topicdialog.none.hint'.tr(),
          enabled: enabled,
          isDense: true),
      validationMessages: {
        'expiry': (_) => 'publishtopicdialog.messageexpiry.error'.tr(),
        ValidationMessage.number: (_) => 'publishtopicdialog.messageexpiry.error'.tr(),
      },
    );
  }

  Widget _buildUserPropertyRow(TopicEditViewmodel vm, FormGroup group, int index, bool enabled) {
    return SrxFormRow(children: [
      Expanded(
          flex: 2,
          child: ReactiveTextField<String>(
            formControl: group.control(T.userPropertyKeyField) as FormControl<String>,
            readOnly: !enabled,
            decoration: InputDecoration(
                border: OutlineInputBorder(), labelText: 'publishtopicdialog.userpropertykey.label'.tr(), isDense: true),
            validationMessages: {
              ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
              ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr(),
            },
          )),
      SizedBox(width: 16),
      Expanded(
          flex: 3,
          child: ReactiveTextField<String>(
            formControl: group.control(T.userPropertyValueField) as FormControl<String>,
            readOnly: !enabled,
            decoration: InputDecoration(
                border: OutlineInputBorder(), labelText: 'publishtopicdialog.userpropertyvalue.label'.tr(), isDense: true),
            validationMessages: {ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr()},
          )),
      IconButton(
          onPressed: enabled ? () => vm.removeUserProperty(index) : null,
          tooltip: 'publishtopicdialog.removeuserproperty.tooltip'.tr(),
          icon: Icon(Icons.remove_circle_outline)),
    ]);
  }

  Widget _buildActions(BuildContext context, TopicEditViewmodel vm) {
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      SrxFormRow(alignment: CrossAxisAlignment.center, children: [
        Spacer(flex: 3),
        Expanded(
            flex: 1,
            child: OutlinedButton(
                onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('srx.common.cancel'.tr()))),
        SizedBox(width: 16),
        Expanded(
            flex: 1,
            child: ElevatedButton(onPressed: () => _onOkPressed(context), child: Text('simulator.save.button'.tr()))),
      ]),
      if (!vm.isNew) Text('simulator.topicdialog.restart.hint'.tr(), style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  void _onOkPressed(BuildContext context) {
    var topic = _viewmodel.save();
    if (topic != null) {
      GetIt.I.get<SrxNavigationService>().pop(topic);
      return;
    }
    // show the tab with the errors
    var payloadValid = _viewmodel.payloadTabValid && _viewmodel.generator.form.valid;
    _tabController.animateTo(payloadValid ? 1 : 0);
  }
}
