import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/simulator/device_edit_dialog.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/simulator_viewmodel.dart';
import 'package:mqttstudio/simulator/topic_edit_dialog.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Opens the dialogs of the simulator tab and applies their result
class SimulatorDialogs {
  static Future<T?> _show<T>(BuildContext context, Widget dialog) =>
      showDialog<T>(context: context, builder: (_) => SrxTheme(data: CustomTheme.srxTheme, child: dialog));

  static Simulation get _simulation => GetIt.I.get<ProjectManager>().currentProject!.simulation;

  static Future addDevice(BuildContext context, SimulatorViewmodel vm) async {
    var device = await _show<SimulatedDevice>(context, DeviceEditDialog(simulation: _simulation));
    if (device != null) {
      vm.addDevice(device);
    }
  }

  static Future editDevice(BuildContext context, SimulatorViewmodel vm, SimulatedDevice device) async {
    var edited = await _show<SimulatedDevice>(context, DeviceEditDialog(device: device, simulation: _simulation));
    if (edited != null) {
      vm.updateDevice(edited);
    }
  }

  static Future deleteDevice(BuildContext context, SimulatorViewmodel vm, SimulatedDevice device) async {
    if (await _confirmDelete(context, 'simulator.deletedevice.confirm'.tr(args: [device.name]))) {
      vm.deleteDevice(device);
    }
  }

  static Future addTopic(BuildContext context, SimulatorViewmodel vm, SimulatedDevice device) async {
    var topic = await _show<SimulatedTopic>(context, TopicEditDialog(device: device));
    if (topic != null) {
      vm.addTopic(device, topic);
    }
  }

  static Future editTopic(BuildContext context, SimulatorViewmodel vm, SimulatedDevice device, SimulatedTopic topic) async {
    var edited = await _show<SimulatedTopic>(context, TopicEditDialog(device: device, topic: topic));
    if (edited != null) {
      vm.updateTopic(device, edited);
    }
  }

  static Future deleteTopic(BuildContext context, SimulatorViewmodel vm, SimulatedDevice device, SimulatedTopic topic) async {
    if (await _confirmDelete(context, 'simulator.deletetopic.confirm'.tr(args: [topic.topic]))) {
      vm.deleteTopic(device, topic);
    }
  }

  static Future clearRetained(BuildContext context, SimulatorViewmodel vm) async {
    var count = vm.clearRetained();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('simulator.clearretained.done'.tr(args: ['$count']))));
  }

  static Future<bool> _confirmDelete(BuildContext context, String text) async =>
      await _show<bool>(context, SrxDialog.confirmDelete(bodyText: text)) == true;
}
