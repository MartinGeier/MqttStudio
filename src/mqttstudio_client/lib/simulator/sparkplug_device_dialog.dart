import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/model/sparkplug_source.dart';
import 'package:mqttstudio/simulator/sparkplug_device_viewmodel.dart';
import 'package:mqttstudio/simulator/sparkplug_metric_dialog.dart';
import 'package:mqttstudio/simulator/widgets/simulator_format.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

typedef _V = SparkplugDeviceViewmodel;

// Adds or edits a device of simulated Sparkplug B edge nodes (doc/sparkplug-design.md §10.6). EDGE NODE has the
// edge nodes, their ids and the primary host, METRICS the metrics of the edge node and its devices, ADVANCED the scan,
// aliases, compression and seed. Returns the SimulatedDevice or null.
class SparkplugDeviceDialog extends StatefulWidget {
  // the METRICS tab scrolls inside this height, so the dialog keeps its size
  static const double metricsHeight = 400;

  final SimulatedDevice device;
  final Simulation simulation;
  final bool isNew;

  const SparkplugDeviceDialog({Key? key, required this.device, required this.simulation, required this.isNew})
    : super(key: key);

  @override
  State<SparkplugDeviceDialog> createState() => _SparkplugDeviceDialogState();
}

class _SparkplugDeviceDialogState extends State<SparkplugDeviceDialog> with SingleTickerProviderStateMixin {
  late final SparkplugDeviceViewmodel _viewmodel;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _viewmodel = SparkplugDeviceViewmodel(widget.device, widget.simulation, isNew: widget.isNew);
    _tabController = TabController(length: 3, vsync: this)..addListener(() => setState(() {}));
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
      child: Consumer<SparkplugDeviceViewmodel>(
        builder: (context, vm, _) => SimpleDialog(
          title: Text((vm.isNew ? 'sparkplugdevice.add.title' : 'sparkplugdevice.edit.title').tr()),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 840, maxWidth: 840),
              child: ReactiveForm(
                formGroup: vm.form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTabs(context),
                    SizedBox(height: 16),
                    // the tabs take the height of the tallest one, so the dialog keeps its size and position
                    IndexedStack(
                      index: _tabController.index,
                      children: [
                        _buildNodeTab(context, vm),
                        _buildMetricsTab(context, vm),
                        _buildAdvancedTab(context, vm),
                      ],
                    ),
                    _buildTopics(context, vm),
                    _buildIssues(context, vm),
                    SizedBox(height: 16),
                    _buildActions(vm),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs(BuildContext context) {
    var theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.hintColor,
        indicatorColor: theme.colorScheme.primary,
        tabs: [
          Tab(text: 'sparkplugdevice.node.tab'.tr()),
          Tab(text: 'sparkplugdevice.metrics.tab'.tr()),
          Tab(text: 'sparkplugdevice.advanced.tab'.tr()),
        ],
      ),
    );
  }

  // ---------- EDGE NODE ----------

  Widget _buildNodeTab(BuildContext context, SparkplugDeviceViewmodel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SrxFormRow(
          children: [
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
            Expanded(flex: 2, child: _field<int>(vm, _V.nodesField, 'sparkplugdevice.nodes.label')),
            SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: _field<int>(vm, _V.firstInstanceField, 'simulator.devicedialog.firstinstance.label'),
            ),
          ],
        ),
        _buildSection(context, 'sparkplugdevice.ids.section'),
        SrxFormRow(
          alignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field<String>(vm, _V.groupIdField, 'sparkplugdevice.groupid.label')),
            SizedBox(width: 16),
            Expanded(
              child: _field<String>(
                vm,
                _V.edgeNodeIdField,
                'sparkplugdevice.edgenodeid.label',
                helperKey: 'sparkplugdevice.edgenodeid.helper',
              ),
            ),
          ],
        ),
        _buildSection(context, 'sparkplugdevice.host.section'),
        SrxFormRow(
          alignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field<String>(
                vm,
                _V.primaryHostField,
                'sparkplugdevice.primaryhost.label',
                helperKey: 'sparkplugdevice.primaryhost.helper',
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Tooltip(
                message: 'sparkplugdevice.simulatehost.tooltip'.tr(),
                child: CheckboxField(
                  formControlName: _V.simulateHostField,
                  form: vm.form,
                  label: 'sparkplugdevice.simulatehost.label'.tr(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------- METRICS ----------

  Widget _buildMetricsTab(BuildContext context, SparkplugDeviceViewmodel vm) {
    return SizedBox(
      height: SparkplugDeviceDialog.metricsHeight,
      child: ListView(
        children: [
          _buildMetricsHeader(context, vm, null, Text('sparkplugdevice.nodemetrics.label'.tr())),
          _buildMetrics(context, vm, null),
          for (var i = 0; i < vm.devicesArray.controls.length; i++) ...[
            SizedBox(height: 16),
            _buildDeviceHeader(context, vm, i),
            _buildMetrics(context, vm, i),
          ],
          SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: vm.addDevice,
              icon: Icon(Icons.add),
              label: Text('sparkplugdevice.adddevice.button'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsHeader(BuildContext context, SparkplugDeviceViewmodel vm, int? device, Widget title) {
    return Row(
      children: [
        Expanded(
          child: DefaultTextStyle(style: Theme.of(context).textTheme.titleMedium!, child: title),
        ),
        TextButton.icon(
          onPressed: () => _editMetric(context, vm, device, null),
          icon: Icon(Icons.add),
          label: Text('sparkplugdevice.addmetric.button'.tr()),
        ),
      ],
    );
  }

  // a device: its id with {d}, how many there are on each edge node, and its metrics
  Widget _buildDeviceHeader(BuildContext context, SparkplugDeviceViewmodel vm, int index) {
    return ReactiveForm(
      formGroup: vm.devicesArray.controls[index] as FormGroup,
      child: _buildMetricsHeader(
        context,
        vm,
        index,
        Row(
          children: [
            SizedBox(
              width: 260,
              child: ReactiveTextField<String>(
                formControlName: _V.deviceIdField,
                decoration: _decoration('sparkplugdevice.deviceid.label'),
                validationMessages: _messages,
              ),
            ),
            SizedBox(width: 16),
            SizedBox(
              width: 120,
              child: ReactiveTextField<int>(
                formControlName: _V.deviceCountField,
                decoration: _decoration('sparkplugdevice.devicecount.label'),
                validationMessages: _messages,
              ),
            ),
            SizedBox(width: 4),
            IconButton(
              onPressed: () => vm.removeDevice(index),
              icon: Icon(Icons.delete),
              tooltip: 'sparkplugdevice.removedevice.tooltip'.tr(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetrics(BuildContext context, SparkplugDeviceViewmodel vm, int? device) {
    var theme = Theme.of(context);
    var metrics = vm.metricsOf(device);
    if (metrics.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('sparkplugdevice.nometrics.label'.tr(), style: TextStyle(color: theme.hintColor)),
      );
    }
    return Column(children: [for (var metric in metrics) _buildMetricRow(context, vm, device, metric)]);
  }

  Widget _buildMetricRow(BuildContext context, SparkplugDeviceViewmodel vm, int? device, SparkplugMetricSpec metric) {
    var theme = Theme.of(context);
    var hint = TextStyle(color: theme.hintColor);
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(metric.name, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
          ),
          Expanded(flex: 2, child: Text(metric.type.label)),
          Expanded(flex: 3, child: Text(SimulatorFormat.generatorName(metric.generator.type), style: hint)),
          Expanded(flex: 2, child: Text(metric.unit ?? '', style: hint)),
          Expanded(
            flex: 2,
            child: Text(
              metric.deadband > 0 ? 'sparkplugdevice.deadband.value'.tr(args: ['${metric.deadband}']) : '',
              style: hint,
            ),
          ),
          SizedBox(
            width: 32,
            child: metric.writable
                ? Tooltip(message: 'sparkplugmetric.writable.label'.tr(), child: Icon(Icons.edit_note, size: 20))
                : null,
          ),
          IconButton(
            onPressed: () => _editMetric(context, vm, device, metric),
            icon: Icon(Icons.edit),
            tooltip: 'sparkplugdevice.editmetric.tooltip'.tr(),
          ),
          IconButton(
            onPressed: () => vm.removeMetric(device, metric),
            icon: Icon(Icons.delete),
            tooltip: 'sparkplugdevice.removemetric.tooltip'.tr(),
          ),
        ],
      ),
    );
  }

  Future<void> _editMetric(
    BuildContext context,
    SparkplugDeviceViewmodel vm,
    int? device,
    SparkplugMetricSpec? metric,
  ) async {
    var edited = await showDialog<SparkplugMetricSpec>(
      context: context,
      builder: (_) => SrxTheme(
        data: CustomTheme.srxTheme,
        child: SparkplugMetricDialog(metric: metric, otherNames: vm.otherNames(device, metric)),
      ),
    );
    if (edited != null) {
      vm.putMetric(device, metric, edited);
    }
  }

  // ---------- ADVANCED ----------

  Widget _buildAdvancedTab(BuildContext context, SparkplugDeviceViewmodel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SrxFormRow(
          alignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field<int>(
                vm,
                _V.scanField,
                'sparkplugdevice.scan.label',
                helperKey: 'sparkplugdevice.scan.helper',
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: _field<int>(vm, _V.seedField, 'vda5050device.seed.label', helperKey: 'vda5050device.seed.helper'),
            ),
          ],
        ),
        SizedBox(height: 8),
        SrxFormRow(
          children: [
            Expanded(
              child: Tooltip(
                message: 'sparkplugdevice.aliases.tooltip'.tr(),
                child: CheckboxField(
                  formControlName: _V.aliasesField,
                  form: vm.form,
                  label: 'sparkplugdevice.aliases.label'.tr(),
                ),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Tooltip(
                message: 'sparkplugdevice.compress.tooltip'.tr(),
                child: CheckboxField(
                  formControlName: _V.compressField,
                  form: vm.form,
                  label: 'sparkplugdevice.compress.label'.tr(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------- all tabs ----------

  Widget _buildSection(BuildContext context, String key) {
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: 8),
      child: Text(key.tr(), style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _buildTopics(BuildContext context, SparkplugDeviceViewmodel vm) {
    var theme = Theme.of(context);
    if (!vm.form.valid) {
      return SizedBox.shrink();
    }
    return Container(
      margin: EdgeInsets.only(top: 8),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text('simulator.devicedialog.publishesto.label'.tr(), style: theme.textTheme.bodySmall),
          SizedBox(width: 12),
          Expanded(
            child: Text(vm.resolvedTopics, style: theme.textTheme.bodyLarge, overflow: TextOverflow.ellipsis),
          ),
          SizedBox(width: 12),
          Text(
            'sparkplugdevice.rate.label'.tr(args: [SimulatorFormat.rate(vm.rate)]),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildIssues(BuildContext context, SparkplugDeviceViewmodel vm) {
    var theme = Theme.of(context);
    var issues = vm.issues;
    if (issues.isEmpty) {
      return SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var issue in issues)
            Text(
              'simulator.issue.${issue.kind.name}'.tr(args: [issue.detail]),
              style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error),
            ),
        ],
      ),
    );
  }

  Widget _buildActions(SparkplugDeviceViewmodel vm) {
    return SrxFormRow(
      alignment: CrossAxisAlignment.center,
      children: [
        Spacer(flex: 1),
        Expanded(
          flex: 5,
          child: OutlinedButton(
            onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null),
            child: Text('srx.common.cancel'.tr()),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          flex: 5,
          child: ElevatedButton(onPressed: () => _onSavePressed(vm), child: Text('simulator.save.button'.tr())),
        ),
      ],
    );
  }

  InputDecoration _decoration(String labelKey, {String? helperKey}) => InputDecoration(
    border: OutlineInputBorder(),
    labelText: labelKey.tr(),
    helperText: helperKey?.tr(),
    isDense: true,
  );

  static Map<String, String Function(Object)> get _messages => {
    ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
    ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr(),
    ValidationMessage.min: (_) => 'simulator.value.toosmall.error'.tr(),
    ValidationMessage.max: (_) => 'simulator.value.toolarge.error'.tr(),
    ValidationMessage.number: (_) => 'simulator.value.number.error'.tr(),
    'level': (_) => 'vda5050device.level.error'.tr(),
  };

  Widget _field<T>(SparkplugDeviceViewmodel vm, String name, String labelKey, {String? helperKey}) {
    return ReactiveTextField<T>(
      formControlName: name,
      decoration: _decoration(labelKey, helperKey: helperKey),
      validationMessages: _messages,
      onSubmitted: (_) => _onSavePressed(vm),
    );
  }

  void _onSavePressed(SparkplugDeviceViewmodel vm) {
    var device = vm.save();
    if (device != null) {
      GetIt.I.get<SrxNavigationService>().pop(device);
      return;
    }
    var tab = vm.tabWithErrors;
    if (tab != null) {
      _tabController.animateTo(tab);
    }
  }
}
