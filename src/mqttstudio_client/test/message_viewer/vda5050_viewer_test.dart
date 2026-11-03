import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/fast_topic_chip.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/message_viewer/widgets/grouped_messages_viewer.dart';
import 'package:mqttstudio/message_viewer/widgets/message_detail_view.dart';
import 'package:mqttstudio/message_viewer/widgets/sequential_messages_viewer.dart';
import 'package:mqttstudio/message_viewer/widgets/tree_messages_viewer.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_writer.dart';
import 'package:mqttstudio/protocol/widgets/fleet_viewer.dart';
import 'package:mqttstudio/protocol/widgets/interpreted_payload_view.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';
import 'package:mqttstudio/protocol/widgets/sparkplug_viewer.dart';

const _state = 'vda5050/v3/Acme/R1/state';

String _stateJson(int id, double charge, {String level = ''}) => jsonEncode(const Vda5050Writer(VdaVersion.v3).toJson(VdaState(
      header: VdaHeader(
          headerId: id, timestamp: DateTime.utc(2026, 10, 26), version: '3.0.0', manufacturer: 'Acme', serialNumber: 'R1'),
      orderId: 'o1',
      lastNodeId: 'N1',
      driving: true,
      operatingMode: VdaOperatingMode.automatic,
      powerSupply: VdaPowerSupply(stateOfCharge: charge),
      position: VdaPosition(x: 1, y: 2, theta: 0, mapId: 'hall'),
      velocity: VdaVelocity(vx: 0.5),
      errors: [if (level.isNotEmpty) VdaError(errorType: 'e1', errorLevel: level)],
    )));

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

  Future<void> pumpViewer(WidgetTester tester, TopicViewMode mode) async {
    await tester.binding.setSurfaceSize(Size(1700, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var project = await openNewProject();
    await adapter.connect(project.mqttSettings);
    await tester.pumpWidget(testApp(ChangeNotifierProvider(
      create: (_) => viewmodel = MessageViewerViewmodel()..topicViewMode = mode,
      child: Consumer<MessageViewerViewmodel>(
        builder: (context, vm, child) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          switch (vm.topicViewMode) {
            TopicViewMode.Tree => TreeMessagesViewer(),
            TopicViewMode.Grouped => GroupedMessagesViewer(),
            TopicViewMode.Sequential => SequentialMessagesViewer(),
            TopicViewMode.Fleet => FleetViewer(),
            TopicViewMode.Sparkplug => SparkplugViewer(),
          },
          if (vm.selectedMessage != null) MessageDetailView(),
        ]),
      ),
    )));
    await tester.pumpAndSettle();
  }

  Future<void> receive(WidgetTester tester, String topic, String payload, int second) async {
    adapter.receive(message(topic, payload, receivedOn: start.add(Duration(seconds: second))));
    viewmodel.delayViewUpdate();
    viewmodel.notifyListeners();
    await tester.pump();
  }

  testWidgets('the sequential viewer shows what a VDA 5050 message says', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpViewer(tester, TopicViewMode.Sequential);
      await receive(tester, _state, _stateJson(1, 80), 0);
      await receive(tester, _state, _stateJson(2, 79, level: VdaErrorLevel.fatal), 1);
      await receive(tester, 'plant/temp', '21', 2);
      expect(find.textContaining('R1 | AUTOMATIC | DRIVING | 80 %'), findsOneWidget);
      expect(find.textContaining('R1 | AUTOMATIC | DRIVING | 79 % | order o1#0 at N1 | 1 error'), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);
    });
  });

  testWidgets('the tree shows the last summary, the grouped chips a marker and a tooltip', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpViewer(tester, TopicViewMode.Tree);
      await receive(tester, _state, _stateJson(1, 80, level: VdaErrorLevel.warning), 0);
      viewmodel.expandAll();
      await tester.pumpAndSettle();
      expect(find.textContaining('80 % | order o1#0 at N1 | 1 error'), findsOneWidget);

      viewmodel.topicViewMode = TopicViewMode.Grouped;
      await tester.pumpAndSettle();
      var chip = tester.widget<FastTopicChip>(find.byType(FastTopicChip));
      expect(chip.marker, isNotNull);
      expect(find.byWidgetPredicate((widget) => widget is Tooltip && (widget.message ?? '').startsWith('R1 |')),
          findsOneWidget);
    });
  });

  testWidgets('the detail view shows the sections, switches to raw and charts a value', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpViewer(tester, TopicViewMode.Sequential);
      for (var i = 0; i < 5; i++) {
        await receive(tester, _state, _stateJson(i, 80.0 - i), i);
      }
      viewmodel.selectedMessage = viewmodel.messageBuffer.getLastMessageForTopic(_state);
      await tester.pumpAndSettle();
      expect(find.byType(InterpretedPayloadView), findsOneWidget);
      expect(find.text('VDA 5050 3.0.0'), findsWidgets);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Operating mode'), findsOneWidget);

      // sections fold
      await tester.tap(find.text('Status'));
      await tester.pumpAndSettle();
      expect(find.text('Operating mode'), findsNothing);

      // the chart shows the first value, state of charge, and offers the others
      expect(viewmodel.selectedChartSeries, 'State of charge %');
      expect(viewmodel.getChartValues().map((value) => value.item1), [76, 77, 78, 79, 80]);
      viewmodel.selectedChartSeries = 'Velocity m/s';
      expect(viewmodel.getChartValues().first.item1, 0.5);

      await tester.tap(find.text('Raw'));
      await tester.pumpAndSettle();
      expect(find.byType(InterpretedPayloadView), findsNothing);
      expect(viewmodel.isRaw(_state), isTrue);
      expect(find.textContaining('R1 | AUTOMATIC'), findsNothing);

      await tester.tap(find.text('VDA 5050 3.0.0'));
      await tester.pumpAndSettle();
      expect(find.byType(InterpretedPayloadView), findsOneWidget);
    });
  });

  test('topics of no protocol are not interpreted', () async {
    await openNewProject();
    var vm = MessageViewerViewmodel();
    adapter.receive(message('plant/temp', '{"headerId":1}', receivedOn: start));
    expect(vm.interpret(vm.messageBuffer.getLastMessageForTopic('plant/temp')!), isNull);
    expect(vm.protocolOf('plant/temp'), isNull);
    vm.dispose();
  });
}
