import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/simulator/device_edit_dialog.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/simulator.dart';
import 'package:mqttstudio/simulator/simulator_page.dart';
import 'package:mqttstudio/simulator/topic_edit_dialog.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';

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

  Future<Project> pumpPage(WidgetTester tester, {bool connect = true, bool withTopic = true}) async {
    await tester.binding.setSurfaceSize(Size(1600, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var project = await openNewProject();
    if (withTopic) {
      project.simulation.devices.first.topics
          .add(SimulatedTopic(topic: 'sim/counter', generator: const CounterGenerator()));
    }
    if (connect) {
      await adapter.connect(project.mqttSettings);
    }
    await tester.pumpWidget(testApp(SimulatorPage()));
    await tester.pumpAndSettle();
    return project;
  }

  // the test font draws wide squares, so some rows overflow that fit in the app
  void testPage(String description, Future<void> Function(WidgetTester tester) body) =>
      testWidgets(description, (tester) => ignoringOverflowErrors(() => body(tester)));

  testPage('without a project the page shows a watermark', (tester) async {
    await tester.binding.setSurfaceSize(Size(1600, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(testApp(SimulatorPage()));
    await tester.pumpAndSettle();
    expect(find.text('Open a project to simulate'), findsOneWidget);
  });

  testPage('lists devices and topics and starts and stops a topic', (tester) async {
    await pumpPage(tester);
    expect(find.text(SimulatedDevice.defaultName), findsOneWidget);
    expect(find.text('sim/counter'), findsOneWidget);
    expect(find.text('Counter'), findsOneWidget);

    await tester.tap(find.byTooltip('Start all simulated topics'));
    await tester.pump(Duration(seconds: 3));
    await tester.pump(Duration(milliseconds: 600));
    expect(find.byTooltip('Running'), findsOneWidget);
    expect(adapter.published, isNotEmpty);
    expect(find.text('1 of 1 topics running'), findsWidgets);

    await tester.tap(find.byTooltip('Stop all simulated topics'));
    await tester.pump();
    expect(find.byTooltip('Stopped'), findsOneWidget);
    // lets the statistics timer run out
    await tester.pump(Duration(seconds: 1));
  });

  testPage('start buttons are disabled while disconnected', (tester) async {
    await pumpPage(tester, connect: false);
    var start = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.play_arrow).first);
    expect(start.onPressed, isNull);
  });

  testPage('a disconnect stops the simulation and shows a snackbar', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byTooltip('Start all simulated topics'));
    await tester.pump(Duration(seconds: 2));
    adapter.dropConnection();
    await tester.pump();
    expect(find.text('Simulation stopped: disconnected from MQTT broker'), findsOneWidget);
    await tester.pump(Duration(seconds: 11));
  });

  testPage('the topic dialog edits the topic on two tabs', (tester) async {
    var project = await pumpPage(tester);
    await tester.tap(find.byTooltip('Edit topic'));
    await tester.pumpAndSettle();
    expect(find.byType(TopicEditDialog), findsOneWidget);
    expect(find.text('PAYLOAD'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Topic'), 'sim/edited');
    await tester.tap(find.text('MQTT'));
    await tester.pumpAndSettle();
    expect(find.text('User properties'), findsOneWidget);

    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(find.byType(TopicEditDialog), findsNothing);
    expect(project.simulation.devices.first.topics.single.topic, 'sim/edited');
    expect(find.text('sim/edited'), findsOneWidget);
  });

  testPage('adding a device opens the device dialog', (tester) async {
    var project = await pumpPage(tester, withTopic: false);
    await tester.tap(find.text('ADD DEVICE'));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceEditDialog), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Instances'), '5');
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(project.simulation.devices.length, 2);
    expect(project.simulation.devices.last.instanceCount, 5);
    expect(find.text('5 instances · {n} = 1–5'), findsOneWidget);
  });

  testPage('a new topic can be added to the selected device', (tester) async {
    var project = await pumpPage(tester, withTopic: false);
    await tester.tap(find.text('ADD TOPIC'));
    await tester.pumpAndSettle();
    expect(find.text('Add topic'), findsOneWidget);
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(project.simulation.devices.first.topics.single.generator, isA<RandomWalkGenerator>());
  });
}
