import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/model/vda5050_source.dart';
import 'package:mqttstudio/simulator/simulator.dart';
import 'package:mqttstudio/simulator/simulator_page.dart';
import 'package:mqttstudio/simulator/vda5050_device_dialog.dart';
import 'package:mqttstudio/simulator/widgets/robot_fault_menu.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../../helpers/fake_mqtt_adapter.dart';
import '../../helpers/test_app.dart';
import '../../helpers/test_setup.dart';

void main() {
  late FakeMqttAdapter adapter;

  setUpAll(loadTranslations);

  setUp(() {
    adapter = setUpServices();
    GetIt.I.registerSingleton(SrxNavigationService(Container(), Container()));
  });

  tearDown(() async {
    GetIt.I.get<Simulator>().dispose();
    await tearDownServices();
  });

  Future<Project> pumpPage(WidgetTester tester, {bool withRobots = false}) async {
    await tester.binding.setSurfaceSize(Size(1600, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var project = await openNewProject();
    if (withRobots) {
      project.simulation.devices.add(SimulatedDevice(
          name: 'Robots', kind: DeviceKind.vda5050, instanceCount: 2, vda5050: Vda5050Source(seed: 1)));
    }
    await adapter.connect(project.mqttSettings);
    await tester.pumpWidget(testApp(SimulatorPage()));
    await tester.pumpAndSettle();
    return project;
  }

  // the test font draws wide squares, so some rows overflow that fit in the app
  void testPage(String description, Future<void> Function(WidgetTester tester) body) =>
      testWidgets(description, (tester) => ignoringOverflowErrors(() => body(tester)));

  testPage('the device dialog splits its settings on two tabs', (tester) async {
    var project = await pumpPage(tester);
    await tester.tap(find.text('ADD DEVICE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VDA 5050 robots').last);
    await tester.pumpAndSettle();
    expect(find.byType(Vda5050DeviceDialog), findsOneWidget);
    expect(find.text('Serial number'), findsOneWidget);
    expect(find.text('Nodes from'), findsNothing);

    await tester.tap(find.text('SIMULATION'));
    await tester.pumpAndSettle();
    expect(find.text('Nodes from'), findsOneWidget);
    expect(find.text('Serial number'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Nodes from'), '1');
    await tester.tap(find.text('ROBOTS'));
    await tester.pumpAndSettle();

    // saving shows the tab with the error
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(find.text('Nodes from'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Nodes from'), '3');
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(find.byType(Vda5050DeviceDialog), findsNothing);
    expect(project.simulation.devices.last.vda5050!.minOrderNodes, 3);
    expect(find.textContaining('SIM-5', findRichText: true), findsWidgets);
  });

  testPage('the faults menu has two columns and injects a fault', (tester) async {
    await pumpPage(tester, withRobots: true);
    await tester.tap(find.byTooltip('Start device').last);
    await tester.pump(Duration(seconds: 1));
    await tester.pump(Duration(milliseconds: 600));

    await tester.tap(find.byTooltip('Faults').first);
    await tester.pumpAndSettle();
    expect(find.byType(RobotFaultMenu), findsOneWidget);
    // the popup must not squeeze the two columns
    expect(tester.getSize(find.byType(RobotFaultMenu)).width, RobotFaultMenu.width);
    var robot = tester.getTopLeft(find.text('Robot'));
    var connection = tester.getTopLeft(find.text('Connection'));
    var protocol = tester.getTopLeft(find.text('Protocol'));
    expect(connection.dx, greaterThan(robot.dx + 200));
    expect(protocol.dx, connection.dx);
    expect(connection.dy, robot.dy);

    await tester.tap(find.text('Fatal error'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(Duration(milliseconds: 100));
    }
    expect(find.byType(RobotFaultMenu), findsNothing);
    expect(find.textContaining('Stopped by an error'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop all simulated topics'));
    await tester.pump();
    // lets the statistics timer run out
    await tester.pump(Duration(seconds: 1));
  });
}
