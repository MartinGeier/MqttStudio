import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/broker_stats_viewmodel.dart';
import 'package:mqttstudio/mqtt/side_connection.dart';
import 'package:mqttstudio/mqtt/sys_monitor.dart';
import '../helpers/gated_mqtt_adapter.dart';
import '../helpers/test_setup.dart';

void main() {
  var settings = MqttSettings('test.mosquitto.org', 'client', 1883);

  group('SideConnection', () {
    test('connects and receives', () async {
      var adapter = GatedMqttAdapter()..gated = false;
      var connection = SideConnection(() => adapter);

      await connection.connect(settings);
      connection.listen((adapter) => adapter.subscribeToTopic(TopicSubscription('a/#', MqttQos.atMostOnce)));

      expect(adapter.isConnected(), isTrue);
      expect(adapter.subscribed, ['a/#']);
      expect(connection.isClosed, isFalse);
    });

    test('closing while connecting leaves no connection open', () async {
      var adapter = GatedMqttAdapter();
      var connection = SideConnection(() => adapter);
      Object? error;
      var connecting = connection.connect(settings).catchError((Object exc) => error = exc);
      await pumpEventQueue();

      connection.close();
      adapter.finishConnecting();
      await connecting;

      expect(error, isA<SideConnectionClosedError>());
      expect(error, isA<StateError>());
      expect(connection.isClosed, isTrue);
      expect(adapter.isConnected(), isFalse);
      expect(connection.adapter, isNull);
    });

    test('listening after a close does nothing', () async {
      var adapter = GatedMqttAdapter()..gated = false;
      var connection = SideConnection(() => adapter);
      await connection.connect(settings);
      connection.close();

      connection.listen((adapter) => adapter.subscribeToTopic(TopicSubscription('a/#', MqttQos.atMostOnce)));

      expect(adapter.subscribed, isEmpty);
    });

    test('connecting a closed connection throws', () async {
      var connection = SideConnection(GatedMqttAdapter.new)..close();

      await expectLater(connection.connect(settings), throwsA(isA<SideConnectionClosedError>()));
    });

    test('closing during a reconnect leaves no connection open', () {
      fakeAsync((async) {
        var adapter = GatedMqttAdapter()..gated = false;
        var connection = SideConnection(() => adapter);
        var reconnected = 0;
        connection.reconnectedEvent.subscribe((_) => reconnected++);
        connection.connect(settings);
        async.flushMicrotasks();
        connection.listen((adapter) => adapter.subscribeToTopic(TopicSubscription('a/#', MqttQos.atMostOnce)));

        adapter.gated = true;
        adapter.dropConnection();
        async.elapse(SideConnection.reconnectDelays.first);
        expect(adapter.isConnecting, isTrue);

        connection.close();
        adapter.finishConnecting();
        async.flushMicrotasks();

        expect(adapter.isConnected(), isFalse);
        expect(reconnected, 0);
        expect(adapter.subscribed, ['a/#'], reason: 'not subscribed again');
      });
    });
  });

  group('SysMonitor', () {
    test('closing while it connects leaves no connection open', () async {
      var adapter = GatedMqttAdapter();
      var monitor = SysMonitor(connectionFactory: () => adapter);
      var opening = monitor.open(settings);
      await pumpEventQueue();

      monitor.close();
      adapter.finishConnecting();
      await opening;

      expect(adapter.isConnected(), isFalse);
      expect(adapter.subscribed, isEmpty);
    });

    test('subscribes to the \$SYS topics and closes its connection', () async {
      var adapter = GatedMqttAdapter()..gated = false;
      var monitor = SysMonitor(connectionFactory: () => adapter);

      await monitor.open(settings);

      expect(adapter.subscribed, [SysMonitor.filter]);
      monitor.close();
      expect(adapter.isConnected(), isFalse);
    });
  });

  group('BrokerStatsViewmodel', () {
    setUp(() => setUpServices());
    tearDown(tearDownServices);

    test('closing the dialog while it connects leaves no connection open', () async {
      await openNewProject();
      var adapter = GatedMqttAdapter();
      var stats = BrokerStatsViewmodel(connectionFactory: () => adapter);
      var starting = stats.start();
      await pumpEventQueue();

      stats.dispose();
      adapter.finishConnecting();
      await starting;

      expect(adapter.isConnected(), isFalse);
      expect(stats.state, BrokerStatsState.connecting);
    });
  });
}
