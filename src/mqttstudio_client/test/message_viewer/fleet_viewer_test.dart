import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/message_viewer/widgets/message_detail_view.dart';
import 'package:mqttstudio/message_viewer/widgets/sequential_messages_viewer.dart';
import 'package:mqttstudio/message_viewer/widgets/topics_viewer_command_bar.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_writer.dart';
import 'package:mqttstudio/protocol/widgets/fleet_canvas.dart';
import 'package:mqttstudio/protocol/widgets/fleet_viewer.dart';
import 'package:mqttstudio/protocol/widgets/interpreted_payload_view.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';

void main() {
  late FakeMqttAdapter adapter;
  late MessageViewerViewmodel viewmodel;
  var start = DateTime(2026, 10, 26, 12);

  setUpAll(loadTranslations);

  setUp(() {
    adapter = setUpServices();
    GetIt.I.registerSingleton(SrxNavigationService(Container(), Container()));
  });

  tearDown(tearDownServices);

  // the topic viewer as message_viewer_page.dart lays it out, without app bar and subscriptions
  Future<void> pumpViewer(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(Size(1700, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var project = await openNewProject();
    await adapter.connect(project.mqttSettings);
    await tester.pumpWidget(
      testApp(
        ChangeNotifierProvider(
          create: (_) => viewmodel = MessageViewerViewmodel()..topicViewMode = TopicViewMode.Sequential,
          child: Consumer<MessageViewerViewmodel>(
            builder: (context, vm, child) => Column(
              children: [
                TopicsViewCommandBar(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      vm.topicViewMode == TopicViewMode.Fleet ? FleetViewer() : SequentialMessagesViewer(),
                      if (vm.selectedMessage != null) MessageDetailView(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> receive(
    WidgetTester tester,
    String serial,
    VdaMessage vda, {
    int second = 0,
    String major = 'v3',
  }) async {
    var version = major == 'v3' ? VdaVersion.v3 : VdaVersion.v2;
    var payload = jsonEncode(Vda5050Writer(version).toJson(vda));
    adapter.receive(
      message('uagv/$major/Acme/$serial/${vda.topic}', payload, receivedOn: start.add(Duration(seconds: second))),
    );
    viewmodel.delayViewUpdate();
    viewmodel.notifyListeners();
    await tester.pump();
  }

  VdaHeader header(String serial, {String version = '3.0.0'}) =>
      VdaHeader(headerId: 1, timestamp: start, version: version, manufacturer: 'Acme', serialNumber: serial);

  VdaState state(String serial, {double x = 0, String mapId = 'hall', bool driving = true, String version = '3.0.0'}) =>
      VdaState(
        header: header(serial, version: version),
        orderId: 'o1',
        lastNodeId: 'N1',
        driving: driving,
        position: VdaPosition(x: x, y: 0, theta: 0, mapId: mapId),
        powerSupply: VdaPowerSupply(stateOfCharge: 64),
      );

  Future<void> tapFleetButton(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.precision_manufacturing));
    await tester.pumpAndSettle();
  }

  testWidgets('the Fleet mode is offered once a robot was received', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpViewer(tester);
      await tapFleetButton(tester);
      expect(viewmodel.topicViewMode, TopicViewMode.Sequential);

      adapter.receive(message('plant/temp', '21', receivedOn: start));
      expect(viewmodel.canShowFleet, isFalse);
      await receive(tester, 'R1', state('R1'));
      expect(viewmodel.canShowFleet, isTrue);
      await tapFleetButton(tester);
      expect(viewmodel.topicViewMode, TopicViewMode.Fleet);
      expect(find.byType(FleetViewer), findsOneWidget);
    });
  });

  testWidgets('the table lists the robots, a row selects the robot\'s state', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpViewer(tester);
      await receive(tester, 'R1', state('R1'));
      await receive(tester, 'R2', state('R2', x: 5, driving: false, version: '2.1.0'), major: 'v2', second: 1);
      await receive(
        tester,
        'R2',
        VdaConnection(
          header: header('R2', version: '2.1.0'),
          connectionState: VdaConnectionState.online,
        ),
        major: 'v2',
        second: 2,
      );
      await tapFleetButton(tester);

      // robots of one manufacturer show their serial numbers, the full name is the tooltip
      expect(find.text('R1'), findsOneWidget);
      expect(find.byTooltip('Acme R1'), findsOneWidget);
      expect(find.text('R2'), findsOneWidget);
      expect(find.text('2.1.0'), findsOneWidget);
      expect(find.byTooltip('ONLINE'), findsOneWidget);
      expect(find.byTooltip('No connection message received'), findsOneWidget);
      expect(find.text('64 %'), findsNWidgets(2));
      expect(find.text('o1#0 · N1'), findsNWidgets(2));
      expect(find.descendant(of: find.byType(FleetViewer), matching: find.byIcon(Icons.play_arrow)), findsOneWidget);
      expect(find.descendant(of: find.byType(FleetViewer), matching: find.byIcon(Icons.stop)), findsOneWidget);

      // the table is sorted by robot, a tap on the header turns it around
      await tester.tap(find.text('Robot'));
      await tester.pumpAndSettle();
      expect(viewmodel.sortedVehicles.map((vehicle) => vehicle.serialNumber), ['R2', 'R1']);

      await tester.tap(find.text('R2'));
      await tester.pumpAndSettle();
      expect(viewmodel.selectedMessage!.topicName, 'uagv/v2/Acme/R2/state');
      expect(viewmodel.selectedRobot, 'uagv/v2/Acme/R2');
      expect(find.byType(InterpretedPayloadView), findsOneWidget);
    });
  });

  testWidgets('the map shows one map at a time, a robot on it is selected by a click', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpViewer(tester);
      await receive(tester, 'R1', state('R1'));
      await receive(tester, 'R2', state('R2', x: 5));
      await receive(tester, 'R3', state('R3', x: 40, mapId: 'dock'));
      await tapFleetButton(tester);

      // the map with the most robots first, zones can't be shown without zones
      expect(viewmodel.fleetMap, 'hall');
      var zones = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(zones.onChanged, isNull);
      expect(zones.value, isFalse);
      // disabled controls say why
      expect(find.byTooltip('The map to show'), findsOneWidget);
      expect(
        find.byWidgetPredicate((widget) => widget is Tooltip && (widget.message ?? '').startsWith('No zone set')),
        findsOneWidget,
      );

      // the legend can be hidden
      expect(find.byType(FleetLegend), findsOneWidget);
      expect(find.text('Where it drove'), findsOneWidget);
      await tester.tap(find.byTooltip('Hide the legend'));
      await tester.pumpAndSettle();
      expect(find.byType(FleetLegend), findsNothing);

      viewmodel.fleetMap = 'dock';
      await tester.pumpAndSettle();
      // a single robot sits in the middle of the fitted map
      await tester.tapAt(tester.getCenter(find.byWidgetPredicate((widget) => widget is FleetCanvas)));
      await tester.pumpAndSettle();
      expect(viewmodel.selectedRobot, 'uagv/v3/Acme/R3');
      // the selected robot's map stays shown
      expect(viewmodel.fleetMap, 'dock');
    });
  });

  testWidgets('clearing the messages empties the fleet', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpViewer(tester);
      await receive(tester, 'R1', state('R1'));
      await tapFleetButton(tester);
      viewmodel.clearMessages();
      await tester.pumpAndSettle();
      expect(find.text('No VDA 5050 robots received'), findsOneWidget);
      expect(viewmodel.canShowFleet, isFalse);
    });
  });
}
