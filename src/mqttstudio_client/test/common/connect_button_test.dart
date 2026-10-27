import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/connect_button.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/mqtt/mqtt_will.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';

// Adapter whose connection attempt waits until the test lets it finish. The completer is created inside connect so it
// belongs to the test's fake async zone, where the widget tester pumps its microtasks.
class _SlowMqttAdapter extends FakeMqttAdapter {
  Completer<void>? _pendingConnect;

  void finishConnecting() => _pendingConnect!.complete();

  @override
  Future connect(MqttSettings mqttSettings, {MqttWill? will}) async {
    _pendingConnect = Completer<void>();
    await _pendingConnect!.future;
    await super.connect(mqttSettings, will: will);
  }
}

void main() {
  late _SlowMqttAdapter adapter;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTranslations();
  });

  setUp(() {
    adapter = _SlowMqttAdapter();
    setUpServices(adapter);
    GetIt.I.registerSingleton(SrxNavigationService(Container(), Container()));
  });
  tearDown(tearDownServices);

  ElevatedButton button(WidgetTester tester) => tester.widget<ElevatedButton>(find.byType(ElevatedButton));

  Color? background(WidgetTester tester, Set<WidgetState> states) =>
      button(tester).style?.backgroundColor?.resolve(states);

  group('ConnectButton', () {
    testWidgets('offers to create a project while none is open', (tester) async {
      await tester.pumpWidget(testApp(ConnectButton()));
      await tester.pumpAndSettle();

      expect(find.text('CONNECT'), findsOneWidget);
      expect(find.byTooltip('Create a project and connect to its broker'), findsOneWidget);

      await openNewProject();
      await tester.pumpAndSettle();

      expect(find.byTooltip('Connect to test.mosquitto.org:1883'), findsOneWidget);
    });

    testWidgets('names the action, the state stays in color and icon', (tester) => ignoringOverflowErrors(() async {
      // DISCONNECT and CONNECTING overflow the 150px row in the wide test font
      await openNewProject();
      await tester.pumpWidget(testApp(ConnectButton()));
      await tester.pumpAndSettle();

      expect(find.text('CONNECT'), findsOneWidget);
      expect(find.byIcon(Icons.power_off), findsOneWidget);
      expect(find.byTooltip('Connect to test.mosquitto.org:1883'), findsOneWidget);
      expect(background(tester, {}), Colors.red);

      // the spinner animates, so pump single frames while connecting
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(find.text('CONNECTING'), findsOneWidget);
      expect(find.byTooltip('Connecting to test.mosquitto.org:1883 …'), findsOneWidget);
      expect(button(tester).enabled, isFalse);
      expect(background(tester, {WidgetState.disabled}), Colors.red);

      adapter.finishConnecting();
      await tester.pumpAndSettle();
      expect(find.text('DISCONNECT'), findsOneWidget);
      expect(find.byIcon(Icons.power), findsOneWidget);
      expect(find.byTooltip('Disconnect from test.mosquitto.org:1883'), findsOneWidget);
      expect(background(tester, {}), Colors.green);
      expect(adapter.connectedWith?.hostname, 'test.mosquitto.org');

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(find.text('CONNECT'), findsOneWidget);
      expect(adapter.isConnected(), isFalse);
    }));
  });
}
