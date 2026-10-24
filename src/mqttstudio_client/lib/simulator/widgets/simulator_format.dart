import 'package:easy_localization/easy_localization.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';

// Texts of the simulator tab and its dialogs
class SimulatorFormat {
  static final NumberFormat _count = NumberFormat.decimalPattern('en');

  static String count(int value) => _count.format(value);

  static String rate(double messagesPerSecond) {
    var value = messagesPerSecond < 10 && messagesPerSecond > 0
        ? messagesPerSecond.toStringAsFixed(1)
        : messagesPerSecond.round().toString();
    return 'simulator.rate.label'.tr(args: [value]);
  }

  static String _duration(int ms) {
    if (ms < 1000) {
      return '$ms ms';
    }
    var seconds = ms / 1000;
    return '${seconds == seconds.roundToDouble() ? seconds.round() : seconds} s';
  }

  static String interval(PublishInterval interval) =>
      interval.isRandom ? '${_duration(interval.minMs)} – ${_duration(interval.maxMs)}' : _duration(interval.minMs);

  static String qos(MqttQos qos) {
    switch (qos) {
      case MqttQos.atMostOnce:
        return '0';
      case MqttQos.atLeastOnce:
        return '1';
      case MqttQos.exactlyOnce:
        return '2';
      default:
        return '';
    }
  }

  static String qosAndRetain(SimulatedTopic topic) =>
      topic.retain ? '${qos(topic.qos)} · ${'simulator.retain.short'.tr()}' : qos(topic.qos);

  static String generatorName(GeneratorType type) => 'simulator.generator.${type.key}'.tr();

  static String instances(SimulatedDevice device) => device.instanceCount == 1
      ? 'simulator.device.oneinstance'.tr()
      : 'simulator.device.instances'.tr(args: [
          '${device.instanceCount}',
          '${device.firstInstance}',
          '${device.lastInstance}',
        ]);
}
