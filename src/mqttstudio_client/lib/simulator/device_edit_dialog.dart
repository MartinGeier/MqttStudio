import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/simulator/device_edit_viewmodel.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/widgets/simulator_format.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Adds or edits a simulated device: its name and its instances. Returns the SimulatedDevice or null.
class DeviceEditDialog extends StatelessWidget {
  final SimulatedDevice? device;
  final Simulation simulation;

  const DeviceEditDialog({Key? key, this.device, required this.simulation}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DeviceEditViewmodel>(
      create: (_) => DeviceEditViewmodel(device, simulation),
      child: Consumer<DeviceEditViewmodel>(builder: (context, vm, _) {
        return SimpleDialog(
          title: Text((vm.isNew ? 'simulator.devicedialog.add.title' : 'simulator.devicedialog.edit.title').tr()),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 480, maxWidth: 480),
              child: ReactiveForm(
                formGroup: vm.form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SrxFormRow(children: [Expanded(child: _buildNameField(context, vm))]),
                  SrxFormRow(children: [
                    Expanded(
                        child: _intField(DeviceEditViewmodel.instanceCountField, 'simulator.devicedialog.instances.label',
                            'simulator.devicedialog.instances.helper', context, vm)),
                    SizedBox(width: 16),
                    Expanded(
                        child: _intField(DeviceEditViewmodel.firstInstanceField, 'simulator.devicedialog.firstinstance.label',
                            'simulator.devicedialog.firstinstance.helper', context, vm)),
                  ]),
                  if (!vm.isNew && device!.topics.isNotEmpty) _buildResolvedTopics(context, vm),
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

  Widget _buildNameField(BuildContext context, DeviceEditViewmodel vm) {
    return ReactiveTextField<String>(
      formControlName: DeviceEditViewmodel.nameField,
      autofocus: true,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'simulator.devicedialog.name.label'.tr(), isDense: true),
      validationMessages: {
        ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
        ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr(),
        'duplicate': (_) => 'simulator.issue.deviceNameDuplicate'.tr(),
      },
      onSubmitted: (_) => _onOkPressed(vm),
    );
  }

  Widget _intField(String name, String labelKey, String helperKey, BuildContext context, DeviceEditViewmodel vm) {
    return ReactiveTextField<int>(
      formControlName: name,
      decoration: InputDecoration(
          border: OutlineInputBorder(), labelText: labelKey.tr(), helperText: helperKey.tr(), isDense: true),
      validationMessages: {
        ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
        ValidationMessage.min: (_) => 'simulator.value.toosmall.error'.tr(),
        ValidationMessage.max: (_) => 'simulator.value.toolarge.error'.tr(),
        ValidationMessage.number: (_) => 'simulator.value.number.error'.tr(),
      },
      onSubmitted: (_) => _onOkPressed(vm),
    );
  }

  Widget _buildResolvedTopics(BuildContext context, DeviceEditViewmodel vm) {
    var theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('simulator.devicedialog.publishesto.label'.tr(), style: theme.textTheme.bodySmall),
        SizedBox(height: 6),
        for (var topic in vm.resolvedTopics) Text(topic, style: theme.textTheme.bodyLarge!.copyWith(height: 1.7)),
        SizedBox(height: 6),
        Text(SimulatorFormat.rate(vm.rate), style: theme.textTheme.bodySmall),
        if (vm.hasTopicsWithoutInstance)
          Text('simulator.devicedialog.topicswithoutn.warning'.tr(),
              style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error)),
      ]),
    );
  }

  Widget _buildActions(BuildContext context, DeviceEditViewmodel vm) {
    return SrxFormRow(alignment: CrossAxisAlignment.center, children: [
      Spacer(flex: 1),
      Expanded(
          flex: 5,
          child: OutlinedButton(
              onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('srx.common.cancel'.tr()))),
      SizedBox(width: 16),
      Expanded(flex: 5, child: ElevatedButton(onPressed: () => _onOkPressed(vm), child: Text('simulator.save.button'.tr()))),
    ]);
  }

  void _onOkPressed(DeviceEditViewmodel vm) {
    var device = vm.save();
    if (device != null) {
      GetIt.I.get<SrxNavigationService>().pop(device);
    }
  }
}
