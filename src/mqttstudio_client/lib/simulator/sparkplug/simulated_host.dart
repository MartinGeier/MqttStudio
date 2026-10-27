import 'dart:convert';
import 'dart:typed_data';
import 'package:clock/clock.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/mqtt/mqtt_will.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_profile.dart';
import 'package:typed_data/typed_buffers.dart';

// The primary host application the simulator can play (doc/sparkplug-design.md §10.4, Q2): a connection of its own
// whose will is the retained STATE offline, and a retained STATE online with the same timestamp.
class SimulatedHost {
  final String hostId;
  final MqttSettings settings;
  final MqttAdapter Function() connectionFactory;
  MqttAdapter? _adapter;

  SimulatedHost(this.hostId, {required this.settings, required this.connectionFactory});

  String get topic => '${SparkplugProfile.namespace}/${SpbMessageType.state}/$hostId';

  bool get isOnline => _adapter?.isConnected() ?? false;

  // throws when the broker can't be reached
  Future<void> start() async {
    if (_adapter != null) {
      return;
    }
    var timestamp = clock.now().millisecondsSinceEpoch;
    var adapter = connectionFactory();
    await adapter.connect(
      settings,
      will: MqttWill(topic, _state(false, timestamp), qos: MqttQos.atLeastOnce, retain: true),
    );
    _adapter = adapter;
    _publish(true, timestamp);
  }

  // a host that shuts down announces it before it disconnects
  void stop() {
    var adapter = _adapter;
    if (adapter == null) {
      return;
    }
    if (adapter.isConnected()) {
      _publish(false, clock.now().millisecondsSinceEpoch);
    }
    _adapter = null;
    adapter.disconnect();
  }

  void _publish(bool online, int timestamp) => _adapter!.publish(
    topic,
    Uint8Buffer()..addAll(_state(online, timestamp)),
    MqttPayloadType.binary,
    true,
    MqttQos.atLeastOnce,
  );

  static Uint8List _state(bool online, int timestamp) =>
      Uint8List.fromList(utf8.encode(jsonEncode({'online': online, 'timestamp': timestamp})));
}
