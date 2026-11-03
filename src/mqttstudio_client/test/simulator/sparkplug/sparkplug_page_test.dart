import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/model/sparkplug_source.dart';
import 'package:mqttstudio/simulator/simulator.dart';
import 'package:mqttstudio/simulator/simulator_page.dart';
import 'package:mqttstudio/simulator/sparkplug/simulated_edge_node.dart';
import 'package:mqttstudio/simulator/sparkplug_device_dialog.dart';
import 'package:mqttstudio/simulator/sparkplug_metric_dialog.dart';
import 'package:mqttstudio/simulator/widgets/sparkplug_fault_menu.dart';
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

  Future<Project> pumpPage(WidgetTester tester, {bool withEdgeNodes = false}) async {
    await tester.binding.setSurfaceSize(Size(1600, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var project = await openNewProject();
    if (withEdgeNodes) {
      project.simulation.devices.add(
        SimulatedDevice(
          name: 'Line 1',
          kind: DeviceKind.sparkplug,
          instanceCount: 2,
          sparkplug: SparkplugSource.example()..seed = 1,
        ),
      );
    }
    await adapter.connect(project.mqttSettings);
    await tester.pumpWidget(testApp(SimulatorPage()));
    await tester.pumpAndSettle();
    return project;
  }

  // the test font draws wide squares, so some rows overflow that fit in the app
  void testPage(String description, Future<void> Function(WidgetTester tester) body) =>
      testWidgets(description, (tester) => ignoringOverflowErrors(() => body(tester)));

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('ADD DEVICE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sparkplug edge nodes').last);
    await tester.pumpAndSettle();
    expect(find.byType(SparkplugDeviceDialog), findsOneWidget);
  }

  testPage('the dialog edits the edge nodes, their metrics and devices on three tabs', (tester) async {
    var project = await pumpPage(tester);
    await openDialog(tester);
    expect(find.text('Group id'), findsOneWidget);
    expect(find.text('Temperature'), findsNothing);

    await tester.tap(find.text('METRICS'));
    await tester.pumpAndSettle();
    expect(find.text('Uptime'), findsOneWidget);
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Group id'), findsNothing);

    // a new metric of the edge node
    await tester.tap(find.text('Add metric').first);
    await tester.pumpAndSettle();
    expect(find.byType(SparkplugMetricDialog), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Level');
    await tester.enterText(find.widgetWithText(TextField, 'Unit'), 'm');
    await tester.tap(find.text('SAVE').last);
    await tester.pumpAndSettle();
    expect(find.byType(SparkplugMetricDialog), findsNothing);
    expect(find.text('Level'), findsOneWidget);

    // a name every edge node has is refused
    await tester.tap(find.text('Add metric').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'bdSeq');
    await tester.tap(find.text('SAVE').last);
    await tester.pumpAndSettle();
    expect(find.text('Every edge node has this metric'), findsOneWidget);
    await tester.tap(find.byType(OutlinedButton).last);
    await tester.pumpAndSettle();

    // the list of metrics scrolls inside the dialog
    await tester.scrollUntilVisible(
      find.text('Add device'),
      200,
      scrollable: find
          .descendant(
            of: find.descendant(of: find.byType(SparkplugDeviceDialog), matching: find.byType(ListView)),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Add device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(find.byType(SparkplugDeviceDialog), findsNothing);
    var source = project.simulation.devices.last.sparkplug!;
    expect(source.nodeMetrics.map((metric) => metric.name), ['Uptime', 'Firmware', 'Level']);
    expect(source.nodeMetrics.last.unit, 'm');
    expect(source.devices.map((device) => device.id), ['Pump', 'Device2']);
    expect(project.simulation.devices.last.instanceCount, 2);
  });

  testPage('saving shows the tab with the problem', (tester) async {
    await pumpPage(tester);
    await openDialog(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Edge node id'), 'Edge');
    await tester.tap(find.text('ADVANCED'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(find.text('Group id'), findsOneWidget);
    expect(find.text('With more than one edge node the edge node id must contain {n}'), findsOneWidget);
  });

  testPage('the edge nodes are rows with their state and a Faults menu', (tester) async {
    await pumpPage(tester, withEdgeNodes: true);
    expect(find.textContaining('Edge1', findRichText: true), findsWidgets);
    await tester.tap(find.byTooltip('Start device').last);
    await tester.pump(Duration(seconds: 1));
    await tester.pump(Duration(milliseconds: 600));
    var run = GetIt.I.get<Simulator>().runner.sparkplugOf(GetIt.I.get<Simulator>().devices.last.id)!;
    expect(run.nodes.every((node) => node.state == EdgeNodeState.online), isTrue);
    expect(find.text('Online'), findsNWidgets(2));
    expect(find.text('bdSeq 0'), findsNWidgets(2));
    expect(find.text('1 of 1 devices online'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Faults').first);
    await tester.pumpAndSettle();
    expect(find.byType(SparkplugFaultMenu), findsOneWidget);
    expect(tester.getSize(find.byType(SparkplugFaultMenu)).width, SparkplugFaultMenu.width);
    await tester.tap(find.text('Devices offline'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(Duration(milliseconds: 100));
    }
    expect(find.byType(SparkplugFaultMenu), findsNothing);
    expect(find.textContaining('0 of 1 devices online'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop all simulated topics'));
    await tester.pump();
    await tester.pump(Duration(seconds: 1));
    expect(run.nodes.every((node) => node.state == EdgeNodeState.stopped), isTrue);
  });
}
