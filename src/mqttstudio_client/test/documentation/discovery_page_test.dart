import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/discovery_service.dart';
import 'package:mqttstudio/documentation/documentation_page.dart';
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/mqtt/side_connection.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:typed_data/typed_buffers.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';

class _FailingAdapter extends FakeMqttAdapter {
  bool fail = false;

  @override
  Future connect(settings) async {
    if (fail) {
      throw StateError('broker unreachable');
    }
    await super.connect(settings);
  }
}

void main() {
  group('SideConnection', () {
    testWidgets('reconnects after a lost connection and subscribes again', (tester) async {
      var adapter = _FailingAdapter();
      var connection = SideConnection(() => adapter);
      var subscribed = 0;
      var events = <String>[];
      connection.lostEvent.subscribe((_) => events.add('lost'));
      connection.reconnectedEvent.subscribe((_) => events.add('reconnected'));
      await connection.connect(createProject().mqttSettings);
      connection.listen((_) => subscribed++);
      expect(subscribed, 1);

      adapter.fail = true;
      adapter.disconnect();
      expect(connection.isReconnecting, isTrue);
      await tester.pump(Duration(seconds: 1));
      expect(connection.reconnectAttempt, 2);
      adapter.fail = false;
      await tester.pump(Duration(seconds: 2));
      expect(events, ['lost', 'reconnected']);
      expect(subscribed, 2);
      expect(connection.isReconnecting, isFalse);
      connection.close();
      expect(adapter.connected, isFalse);
    });

    test('client ids get the tag and a suffix', () {
      var settings = SideConnection.settingsFor(createProject().mqttSettings, 'doc');
      expect(settings.clientId, matches(RegExp(r'^client-1-doc-[0-9a-f]{4}$')));
      expect(settings.cleanStart, isTrue);
    });
  });

  group('discovery in the documentation tab', () {
    late List<FakeMqttAdapter> connections;

    setUpAll(loadTranslations);

    setUp(() {
      setUpServices();
      GetIt.I.registerSingleton(SrxNavigationService(Container(), Container()));
      GetIt.I.get<DiscoveryService>().dispose();
      GetIt.I.unregister<DiscoveryService>();
      connections = [];
      GetIt.I.registerSingleton(DiscoveryService(connectionFactory: () {
        var connection = FakeMqttAdapter();
        connections.add(connection);
        return connection;
      }));
    });

    tearDown(() async {
      GetIt.I.get<DiscoveryService>().dispose();
      await tearDownServices();
    });

    ReceivedMqttMessage received(String topic, String payload) => ReceivedMqttMessage(
        1, topic, Uint8Buffer()..addAll(utf8.encode(payload)), MqttQos.atLeastOnce, DateTime.now(), false);

    testWidgets('discovers live topics, reviews them and shows what was observed', (tester) async {
      await ignoringOverflowErrors(() async {
        await tester.binding.setSurfaceSize(Size(1600, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var project = await openNewProject();
        project.mqttSettings.protocolVersion = MqttProtocolVersion.v5;
        await tester.pumpWidget(testApp(DocumentationPage()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('DISCOVER'));
        await tester.pumpAndSettle();
        expect(find.text('Discover Topics'), findsOneWidget);
        // no filter by default: # on a busy broker would flood the app
        var dialog = find.byType(SimpleDialog);
        var filter = find.descendant(of: dialog, matching: find.byType(TextField)).first;
        expect(tester.widget<TextField>(filter).controller!.text, isEmpty);
        await tester.tap(find.descendant(of: dialog, matching: find.text('DISCOVER')));
        await tester.pumpAndSettle();
        expect(dialog, findsOneWidget);
        expect(connections, isEmpty);
        await tester.enterText(filter, 'plant/#');
        await tester.tap(find.descendant(of: dialog, matching: find.text('DISCOVER')));
        await tester.pumpAndSettle();

        var connection = connections.single;
        for (var i = 0; i < 3; i++) {
          connection.messageReceivedEvent.broadcast(received('plant/m$i/temp', '${20 + i}'));
        }
        await tester.pump(Duration(seconds: 1));
        expect(find.textContaining('DISCOVERING'), findsOneWidget);
        expect(find.textContaining('3 topics, 3 new'), findsOneWidget);

        await tester.tap(find.byTooltip('Stop the discovery and review what it found'));
        await tester.pumpAndSettle();
        expect(find.text('Review Discovery'), findsOneWidget);
        expect(find.text('plant/m{id}/temp'), findsWidgets);
        await tester.tap(find.text('APPLY'));
        await tester.pumpAndSettle();

        var node = GetIt.I.get<DocumentationService>().nodeAt('plant/m{id}/temp')!;
        expect(node.review, DocReviewState.added);
        expect(node.observed!.instanceCount, 3);
        expect(find.text('New'), findsWidgets);
        expect(GetIt.I.get<ProjectManager>().hasProjectChanged(), isTrue);

        await tester.tap(find.text('temp'));
        await tester.pumpAndSettle();
        expect(find.text('Observed'), findsOneWidget);
        expect(node.review, DocReviewState.none);
        expect(find.text('Observed: Number'), findsOneWidget);
      });
    });

    testWidgets('the discover dialog keeps its height on every source', (tester) async {
      await ignoringOverflowErrors(() async {
        await tester.binding.setSurfaceSize(Size(1600, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await openNewProject();
        await tester.pumpWidget(testApp(DocumentationPage()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('DISCOVER'));
        await tester.pumpAndSettle();

        var dialog = find.byType(SimpleDialog);
        var heights = [tester.getSize(dialog).height];
        for (var source in ['RECORDING', 'TOPIC VIEWER', 'LIVE BROKER']) {
          await tester.tap(find.text(source));
          await tester.pumpAndSettle();
          heights.add(tester.getSize(dialog).height);
        }
        expect(heights.toSet(), hasLength(1));

        // the stop settings only apply to a live discovery
        await tester.tap(find.text('TOPIC VIEWER'));
        await tester.pumpAndSettle();
        expect(find.text('Stop after'), findsOneWidget);
        var stop = tester.widget<DropdownButton<DiscoveryStop>>(find.byType(DropdownButton<DiscoveryStop>));
        expect(stop.onChanged, isNull);
      });
    });

    testWidgets('a broker that can not be reached shows an error', (tester) async {
      await ignoringOverflowErrors(() async {
        GetIt.I.get<DiscoveryService>().dispose();
        GetIt.I.unregister<DiscoveryService>();
        GetIt.I.registerSingleton(DiscoveryService(connectionFactory: () => _FailingAdapter()..fail = true));
        await tester.binding.setSurfaceSize(Size(1600, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await openNewProject();
        await tester.pumpWidget(testApp(DocumentationPage()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('DISCOVER'));
        await tester.pumpAndSettle();
        var dialog = find.byType(SimpleDialog);
        await tester.enterText(find.descendant(of: dialog, matching: find.byType(TextField)).first, '#');
        await tester.tap(find.descendant(of: dialog, matching: find.text('DISCOVER')));
        await tester.pumpAndSettle();
        expect(find.text('Cannot start the discovery'), findsOneWidget);
        expect(GetIt.I.get<DiscoveryService>().isRunning, isFalse);
      });
    });
  });
}
