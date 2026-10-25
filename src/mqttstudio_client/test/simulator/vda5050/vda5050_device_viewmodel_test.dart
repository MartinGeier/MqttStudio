import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/model/vda5050_source.dart';
import 'package:mqttstudio/simulator/vda5050_device_viewmodel.dart';
import '../../helpers/test_setup.dart';

SimulatedDevice _newDevice() => SimulatedDevice(
    name: 'Robots', kind: DeviceKind.vda5050, instanceCount: 5, vda5050: Vda5050Source());

void main() {
  setUp(() => setUpServices());
  tearDown(tearDownServices);

  test('a new device with the defaults can be saved as entered', () {
    var vm = Vda5050DeviceViewmodel(_newDevice(), Simulation(), isNew: true);
    vm.form.control(Vda5050DeviceViewmodel.actionPercentField).value = 50;
    vm.form.control(Vda5050DeviceViewmodel.seedField).value = 7;
    var device = vm.save()!;
    expect(device.kind, DeviceKind.vda5050);
    expect(device.instanceCount, 5);
    expect(device.vda5050!.actionProbability, 0.5);
    expect(device.vda5050!.seed, 7);
    expect(vm.resolvedTopics, 'vda5050/v3/MQTTStudio/SIM-1/state … vda5050/v3/MQTTStudio/SIM-5/state');
    vm.dispose();
  });

  test('switching to 2.x suggests uagv and disables the 3.0 options', () async {
    var vm = Vda5050DeviceViewmodel(_newDevice(), Simulation(), isNew: true);
    vm.form.control(Vda5050DeviceViewmodel.versionField).value = VdaVersion.v2;
    // the form reports changes in a microtask
    await Future<void>.delayed(Duration.zero);
    expect(vm.form.control(Vda5050DeviceViewmodel.interfaceNameField).value, 'uagv');
    expect(vm.form.control(Vda5050DeviceViewmodel.zonesField).disabled, isTrue);
    vm.form.control(Vda5050DeviceViewmodel.versionField).value = VdaVersion.v3;
    await Future<void>.delayed(Duration.zero);
    expect(vm.form.control(Vda5050DeviceViewmodel.interfaceNameField).value, 'vda5050');
    expect(vm.form.control(Vda5050DeviceViewmodel.zonesField).enabled, isTrue);
    vm.dispose();
  });

  test('names with topic levels, a serial number without {n} and too small a layout are refused', () {
    var vm = Vda5050DeviceViewmodel(_newDevice(), Simulation(), isNew: true);
    vm.form.control(Vda5050DeviceViewmodel.manufacturerField).value = 'a/b';
    expect(vm.save(), isNull);
    vm.form.control(Vda5050DeviceViewmodel.manufacturerField).value = 'Acme';
    vm.form.control(Vda5050DeviceViewmodel.serialNumberField).value = 'R1';
    expect(vm.issues.map((issue) => issue.kind), [SimulationIssueKind.vdaSerialNeedsInstance]);
    vm.form.control(Vda5050DeviceViewmodel.serialNumberField).value = 'R{n}';
    vm.form.control(Vda5050DeviceViewmodel.columnsField).value = 2;
    vm.form.control(Vda5050DeviceViewmodel.rowsField).value = 2;
    expect(vm.issues.map((issue) => issue.kind), [SimulationIssueKind.vdaLayoutTooSmall]);
    expect(vm.save(), isNull);
    vm.form.control(Vda5050DeviceViewmodel.visualizationField).value = 50;
    expect(vm.form.control(Vda5050DeviceViewmodel.visualizationField).hasError('visualization'), isTrue);
    vm.dispose();
  });

  test('the dialog opens the tab with the first problem', () {
    var vm = Vda5050DeviceViewmodel(_newDevice(), Simulation(), isNew: true);
    expect(vm.tabWithErrors, isNull);
    vm.form.control(Vda5050DeviceViewmodel.maxOrderNodesField).value = 2;
    vm.form.control(Vda5050DeviceViewmodel.minOrderNodesField).value = 3;
    expect(vm.tabWithErrors, 1);
    vm.form.control(Vda5050DeviceViewmodel.columnsField).value = 1;
    expect(vm.tabWithErrors, 0);
    vm.dispose();
  });
}
