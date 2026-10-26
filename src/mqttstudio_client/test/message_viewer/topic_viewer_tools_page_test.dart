import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/fast_topic_chip.dart';
import 'package:mqttstudio/message_viewer/compare_messages_dialog.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/message_viewer/publish_topic_dialog.dart';
import 'package:mqttstudio/message_viewer/retained_messages_dialog.dart';
import 'package:mqttstudio/message_viewer/widgets/message_detail_view.dart';
import 'package:mqttstudio/message_viewer/widgets/sequential_messages_viewer.dart';
import 'package:mqttstudio/message_viewer/widgets/topics_viewer_command_bar.dart';
import 'package:mqttstudio/message_viewer/widgets/tree_messages_viewer.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/mqtt/broker_stats_dialog.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';

void main() {
  late FakeMqttAdapter adapter;
  late Project project;
  late MessageViewerViewmodel viewmodel;
  var start = DateTime(2026, 10, 25, 12);

  setUpAll(loadTranslations);

  setUp(() {
    adapter = setUpServices();
    GetIt.I.registerSingleton(SrxNavigationService(Container(), Container()));
  });

  tearDown(tearDownServices);

  // the topic viewer as message_viewer_page.dart lays it out, without app bar and subscriptions
  Future<void> pumpViewer(WidgetTester tester, {TopicViewMode mode = TopicViewMode.Sequential}) async {
    await tester.binding.setSurfaceSize(Size(1700, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    project = await openNewProject();
    await adapter.connect(project.mqttSettings);
    await tester.pumpWidget(testApp(ChangeNotifierProvider(
      create: (_) => viewmodel = MessageViewerViewmodel()..topicViewMode = mode,
      child: Consumer<MessageViewerViewmodel>(
        builder: (context, vm, child) => Column(children: [
          TopicsViewCommandBar(),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              vm.topicViewMode == TopicViewMode.Tree ? TreeMessagesViewer() : SequentialMessagesViewer(),
              if (vm.selectedMessage != null) MessageDetailView(),
            ]),
          ),
        ]),
      ),
    )));
    await tester.pumpAndSettle();
  }

  // lets the viewers refresh, they update at most every 500 ms
  Future<void> receive(WidgetTester tester, String topic, String payload, int second, {bool retain = false}) async {
    adapter.receive(message(topic, payload, receivedOn: start.add(Duration(seconds: second)), retain: retain));
    viewmodel.delayViewUpdate();
    viewmodel.notifyListeners();
    await tester.pump();
  }

  Future<void> select(WidgetTester tester, String topic) async {
    viewmodel.selectedMessage = viewmodel.messageBuffer.getLastMessageForTopic(topic);
    await tester.pumpAndSettle();
  }

  Future<void> chooseInDropDown(WidgetTester tester, String current, String choice) async {
    await tester.tap(find.text(current).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(choice).last);
    await tester.pumpAndSettle();
  }

  group('topic viewer filter', () {
    testWidgets('filters by a condition and reports an invalid one', (tester) async {
      await ignoringOverflowErrors(() async {
        await pumpViewer(tester);
        await receive(tester, 'plant/a', '{"temp": 90}', 0);
        await receive(tester, 'plant/b', '{"temp": 20}', 1);
        expect(find.byType(FastTopicChip), findsNWidgets(2));

        await chooseInDropDown(tester, 'Topic', 'Condition');
        await tester.enterText(find.byType(TextField), r'$.temp >');
        await tester.pump(Duration(milliseconds: 400));
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(find.byType(FastTopicChip), findsNWidgets(2));

        await tester.enterText(find.byType(TextField), r'$.temp > 80');
        await tester.pump(Duration(milliseconds: 400));
        expect(find.byIcon(Icons.error_outline), findsNothing);
        expect(find.byType(FastTopicChip), findsOneWidget);
      });
    });
  });

  group('message detail view', () {
    testWidgets('highlights what changed since the previous message', (tester) async {
      await ignoringOverflowErrors(() async {
        await pumpViewer(tester);
        await receive(tester, 'plant/a', '{"temp": 80, "state": "ok"}', 0);
        await receive(tester, 'plant/a', '{"temp": 81, "state": "ok"}', 1);
        await select(tester, 'plant/a');

        await tester.tap(find.byIcon(Icons.difference_outlined));
        await tester.pumpAndSettle();

        expect(find.text('1 change since the previous message (1.00 s earlier)'), findsOneWidget);
        expect(find.textContaining('was 80', findRichText: true), findsOneWidget);
      });
    });

    testWidgets('decodes the payload with the chosen decoder', (tester) async {
      await ignoringOverflowErrors(() async {
        await pumpViewer(tester);
        await receive(tester, 'plant/a', 'hello', 0);
        await select(tester, 'plant/a');

        await chooseInDropDown(tester, 'Auto', 'Hex');

        expect(find.textContaining(RegExp(r'68 65 6c 6c  6f +\|hello\|')), findsOneWidget);
        expect(viewmodel.decoderOf('plant/a').name, 'hex');
      });
    });

    testWidgets('compares the marked message with the selected one', (tester) async {
      await ignoringOverflowErrors(() async {
        await pumpViewer(tester);
        await receive(tester, 'plant/a', '{"temp": 80}', 0);
        await receive(tester, 'plant/b', '{"temp": 85, "new": 1}', 1);
        await select(tester, 'plant/a');
        await tester.tap(find.byIcon(Icons.push_pin_outlined));
        await tester.pumpAndSettle();
        await select(tester, 'plant/b');

        await tester.tap(find.byIcon(Icons.compare_arrows));
        await tester.pumpAndSettle();

        expect(find.byType(CompareMessagesDialog), findsOneWidget);
        expect(find.text('2 changes'), findsOneWidget);
        expect(find.text(r'~ $.temp: 80 → 85'), findsOneWidget);
      });
    });

    testWidgets('opens the publish dialog with the message to change it', (tester) async {
      await ignoringOverflowErrors(() async {
        await pumpViewer(tester);
        await receive(tester, 'plant/a', '{"on": true}', 0);
        await select(tester, 'plant/a');

        await tester.tap(find.byIcon(Icons.edit_note));
        await tester.pumpAndSettle();
        expect(find.byType(PublishTopicDialog), findsOneWidget);
        await tester.enterText(find.widgetWithText(TextField, '{"on": true}'), '{"on": false}');
        await tester.tap(find.descendant(of: find.byType(PublishTopicDialog), matching: find.text('PUBLISH')));
        await tester.pumpAndSettle();

        expect(adapter.published.single.topic, 'plant/a');
        expect(adapter.published.single.payload, '{"on": false}');
      });
    });
  });

  group('tree viewer', () {
    testWidgets('shows statistics and subscribes to a branch from the context menu', (tester) async {
      await ignoringOverflowErrors(() async {
        await pumpViewer(tester, mode: TopicViewMode.Tree);
        await receive(tester, 'plant/line1/temp', '20', 0);
        await receive(tester, 'plant/line1/temp', '21', 1);
        await tester.pump(Duration(seconds: 1));
        expect(find.textContaining('msg/s'), findsOneWidget);

        await tester.tap(find.text('line1'), buttons: kSecondaryButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Subscribe to plant/line1/#'));
        await tester.pumpAndSettle();

        expect(project.topicSubscriptions.single.topic, 'plant/line1/#');
        expect(adapter.subscribed, ['plant/line1/#']);
      });
    });
  });

  group('retained messages dialog', () {
    testWidgets('scans when it opens and clears the selected messages', (tester) async {
      await ignoringOverflowErrors(() async {
        await tester.binding.setSurfaceSize(Size(1400, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        project = await openNewProject();
        FakeMqttAdapter? side;
        await tester.pumpWidget(testApp(
            DialogHost(RetainedMessagesDialog(filter: 'plant/#', connectionFactory: () => side = FakeMqttAdapter()))));
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump();

        side!.receive(message('plant/a', '1', retain: true));
        side!.receive(message('plant/b', '{"x": 2}', retain: true));
        await tester.pump(Duration(seconds: 1));
        expect(find.text('2 retained messages in plant/#.'), findsOneWidget);
        expect(find.text('plant/b'), findsOneWidget);

        await tester.tap(find.text('CLEAR 2'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Yes'));
        await tester.pumpAndSettle();

        expect(side!.published.map((p) => p.topic), ['plant/a', 'plant/b']);
        expect(find.text('plant/b'), findsNothing);
        await tester.tap(find.text('CLOSE'));
        await tester.pumpAndSettle();
        expect(side!.disconnectCount, 1);
      });
    });
  });

  group('broker statistics dialog', () {
    testWidgets('shows the summary and all \$SYS topics', (tester) async {
      await ignoringOverflowErrors(() async {
        await tester.binding.setSurfaceSize(Size(1400, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        project = await openNewProject();
        FakeMqttAdapter? side;
        await tester.pumpWidget(testApp(DialogHost(BrokerStatsDialog(connectionFactory: () => side = FakeMqttAdapter()))));
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump();

        side!.receive(message(r'$SYS/broker/version', 'mosquitto version 2.0.18'));
        side!.receive(message(r'$SYS/broker/load/messages/received/1min', '120.5'));
        await tester.pump(Duration(seconds: 1));

        expect(find.text('Version'), findsOneWidget);
        expect(find.text('120.5 per minute'), findsOneWidget);
        expect(find.text(r'All $SYS topics (2)'), findsOneWidget);
        await tester.tap(find.text('Ok'));
        await tester.pumpAndSettle();
        expect(side!.disconnectCount, 1);
      });
    });
  });
}
