import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/mqtt/mqtt_connection_viewmodel.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_setup.dart';
import 'package:mqttstudio/mqtt/mqtt_will.dart';

// Adapter whose connection attempt fails like an unreachable broker
class FailingMqttAdapter extends FakeMqttAdapter {
  @override
  Future connect(MqttSettings mqttSettings, {MqttWill? will}) async {
    throw SrxServiceException('broker not reachable', ServiceError.MqttCannotConnect);
  }
}

void main() {
  late FakeMqttAdapter adapter;

  setUp(() => adapter = setUpServices());
  tearDown(tearDownServices);

  var settings = MqttSettings('test.mosquitto.org', 'client', 1883);

  group('MqttConnectionViewmodel', () {
    test('connects and is busy while connecting', () async {
      var viewmodel = MqttConnectionViewmodel();
      var busyStates = <bool>[];
      viewmodel.addListener(() => busyStates.add(viewmodel.isBusy));

      await viewmodel.connect(settings);

      expect(viewmodel.isConnected(), isTrue);
      expect(adapter.connectedWith, same(settings));
      expect(busyStates.first, isTrue);
      expect(busyStates.last, isFalse);
    });

    test('does not connect without hostname or client id', () async {
      var viewmodel = MqttConnectionViewmodel();

      await viewmodel.connect(MqttSettings(' ', 'client', 1883));
      await viewmodel.connect(MqttSettings('test.mosquitto.org', '', 1883));

      expect(adapter.connectedWith, isNull);
    });

    test('reports a failed connection through onError', () async {
      await tearDownServices();
      setUpServices(FailingMqttAdapter());
      var viewmodel = MqttConnectionViewmodel();
      String? error;
      viewmodel.onError = (message) => error = message;

      await viewmodel.connect(settings);

      expect(error, 'broker not reachable');
      expect(viewmodel.isBusy, isFalse);
    });

    test('disconnects', () async {
      var viewmodel = MqttConnectionViewmodel();
      await viewmodel.connect(settings);

      viewmodel.disconnect();

      expect(viewmodel.isConnected(), isFalse);
    });

    test('notifies when the broker closes the connection', () async {
      var viewmodel = MqttConnectionViewmodel();
      await viewmodel.connect(settings);
      var notified = 0;
      viewmodel.addListener(() => notified++);

      // the broker drops the connection without the user disconnecting
      adapter.disconnect();

      expect(notified, greaterThan(0));
    });

    test('reports the reason an MQTT 5 broker gave for closing the connection', () async {
      var viewmodel = MqttConnectionViewmodel();
      String? reason;
      viewmodel.onBrokerDisconnected = (value) => reason = value;
      await viewmodel.connect(settings);

      adapter.dropConnection(reason: 'Session taken over (0x8e)');

      expect(reason, 'Session taken over (0x8e)');
      expect(viewmodel.isConnected(), isFalse);
    });

    test('does not report a reason when none was given', () async {
      var viewmodel = MqttConnectionViewmodel();
      var reported = false;
      viewmodel.onBrokerDisconnected = (_) => reported = true;
      await viewmodel.connect(settings);

      adapter.dropConnection();

      expect(reported, isFalse);
    });

    test('reports a rejected subscription', () async {
      var viewmodel = MqttConnectionViewmodel();
      String? failedTopic;
      String? failedReason;
      viewmodel.onSubscribeFailed = (topic, reason) {
        failedTopic = topic;
        failedReason = reason;
      };

      adapter.failSubscription('home/#', 'Not authorized (0x87)');

      expect(failedTopic, 'home/#');
      expect(failedReason, 'Not authorized (0x87)');
    });

    test('offers the broker info of the connection', () async {
      var viewmodel = MqttConnectionViewmodel();
      expect(viewmodel.brokerInfo, isNull);

      await viewmodel.connect(settings);

      expect(viewmodel.brokerInfo!.protocolVersion, settings.protocolVersion);
    });
  });
}
