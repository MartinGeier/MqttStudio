import 'dart:async';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/mqtt/mqtt_will.dart';
import 'fake_mqtt_adapter.dart';

// Adapter whose connection attempts wait until the test lets them finish, to close or stop something while it is
// still connecting. A disconnect meanwhile does not stop the attempt, as with a broker that answers late.
class GatedMqttAdapter extends FakeMqttAdapter {
  // false: connect at once
  bool gated = true;
  final List<Completer<void>> _pending = [];

  bool get isConnecting => _pending.isNotEmpty;

  void finishConnecting() {
    for (var pending in _pending) {
      pending.complete();
    }
    _pending.clear();
  }

  @override
  Future connect(MqttSettings mqttSettings, {MqttWill? will}) async {
    if (gated) {
      var pending = Completer<void>();
      _pending.add(pending);
      await pending.future;
    }
    await super.connect(mqttSettings, will: will);
  }
}
