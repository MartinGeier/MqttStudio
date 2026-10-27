import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/message_viewer/widgets/message_detail_view.dart';
import 'package:mqttstudio/message_viewer/widgets/sequential_messages_viewer.dart';
import 'package:mqttstudio/message_viewer/widgets/topics_viewer_command_bar.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/protocol/widgets/sparkplug_viewer.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:typed_data/typed_buffers.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';

Uint8List _payload(int? seq, List<SpbMetric> metrics) =>
    SparkplugWriter.write(SpbPayload(timestamp: 1761566400000, seq: seq, metrics: metrics));

SpbMetric _defined(String name, int alias, SpbDataType type, Object value, {String? unit}) => SpbMetric(
  name: name,
  alias: alias,
  datatype: type.code,
  value: value,
  properties: unit == null
      ? null
      : SpbPropertySet({'engUnit': SpbPropertyValue(type: SpbDataType.string.code, value: unit)}),
);

void main() {
  late FakeMqttAdapter adapter;
  late MessageViewerViewmodel viewmodel;
  var start = DateTime(2026, 10, 27, 12);

  setUpAll(loadTranslations);

  setUp(() {
    adapter = setUpServices();
    GetIt.I.registerSingleton(SrxNavigationService(Container(), Container()));
  });

  tearDown(tearDownServices);

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
                      vm.topicViewMode == TopicViewMode.Sparkplug ? SparkplugViewer() : SequentialMessagesViewer(),
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

  Future<void> receive(WidgetTester tester, String topic, Uint8List payload, int second) async {
    adapter.receive(
      ReceivedMqttMessage(
        1,
        topic,
        Uint8Buffer()..addAll(payload),
        MqttQos.atMostOnce,
        start.add(Duration(seconds: second)),
        false,
      ),
    );
    viewmodel.delayViewUpdate();
    viewmodel.notifyListeners();
    await tester.pump();
  }

  Future<void> receivePlant(WidgetTester tester) async {
    await receive(
      tester,
      'spBv1.0/Plant1/NBIRTH/Edge1',
      _payload(0, [
        SpbMetric(name: 'bdSeq', datatype: SpbDataType.int64.code, value: 2),
        _defined('Firmware', 1, SpbDataType.string, '3.2.1'),
      ]),
      0,
    );
    await receive(
      tester,
      'spBv1.0/Plant1/DBIRTH/Edge1/Pump',
      _payload(1, [
        _defined('Temperature', 10, SpbDataType.double, 60.0, unit: '°C'),
        _defined('Motor/Speed', 11, SpbDataType.int32, 1450, unit: 'rpm'),
        _defined('Mode', 12, SpbDataType.string, 'AUTO'),
      ]),
      1,
    );
    for (var i = 0; i < 3; i++) {
      await receive(
        tester,
        'spBv1.0/Plant1/DDATA/Edge1/Pump',
        _payload(2 + i, [SpbMetric(alias: 10, value: 61.0 + i, encodeAs: SpbDataType.double)]),
        2 + i,
      );
    }
    await receive(
      tester,
      'spBv1.0/Plant1/NDATA/Edge2',
      _payload(9, [SpbMetric(alias: 4, value: 1.5, encodeAs: SpbDataType.double)]),
      6,
    );
  }

  Future<void> openView(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.hub));
    await tester.pumpAndSettle();
  }

  testWidgets('the Sparkplug mode is offered once a Sparkplug message was received', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpViewer(tester);
      await openView(tester);
      expect(viewmodel.topicViewMode, TopicViewMode.Sequential);
      await receivePlant(tester);
      expect(viewmodel.canShowSparkplug, isTrue);
      await openView(tester);
      expect(find.byType(SparkplugViewer), findsOneWidget);
    });
  });

  testWidgets('the tree shows edge nodes and devices, the table the current values', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpViewer(tester);
      await receivePlant(tester);
      await openView(tester);

      // the first edge node is selected
      expect(find.text('Edge1'), findsWidgets);
      expect(find.text('bdSeq 2  seq 4'), findsOneWidget);
      expect(find.text('Firmware'), findsOneWidget);
      expect(find.text('no birth seen'), findsOneWidget);

      await tester.tap(find.text('Pump'));
      await tester.pumpAndSettle();
      expect(find.text('63 °C'), findsOneWidget);
      expect(find.text('1450 rpm'), findsOneWidget);
      expect(find.textContaining('device of Edge1 in Plant1', findRichText: true), findsOneWidget);
      // the header's buttons sit at the right edge of the view
      var viewRight = tester.getTopRight(find.byType(SparkplugViewer)).dx;
      expect(tester.getTopRight(find.byTooltip('Show the last message')).dx, closeTo(viewRight - 12, 1));

      // by changes, the stuck metrics first
      await tester.tap(find.text('Changes'));
      await tester.pumpAndSettle();
      expect(viewmodel.metricsOf(viewmodel.selectedSparkplugEntry!).map((metric) => metric.name), [
        'Mode',
        'Motor/Speed',
        'Temperature',
      ]);

      await tester.enterText(
        find.descendant(of: find.byType(SparkplugViewer), matching: find.byType(TextField)),
        'temp',
      );
      await tester.pumpAndSettle();
      expect(find.text('1450 rpm'), findsNothing);

      // a metric shows its last message and its chart
      await tester.tap(find.text('63 °C'));
      await tester.pumpAndSettle();
      expect(viewmodel.selectedMessage!.topicName, 'spBv1.0/Plant1/DDATA/Edge1/Pump');
      expect(viewmodel.selectedChartSeries, 'Temperature');
      expect(viewmodel.getChartValues().map((value) => value.item1), [63, 62, 61]);
      expect(find.byType(MessageDetailView), findsOneWidget);
    });
  });

  testWidgets('an edge node without birth offers the rebirth request', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpViewer(tester);
      await receivePlant(tester);
      await openView(tester);
      await tester.tap(find.text('Edge2'));
      await tester.pumpAndSettle();
      expect(find.text('alias 4'), findsOneWidget);
      expect(find.text('No birth received: some metrics are shown by alias'), findsOneWidget);

      viewmodel.confirmRebirth = false;
      await tester.tap(find.text('Request rebirth'));
      await tester.pumpAndSettle();
      expect(adapter.published.map((message) => message.topic), contains('spBv1.0/Plant1/NCMD/Edge2'));
      expect(find.textContaining('Rebirth requested at'), findsOneWidget);
    });
  });

  testWidgets('clearing the messages empties the view', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpViewer(tester);
      await receivePlant(tester);
      await openView(tester);
      viewmodel.clearMessages();
      await tester.pumpAndSettle();
      expect(find.text('No Sparkplug B messages received'), findsOneWidget);
      expect(viewmodel.canShowSparkplug, isFalse);
    });
  });
}
