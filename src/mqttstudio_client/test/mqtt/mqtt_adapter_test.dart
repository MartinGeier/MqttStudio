import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/broker_info.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/mqtt/mqtt_connection_viewmodel.dart';
import 'package:mqttstudio/mqtt/mqtt_protocol_client.dart';
import 'package:mqttstudio/mqtt/mqtt_will.dart';
import 'package:mqttstudio/mqtt/tls_context.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:typed_data/typed_buffers.dart';
import '../helpers/test_setup.dart';

// Protocol client whose connect waits until the test lets it finish, then succeeds like a broker that answers late
class _GatedProtocolClient extends MqttProtocolClient {
  final Completer<void> _gate = Completer<void>();
  bool connected = false;
  int disconnectCount = 0;
  bool? bundledCaLoadedOnConnect;

  void finishConnecting() => _gate.complete();

  @override
  MqttProtocolVersion get protocolVersion => MqttProtocolVersion.v5;

  @override
  BrokerInfo? get brokerInfo => connected ? BrokerInfo(protocolVersion) : null;

  @override
  String? get lastDisconnectReason => null;

  @override
  Future connect(MqttSettings mqttSettings, {MqttWill? will}) async {
    bundledCaLoadedOnConnect = TlsContext.isBundledCaLoaded;
    await _gate.future;
    connected = true;
    onConnected?.call();
  }

  @override
  void disconnect() {
    disconnectCount++;
    if (connected) {
      connected = false;
      onDisconnected?.call();
    }
  }

  @override
  void dropConnection() => disconnect();

  @override
  bool isConnected() => connected;

  @override
  void subscribe(TopicSubscription subscription) {}

  @override
  void unsubscribe(String topic) {}

  @override
  void publish(String topic, Uint8Buffer payload, MqttQos qos, bool retain, MqttMessageProperties? properties) {}
}

void main() {
  var settings = MqttSettings('test.mosquitto.org', 'client', 1883);
  late List<_GatedProtocolClient> clients;
  late MqttAdapter adapter;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    clients = [];
    adapter = MqttAdapter(clientFactory: (_) {
      var client = _GatedProtocolClient();
      clients.add(client);
      return client;
    });
  });

  Future<void> untilConnecting(int count) async {
    for (var i = 0; i < 100 && clients.length < count; i++) {
      await Future.delayed(Duration.zero);
    }
    expect(clients, hasLength(count));
  }

  // must run first: the bundled CA is loaded once per test isolate
  test('the first connect waits for the bundled CA', () async {
    var connecting = adapter.connect(settings);
    await untilConnecting(1);
    clients.single.finishConnecting();
    await connecting;

    expect(clients.single.bundledCaLoadedOnConnect, isTrue);
  });

  test('connects', () async {
    var connected = 0;
    adapter.onConnectedEvent.subscribe((_) => connected++);

    var connecting = adapter.connect(settings);
    await untilConnecting(1);
    clients.single.finishConnecting();
    await connecting;

    expect(adapter.isConnected(), isTrue);
    expect(connected, 1);
  });

  test('a disconnect while connecting cancels the connect and closes its connection', () async {
    var connected = 0;
    adapter.onConnectedEvent.subscribe((_) => connected++);
    var connecting = adapter.connect(settings);
    await untilConnecting(1);

    adapter.disconnect();
    clients.single.finishConnecting();

    await expectLater(
        connecting,
        throwsA(isA<SrxServiceException>()
            .having((exc) => exc.serviceError, 'serviceError', ServiceError.MqttConnectCancelled)));
    expect(adapter.isConnected(), isFalse);
    expect(clients.single.connected, isFalse);
    expect(connected, 0);
  });

  test('a second connect cancels the first one', () async {
    var disconnected = 0;
    adapter.onDisconnectedEvent.subscribe((_) => disconnected++);
    var first = adapter.connect(settings);
    await untilConnecting(1);
    var second = adapter.connect(settings);
    await untilConnecting(2);

    clients[0].finishConnecting();
    clients[1].finishConnecting();

    await expectLater(first, throwsA(isA<SrxServiceException>()));
    await second;
    expect(clients[0].connected, isFalse);
    expect(adapter.isConnected(), isTrue);
    expect(disconnected, 0, reason: 'the replaced connection does not report for the adapter');
  });

  test('a failing subscriber does not stop the rest of the messages', () async {
    var connecting = adapter.connect(settings);
    await untilConnecting(1);
    clients.single.finishConnecting();
    await connecting;
    var received = <String>[];
    adapter.messageReceivedEvent.subscribe((message) {
      if (message.topicName == 'bad') {
        throw StateError('handler failed');
      }
      received.add(message.topicName);
    });

    clients.single.onMessagesReceived!([
      for (var topic in ['a', 'bad', 'b'])
        ReceivedMqttMessage(1, topic, Uint8Buffer(), MqttQos.atMostOnce, DateTime.now(), false)
    ]);
    await pumpEventQueue();

    expect(received, ['a', 'b']);
  });

  group('closing the project while connecting', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      GetIt.I.registerSingleton<MqttAdapter>(adapter);
      GetIt.I.registerSingleton(ProjectManager(() async => false));
    });
    tearDown(tearDownServices);

    test('ends disconnected without an error', () async {
      var manager = GetIt.I.get<ProjectManager>();
      var project = createProject();
      await manager.openProject(project);
      var viewmodel = MqttConnectionViewmodel();
      String? error;
      viewmodel.onError = (message) => error = message;

      var connecting = viewmodel.connect(project.mqttSettings);
      await untilConnecting(1);
      await manager.closeProject();
      clients.single.finishConnecting();
      await connecting;

      expect(manager.isProjectOpen, isFalse);
      expect(viewmodel.isConnected(), isFalse);
      expect(viewmodel.isBusy, isFalse);
      expect(error, isNull);
    });
  });
}
