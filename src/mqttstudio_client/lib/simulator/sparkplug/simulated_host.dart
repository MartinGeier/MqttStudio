import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:clock/clock.dart';
import 'package:event/event.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/mqtt/mqtt_will.dart';
import 'package:mqttstudio/mqtt/side_connection.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_profile.dart';
import 'package:typed_data/typed_buffers.dart';

// The primary host application the simulator can play (doc/sparkplug-design.md §10.4, Q2): a connection of its own
// whose will is the retained STATE offline, and a retained STATE online with the same timestamp. A lost connection is
// made again with the reconnect delays of the side connections, with a new timestamp, until the host stops.
class SimulatedHost {
  static const List<Duration> reconnectDelays = SideConnection.reconnectDelays;

  final String hostId;
  final MqttSettings settings;
  final MqttAdapter Function() connectionFactory;
  MqttAdapter? _adapter;
  Timer? _retryTimer;
  int _attempt = 0;
  bool _running = false;

  SimulatedHost(this.hostId, {required this.settings, required this.connectionFactory});

  String get topic => '${SparkplugProfile.namespace}/${SpbMessageType.state}/$hostId';

  bool get isOnline => _adapter?.isConnected() ?? false;

  // throws when the broker can't be reached
  Future<void> start() async {
    if (_running) {
      return;
    }
    _running = true;
    try {
      await _connect();
    } catch (_) {
      _running = false;
      rethrow;
    }
  }

  // a host that shuts down announces it before it disconnects
  void stop() {
    _running = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    var adapter = _adapter;
    if (adapter == null) {
      return;
    }
    _detach();
    if (adapter.isConnected()) {
      _publish(adapter, false, clock.now().millisecondsSinceEpoch);
    }
    adapter.disconnect();
  }

  Future<void> _connect() async {
    var timestamp = clock.now().millisecondsSinceEpoch;
    var adapter = connectionFactory();
    try {
      await adapter.connect(
        settings,
        will: MqttWill(topic, _state(false, timestamp), qos: MqttQos.atLeastOnce, retain: true),
      );
      if (_running) {
        _publish(adapter, true, timestamp);
      }
    } catch (_) {
      adapter.disconnect();
      rethrow;
    }
    if (!_running) {
      adapter.disconnect();
      return;
    }
    _attempt = 0;
    _adapter = adapter;
    adapter.onDisconnectedEvent.subscribe(_onDisconnected);
  }

  void _onDisconnected(EventArgs? _) {
    _detach();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_running) {
      return;
    }
    var wait = reconnectDelays[min(_attempt, reconnectDelays.length - 1)];
    _attempt++;
    _retryTimer = Timer(wait, _reconnect);
  }

  Future<void> _reconnect() async {
    _retryTimer = null;
    if (!_running) {
      return;
    }
    try {
      await _connect();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _detach() {
    _adapter?.onDisconnectedEvent.unsubscribe(_onDisconnected);
    _adapter = null;
  }

  void _publish(MqttAdapter adapter, bool online, int timestamp) => adapter.publish(
    topic,
    Uint8Buffer()..addAll(_state(online, timestamp)),
    MqttPayloadType.binary,
    true,
    MqttQos.atLeastOnce,
  );

  static Uint8List _state(bool online, int timestamp) =>
      Uint8List.fromList(utf8.encode(jsonEncode({'online': online, 'timestamp': timestamp})));
}
