import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/message_viewer/widgets/message_detail_view.dart';
import 'package:mqttstudio/message_viewer/widgets/sequential_messages_viewer.dart';
import 'package:mqttstudio/message_viewer/widgets/tree_messages_viewer.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:typed_data/typed_buffers.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';

Uint8List _data(int seq) => SparkplugWriter.write(
  SpbPayload(
    timestamp: 1761552000000,
    seq: seq,
    metrics: [SpbMetric(alias: 2, value: 21.5, encodeAs: SpbDataType.double)],
  ),
);

Uint8List _birth() => SparkplugWriter.write(
  SpbPayload(
    timestamp: 1761552000000,
    seq: 0,
    metrics: [
      SpbMetric(name: 'bdSeq', datatype: SpbDataType.int64.code, value: 0),
      SpbMetric(name: 'Temperature', alias: 2, datatype: SpbDataType.double.code, value: 20.0),
    ],
  ),
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

  Future<void> pumpViewer(WidgetTester tester, TopicViewMode mode) async {
    await tester.binding.setSurfaceSize(Size(1700, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var project = await openNewProject();
    await adapter.connect(project.mqttSettings);
    await tester.pumpWidget(
      testApp(
        ChangeNotifierProvider(
          create: (_) => viewmodel = MessageViewerViewmodel()..topicViewMode = mode,
          child: Consumer<MessageViewerViewmodel>(
            builder: (context, vm, child) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                vm.topicViewMode == TopicViewMode.Tree ? TreeMessagesViewer() : SequentialMessagesViewer(),
                if (vm.selectedMessage != null) MessageDetailView(),
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

  List<String> rebirthsSent() => [
    for (var message in adapter.published)
      if (message.topic.contains('/NCMD/')) message.topic,
  ];

  testWidgets('the missing-birth warning offers the request, asked once per session', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpViewer(tester, TopicViewMode.Sequential);
      await receive(tester, 'spBv1.0/Plant1/NDATA/Edge1', _data(5), 0);
      viewmodel.selectedMessage = viewmodel.messageBuffer.getLastMessageForTopic('spBv1.0/Plant1/NDATA/Edge1');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Request rebirth'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Edge node Edge1 in group Plant1 publishes'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(rebirthsSent(), ['spBv1.0/Plant1/NCMD/Edge1']);
      var sent = adapter.published.last;
      expect(sent.qos, MqttQos.atMostOnce);
      expect(sent.retain, isFalse);
      expect(SparkplugReader.read(Uint8List.fromList(sent.payload as List<int>)).metrics.single.value, true);
      expect(find.text('Rebirth requested from Edge1'), findsOneWidget);
      expect(find.textContaining('Rebirth requested at'), findsOneWidget);
      expect(viewmodel.confirmRebirth, isFalse);

      // the toolbar's button asks no more in this session
      await tester.tap(find.byTooltip('Request rebirth of Edge1: it publishes its births again'));
      await tester.pumpAndSettle();
      expect(rebirthsSent(), hasLength(2));

      // the birth arrives: the warning is gone
      await receive(tester, 'spBv1.0/Plant1/NBIRTH/Edge1', _birth(), 1);
      await receive(tester, 'spBv1.0/Plant1/NDATA/Edge1', _data(1), 2);
      viewmodel.selectedMessage = viewmodel.messageBuffer.getLastMessageForTopic('spBv1.0/Plant1/NDATA/Edge1');
      await tester.pumpAndSettle();
      expect(find.text('Request rebirth'), findsNothing);
      expect(find.textContaining('Rebirth requested at'), findsNothing);
    });
  });

  testWidgets('saying no sends nothing, and without a connection the request is disabled', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpViewer(tester, TopicViewMode.Sequential);
      await receive(tester, 'spBv1.0/Plant1/NDATA/Edge1', _data(5), 0);
      viewmodel.selectedMessage = viewmodel.messageBuffer.getLastMessageForTopic('spBv1.0/Plant1/NDATA/Edge1');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request rebirth'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(rebirthsSent(), isEmpty);
      expect(viewmodel.confirmRebirth, isTrue);

      adapter.dropConnection();
      viewmodel.notifyListeners();
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Request rebirth')).onPressed, isNull);
    });
  });

  testWidgets('the tree asks all edge nodes of a group', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpViewer(tester, TopicViewMode.Tree);
      await receive(tester, 'spBv1.0/Plant1/NDATA/Edge1', _data(5), 0);
      await receive(tester, 'spBv1.0/Plant1/NDATA/Edge2', _data(9), 1);
      await receive(tester, 'spBv1.0/Plant2/NDATA/Edge7', _data(3), 2);
      viewmodel.expandAll();
      await tester.pumpAndSettle();
      viewmodel.confirmRebirth = false;

      await tester.tap(find.text('Plant1'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request rebirth of all 2 edge nodes'));
      await tester.pumpAndSettle();
      expect(rebirthsSent(), ['spBv1.0/Plant1/NCMD/Edge1', 'spBv1.0/Plant1/NCMD/Edge2']);

      // the group branch of a single edge node names it
      await tester.tap(find.text('Plant2'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request rebirth of Edge7'));
      await tester.pumpAndSettle();
      expect(rebirthsSent().last, 'spBv1.0/Plant2/NCMD/Edge7');
    });
  });
}
