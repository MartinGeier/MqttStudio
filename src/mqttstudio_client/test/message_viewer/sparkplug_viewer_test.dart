import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/documentation/engine/conformance_checker.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/message_viewer/widgets/message_detail_view.dart';
import 'package:mqttstudio/message_viewer/widgets/sequential_messages_viewer.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_rules.dart';
import 'package:mqttstudio/protocol/widgets/interpreted_payload_view.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:typed_data/typed_buffers.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';

const _birthTopic = 'spBv1.0/Plant1/NBIRTH/Edge1';
const _dataTopic = 'spBv1.0/Plant1/NDATA/Edge1';

Uint8List _birth() => SparkplugWriter.write(
  SpbPayload(
    timestamp: 1761552000000,
    seq: 0,
    metrics: [
      SpbMetric(name: 'bdSeq', datatype: SpbDataType.int64.code, value: 0),
      SpbMetric(
        name: 'Temperature',
        alias: 2,
        datatype: SpbDataType.double.code,
        value: 20.0,
        properties: SpbPropertySet({'engUnit': SpbPropertyValue(type: SpbDataType.string.code, value: '°C')}),
      ),
    ],
  ),
);

Uint8List _data(int seq, double temperature) => SparkplugWriter.write(
  SpbPayload(
    timestamp: 1761552000000 + seq * 1000,
    seq: seq,
    metrics: [SpbMetric(alias: 2, value: temperature, datatype: SpbDataType.double.code)],
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

  testWidgets('the topic viewer interprets Sparkplug B payloads with the names of the birth', (tester) async {
    await ignoringOverflowErrors(() async {
      await tester.binding.setSurfaceSize(Size(1700, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var project = await openNewProject();
      await adapter.connect(project.mqttSettings);
      await tester.pumpWidget(
        testApp(
          ChangeNotifierProvider(
            create: (_) => viewmodel = MessageViewerViewmodel()..topicViewMode = TopicViewMode.Sequential,
            child: Consumer<MessageViewerViewmodel>(
              builder: (context, vm, child) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [SequentialMessagesViewer(), if (vm.selectedMessage != null) MessageDetailView()],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await receive(tester, _birthTopic, _birth(), 0);
      for (var seq = 1; seq <= 3; seq++) {
        await receive(tester, _dataTopic, _data(seq, 20.0 + seq), seq);
      }
      expect(find.textContaining('BIRTH | edge node Edge1 | 2 metrics'), findsOneWidget);
      expect(find.textContaining('Edge1 | Temperature = 23 °C | seq 3'), findsOneWidget);

      viewmodel.selectedMessage = viewmodel.messageBuffer.getLastMessageForTopic(_dataTopic);
      await tester.pumpAndSettle();
      expect(find.byType(InterpretedPayloadView), findsOneWidget);
      expect(find.text('Sparkplug B'), findsOneWidget);
      expect(viewmodel.selectedChartSeries, 'Temperature');
      expect(viewmodel.getChartValues().map((value) => value.item1), [23, 22, 21]);
    });
  });

  test('the documentation check runs the Sparkplug rules on binary payloads', () {
    var checker = ConformanceChecker(TopicDocumentation());
    var at = DateTime.utc(2026, 10, 27, 8);
    void check(String topic, Uint8List payload) =>
        checker.check(RecordedMessage(offsetMicros: 0, topic: topic, payload: payload), at);
    check(_birthTopic, _birth());
    check(_dataTopic, _data(1, 21));
    check(_dataTopic, _data(3, 22));
    // the empty documentation also reports the topics as undocumented
    expect(checker.findings.map((finding) => finding.protocolRule).nonNulls, [SparkplugRules.seqGap]);
  });
}
