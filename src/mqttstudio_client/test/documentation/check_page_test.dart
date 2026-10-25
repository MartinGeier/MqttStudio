import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/check_service.dart';
import 'package:mqttstudio/documentation/documentation_page.dart';
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/simulator.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:typed_data/typed_buffers.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';

void main() {
  late List<FakeMqttAdapter> connections;

  setUpAll(loadTranslations);

  setUp(() {
    setUpServices();
    GetIt.I.registerSingleton(SrxNavigationService(Container(), Container()));
    GetIt.I.get<CheckService>().dispose();
    GetIt.I.unregister<CheckService>();
    connections = [];
    GetIt.I.registerSingleton(CheckService(connectionFactory: () {
      var connection = FakeMqttAdapter();
      connections.add(connection);
      return connection;
    }));
  });

  tearDown(() async {
    GetIt.I.get<CheckService>().dispose();
    await tearDownServices();
  });

  ReceivedMqttMessage received(String topic, String payload) => ReceivedMqttMessage(
      1, topic, Uint8Buffer()..addAll(utf8.encode(payload)), MqttQos.atMostOnce, DateTime.now(), false);

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(Size(1600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openNewProject();
    GetIt.I.get<DocumentationService>()
      ..addNode(DocNode(path: 'plant', title: 'Plant'))
      ..addNode(DocNode(
          path: 'plant/on', title: 'Running', topic: TopicSpec(payload: PayloadSpec(format: PayloadFormat.boolean))));
    await tester.pumpWidget(testApp(DocumentationPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('CHECK shows the findings until the panel is closed', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpPage(tester);
      await tester.tap(find.text('CHECK'));
      await tester.pumpAndSettle();
      var connection = connections.single;
      expect(connection.subscribed, ['plant/on']);
      expect(find.text('Findings'), findsOneWidget);
      expect(find.text('No findings yet.'), findsOneWidget);

      connection.messageReceivedEvent.broadcast(received('plant/on', 'maybe'));
      await tester.pump(Duration(seconds: 1));
      expect(find.textContaining('CHECKING'), findsOneWidget);
      expect(find.text('Wrong format'), findsOneWidget);
      expect(find.byTooltip('The check found problems with this topic'), findsOneWidget);

      await tester.tap(find.byTooltip('Stop the check'));
      await tester.pumpAndSettle();
      expect(find.textContaining('CHECKING'), findsNothing);
      expect(find.text('Wrong format'), findsOneWidget);

      await tester.tap(find.byTooltip('Close the findings'));
      await tester.pumpAndSettle();
      expect(find.text('Findings'), findsNothing);
      expect(find.byTooltip('The check found problems with this topic'), findsNothing);
    });
  });

  testWidgets('Create simulation adds a device per documented topic', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpPage(tester);
      var before = GetIt.I.get<Simulator>().devices.length;
      await tester.tap(find.text('plant'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create simulation'));
      await tester.pumpAndSettle();
      var devices = GetIt.I.get<Simulator>().devices;
      expect(devices.length, before + 1);
      var device = devices.last;
      expect(device.name, 'Running');
      expect(device.topics.single.topic, 'plant/on');
      expect(device.topics.single.generator, isA<BoolGenerator>());
      expect(find.text('Added the simulated device Running'), findsOneWidget);
    });
  });
}
