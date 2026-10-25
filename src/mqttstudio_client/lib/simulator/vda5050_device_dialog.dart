import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/vda5050_device_viewmodel.dart';
import 'package:mqttstudio/simulator/widgets/simulator_format.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

typedef _V = Vda5050DeviceViewmodel;

// Adds or edits a device of simulated VDA 5050 robots (doc/vda5050-design.md §10.6). The ROBOTS tab has what is set
// most often: the robots, their names and the layout; the SIMULATION tab has orders, battery, messages, faults and the
// 3.0 options. Returns the SimulatedDevice or null.
class Vda5050DeviceDialog extends StatefulWidget {
  final SimulatedDevice device;
  final Simulation simulation;
  final bool isNew;

  const Vda5050DeviceDialog({Key? key, required this.device, required this.simulation, required this.isNew})
      : super(key: key);

  @override
  State<Vda5050DeviceDialog> createState() => _Vda5050DeviceDialogState();
}

class _Vda5050DeviceDialogState extends State<Vda5050DeviceDialog> with SingleTickerProviderStateMixin {
  late final Vda5050DeviceViewmodel _viewmodel;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _viewmodel = Vda5050DeviceViewmodel(widget.device, widget.simulation, isNew: widget.isNew);
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
      child: Consumer<Vda5050DeviceViewmodel>(builder: (context, vm, _) {
        return SimpleDialog(
          title: Text((vm.isNew ? 'vda5050device.add.title' : 'vda5050device.edit.title').tr()),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 840, maxWidth: 840),
              child: ReactiveForm(
                formGroup: vm.form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _buildTabs(context),
                  SizedBox(height: 16),
                  // both tabs take the height of the taller one, so the dialog keeps its size and position
                  IndexedStack(
                    index: _tabController.index,
                    children: [_buildRobotsTab(context, vm), _buildSimulationTab(context, vm)],
                  ),
                  _buildTopics(context, vm),
                  _buildIssues(context, vm),
                  SizedBox(height: 16),
                  _buildActions(vm),
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
        tabs: [Tab(text: 'vda5050device.robots.tab'.tr()), Tab(text: 'vda5050device.simulation.tab'.tr())],
      ),
    );
  }

  // ---------- ROBOTS ----------

  Widget _buildRobotsTab(BuildContext context, Vda5050DeviceViewmodel vm) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SrxFormRow(children: [
        Expanded(
          flex: 6,
          child: ReactiveTextField<String>(
            formControlName: _V.nameField,
            autofocus: true,
            decoration: _decoration('simulator.devicedialog.name.label'),
            validationMessages: {..._messages, 'duplicate': (_) => 'simulator.issue.deviceNameDuplicate'.tr()},
            onSubmitted: (_) => _onSavePressed(vm),
          ),
        ),
        SizedBox(width: 16),
        Expanded(flex: 2, child: _number<int>(vm, _V.robotsField, 'vda5050device.robots.label')),
        SizedBox(width: 16),
        Expanded(flex: 2, child: _number<int>(vm, _V.firstInstanceField, 'simulator.devicedialog.firstinstance.label')),
      ]),
      _buildSection(context, 'vda5050device.robots.section'),
      SrxFormRow(children: [
        Expanded(
          flex: 2,
          child: ReactiveDropdownField<VdaVersion>(
            formControlName: _V.versionField,
            decoration: _decoration('vda5050device.version.label'),
            items: [
              for (var version in VdaVersion.values)
                DropdownMenuItem(value: version, child: Text('VDA 5050 ${version.protocolVersion}'))
            ],
          ),
        ),
        SizedBox(width: 16),
        Expanded(flex: 2, child: _text(vm, _V.interfaceNameField, 'vda5050device.interfacename.label')),
        SizedBox(width: 16),
        Expanded(flex: 2, child: _text(vm, _V.manufacturerField, 'vda5050device.manufacturer.label')),
        SizedBox(width: 16),
        Expanded(
            flex: 2,
            child: _text(vm, _V.serialNumberField, 'vda5050device.serialnumber.label',
                helperKey: 'vda5050device.serialnumber.helper')),
      ]),
      _buildSection(context, 'vda5050device.layout.section'),
      SrxFormRow(children: [
        Expanded(flex: 2, child: _number<int>(vm, _V.columnsField, 'vda5050device.columns.label')),
        SizedBox(width: 16),
        Expanded(flex: 2, child: _number<int>(vm, _V.rowsField, 'vda5050device.rows.label')),
        SizedBox(width: 16),
        Expanded(flex: 2, child: _number<double>(vm, _V.spacingField, 'vda5050device.spacing.label')),
        SizedBox(width: 16),
        Expanded(flex: 2, child: _number<int>(vm, _V.chargingStationsField, 'vda5050device.chargingstations.label')),
        SizedBox(width: 16),
        Expanded(flex: 3, child: _text(vm, _V.mapIdField, 'vda5050device.mapid.label')),
      ]),
    ]);
  }

  // ---------- SIMULATION ----------

  Widget _buildSimulationTab(BuildContext context, Vda5050DeviceViewmodel vm) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildSection(context, 'vda5050device.orders.section', top: false),
      SrxFormRow(children: [
        Expanded(child: _number<int>(vm, _V.minOrderNodesField, 'vda5050device.minnodes.label')),
        SizedBox(width: 16),
        Expanded(child: _number<int>(vm, _V.maxOrderNodesField, 'vda5050device.maxnodes.label')),
        SizedBox(width: 16),
        Expanded(
            child: _number<int>(vm, _V.horizonNodesField, 'vda5050device.horizon.label',
                helperKey: 'vda5050device.horizon.helper')),
        SizedBox(width: 16),
        Expanded(child: _number<int>(vm, _V.actionPercentField, 'vda5050device.actions.label')),
      ]),
      SrxFormRow(children: [
        Expanded(child: _number<int>(vm, _V.minActionSecField, 'vda5050device.minaction.label')),
        SizedBox(width: 16),
        Expanded(child: _number<int>(vm, _V.maxActionSecField, 'vda5050device.maxaction.label')),
        SizedBox(width: 16),
        Expanded(child: _number<int>(vm, _V.minIdleSecField, 'vda5050device.minidle.label')),
        SizedBox(width: 16),
        Expanded(child: _number<int>(vm, _V.maxIdleSecField, 'vda5050device.maxidle.label')),
      ]),
      _buildSection(context, 'vda5050device.driving.section'),
      SrxFormRow(alignment: CrossAxisAlignment.start, children: [
        Expanded(child: _number<double>(vm, _V.speedField, 'vda5050device.speed.label')),
        SizedBox(width: 16),
        Expanded(child: _number<double>(vm, _V.batteryPerHourField, 'vda5050device.battery.label')),
        SizedBox(width: 16),
        Expanded(child: _number<double>(vm, _V.chargePerHourField, 'vda5050device.charge.label')),
        SizedBox(width: 16),
        Expanded(
            child: _number<double>(vm, _V.randomFaultsField, 'vda5050device.randomfaults.label',
                helperKey: 'vda5050device.randomfaults.helper')),
      ]),
      _buildSection(context, 'vda5050device.messages.section'),
      SrxFormRow(alignment: CrossAxisAlignment.start, children: [
        Expanded(child: _number<int>(vm, _V.heartbeatField, 'vda5050device.heartbeat.label')),
        SizedBox(width: 16),
        Expanded(
            child: _number<int>(vm, _V.visualizationField, 'vda5050device.visualization.label',
                helperKey: 'vda5050device.visualization.helper')),
        SizedBox(width: 16),
        Expanded(
            child: _number<int>(vm, _V.seedField, 'vda5050device.seed.label', helperKey: 'vda5050device.seed.helper')),
        SizedBox(width: 16),
        Expanded(
            child: CheckboxField(
                formControlName: _V.factsheetField, form: vm.form, label: 'vda5050device.factsheet.label'.tr())),
      ]),
      _buildSection(context, 'vda5050device.v3.section'),
      // visible for 2.x robots too, but disabled
      SrxFormRow(children: [
        Expanded(
            child: CheckboxField(formControlName: _V.zonesField, form: vm.form, label: 'vda5050device.zones.label'.tr())),
        SizedBox(width: 16),
        Expanded(
            child: CheckboxField(
                formControlName: _V.requestsField, form: vm.form, label: 'vda5050device.requests.label'.tr())),
      ]),
    ]);
  }

  // ---------- both tabs ----------

  Widget _buildSection(BuildContext context, String key, {bool top = true}) {
    return Padding(
      padding: EdgeInsets.only(top: top ? 8 : 0, bottom: 8),
      child: Text(key.tr(), style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _buildTopics(BuildContext context, Vda5050DeviceViewmodel vm) {
    var theme = Theme.of(context);
    if (!vm.form.valid) {
      return SizedBox.shrink();
    }
    return Container(
      margin: EdgeInsets.only(top: 8),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(4)),
      child: Row(children: [
        Text('simulator.devicedialog.publishesto.label'.tr(), style: theme.textTheme.bodySmall),
        SizedBox(width: 12),
        Expanded(child: Text(vm.resolvedTopics, style: theme.textTheme.bodyLarge, overflow: TextOverflow.ellipsis)),
        SizedBox(width: 12),
        Text(SimulatorFormat.rate(vm.rate), style: theme.textTheme.bodySmall),
      ]),
    );
  }

  Widget _buildIssues(BuildContext context, Vda5050DeviceViewmodel vm) {
    var theme = Theme.of(context);
    var issues = vm.issues;
    if (issues.isEmpty) {
      return SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var issue in issues)
          Text('simulator.issue.${issue.kind.name}'.tr(args: [issue.detail]),
              style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error)),
      ]),
    );
  }

  Widget _buildActions(Vda5050DeviceViewmodel vm) {
    return SrxFormRow(alignment: CrossAxisAlignment.center, children: [
      Spacer(flex: 1),
      Expanded(
          flex: 5,
          child: OutlinedButton(
              onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('srx.common.cancel'.tr()))),
      SizedBox(width: 16),
      Expanded(flex: 5, child: ElevatedButton(onPressed: () => _onSavePressed(vm), child: Text('simulator.save.button'.tr()))),
    ]);
  }

  InputDecoration _decoration(String labelKey, {String? helperKey}) => InputDecoration(
      border: OutlineInputBorder(), labelText: labelKey.tr(), helperText: helperKey?.tr(), isDense: true);

  static Map<String, String Function(Object)> get _messages => {
        ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
        ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr(),
        ValidationMessage.min: (_) => 'simulator.value.toosmall.error'.tr(),
        ValidationMessage.max: (_) => 'simulator.value.toolarge.error'.tr(),
        ValidationMessage.number: (_) => 'simulator.value.number.error'.tr(),
        'level': (_) => 'vda5050device.level.error'.tr(),
        'visualization': (_) => 'vda5050device.visualization.error'.tr(),
      };

  Widget _text(Vda5050DeviceViewmodel vm, String name, String labelKey, {String? helperKey}) {
    return ReactiveTextField<String>(
      formControlName: name,
      decoration: _decoration(labelKey, helperKey: helperKey),
      validationMessages: _messages,
      onSubmitted: (_) => _onSavePressed(vm),
    );
  }

  Widget _number<T>(Vda5050DeviceViewmodel vm, String name, String labelKey, {String? helperKey}) {
    return ReactiveTextField<T>(
      formControlName: name,
      decoration: _decoration(labelKey, helperKey: helperKey),
      validationMessages: _messages,
      onSubmitted: (_) => _onSavePressed(vm),
    );
  }

  void _onSavePressed(Vda5050DeviceViewmodel vm) {
    var device = vm.save();
    if (device != null) {
      GetIt.I.get<SrxNavigationService>().pop(device);
      return;
    }
    // show the tab with the errors
    var tab = vm.tabWithErrors;
    if (tab != null) {
      _tabController.animateTo(tab);
    }
  }
}
