import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/simulator/simulator_viewmodel.dart';
import 'package:mqttstudio/simulator/widgets/simulator_dialogs.dart';
import 'package:mqttstudio/simulator/widgets/simulator_format.dart';
import 'package:provider/provider.dart';

// The toolbar of the simulator tab, laid out like the command bar of the topic viewer
class SimulatorCommandBar extends StatelessWidget {
  const SimulatorCommandBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<SimulatorViewmodel>();
    return Column(
      children: [
        Divider(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              _buildStartStopButtons(vm),
              SizedBox(height: 40, child: VerticalDivider()),
              _buildAddButtons(context, vm),
              SizedBox(height: 40, child: VerticalDivider()),
              _buildClearRetainedButton(context, vm),
            ]),
            _buildRate(context, vm),
          ],
        ),
        Divider(height: 4),
      ],
    );
  }

  Widget _buildStartStopButtons(SimulatorViewmodel vm) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: OverflowBar(spacing: 6, children: [
        IconButton(
            onPressed: vm.canStart && vm.topicCount > vm.runningCount ? vm.startAll : null,
            icon: Icon(Icons.play_arrow),
            color: Colors.green,
            tooltip: vm.isProjectOpen && !vm.isConnected
                ? 'simulator.connectfirst.tooltip'.tr()
                : 'simulator.startall.tooltip'.tr()),
        IconButton(
            onPressed: vm.isAnyRunning ? vm.stopAll : null,
            icon: Icon(Icons.stop),
            tooltip: 'simulator.stopall.tooltip'.tr()),
      ]),
    );
  }

  Widget _buildAddButtons(BuildContext context, SimulatorViewmodel vm) {
    return Row(children: [
      Tooltip(
        message: 'simulator.adddevice.tooltip'.tr(),
        child: TextButton.icon(
            onPressed: vm.isProjectOpen ? () => SimulatorDialogs.addDevice(context, vm) : null,
            icon: Icon(Icons.devices_other),
            label: Text('simulator.adddevice.button'.tr())),
      ),
      Tooltip(
        message: 'simulator.addtopic.tooltip'.tr(),
        child: TextButton.icon(
            onPressed: vm.isProjectOpen ? () => SimulatorDialogs.addTopic(context, vm, vm.deviceForNewTopic()) : null,
            icon: Icon(Icons.add),
            label: Text('simulator.addtopic.button'.tr())),
      ),
    ]);
  }

  Widget _buildClearRetainedButton(BuildContext context, SimulatorViewmodel vm) {
    return Tooltip(
      message: 'simulator.clearretained.tooltip'.tr(),
      child: TextButton.icon(
          onPressed: vm.canStart && vm.hasRetainedTopics ? () => SimulatorDialogs.clearRetained(context, vm) : null,
          icon: Icon(Icons.unpublished),
          label: Text('simulator.clearretained.button'.tr())),
    );
  }

  Widget _buildRate(BuildContext context, SimulatorViewmodel vm) {
    var theme = Theme.of(context);
    var caption = vm.isRateHigh
        ? 'simulator.ratewarning.label'.tr()
        : 'simulator.running.label'.tr(args: ['${vm.runningCount}', '${vm.topicCount}']);
    return Tooltip(
      message: 'simulator.rate.tooltip'.tr(),
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(children: [
          Icon(vm.isRateHigh ? Icons.warning : Icons.speed, color: vm.isProjectOpen ? null : theme.disabledColor),
          SizedBox(width: 6),
          Text(SimulatorFormat.rate(vm.runningRate), style: theme.textTheme.labelLarge),
          SizedBox(width: 6),
          Text(caption, style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}
