import 'dart:async';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/mqtt/side_connection.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';

// Finds the retained messages below a topic filter on a connection of its own, so the topic viewer doesn't see the
// scan: the broker sends them right after the subscription, with the retain flag set. A scan ends [quietPeriod] after
// the last one arrived, [firstMessageWait] after subscribing when none arrives, and after [maxDuration] at the latest.
// Clearing publishes an empty retained message per topic, which makes the broker delete the retained one.
class RetainedScanner {
  static const Duration firstMessageWait = Duration(seconds: 2);
  static const Duration quietPeriod = Duration(milliseconds: 800);
  static const Duration maxDuration = Duration(seconds: 15);

  final MqttAdapter Function() _factory;
  SideConnection? _connection;
  // ends a running scan
  void Function()? _finishScan;

  RetainedScanner({MqttAdapter Function()? connectionFactory}) : _factory = connectionFactory ?? MqttAdapter.new;

  bool get isOpen => _connection != null;

  // throws when the broker can't be reached
  Future<void> open(MqttSettings settings) async {
    var connection = SideConnection(_factory, reconnect: false);
    await connection.connect(SideConnection.settingsFor(settings, 'retained'));
    connection.listen((_) {});
    _connection = connection;
  }

  // the retained messages below the filter, sorted by topic; onFound reports the count while they arrive
  Future<List<ReceivedMqttMessage>> scan(String filter, {void Function(int found)? onFound}) {
    var connection = _connection!;
    var found = <String, ReceivedMqttMessage>{};
    var completer = Completer<List<ReceivedMqttMessage>>();
    Timer? quiet;
    Timer? limit;
    late void Function(ReceivedMqttMessage?) onMessage;

    void finish() {
      if (completer.isCompleted) {
        return;
      }
      _finishScan = null;
      quiet?.cancel();
      limit?.cancel();
      connection.messageReceivedEvent.unsubscribe(onMessage);
      connection.adapter?.unSubscribeFromTopic(filter);
      completer.complete(found.values.toList()..sort((a, b) => a.topicName.compareTo(b.topicName)));
    }

    onMessage = (message) {
      // messages published while scanning arrive without the retain flag
      if (message == null || !message.retain || !RecorderRules.matches(message.topicName, filter)) {
        return;
      }
      found[message.topicName] = message;
      onFound?.call(found.length);
      quiet?.cancel();
      quiet = Timer(quietPeriod, finish);
    };

    _finishScan = finish;
    connection.messageReceivedEvent.subscribe(onMessage);
    connection.adapter!.subscribeToTopic(TopicSubscription(filter, MqttQos.atMostOnce));
    quiet = Timer(firstMessageWait, finish);
    limit = Timer(maxDuration, finish);
    return completer.future;
  }

  void clear(List<String> topics) {
    var adapter = _connection!.adapter!;
    for (var topic in topics) {
      adapter.publish(topic, '', MqttPayloadType.string, true, MqttQos.atLeastOnce);
    }
  }

  void close() {
    _finishScan?.call();
    _connection?.close();
    _connection = null;
  }
}
