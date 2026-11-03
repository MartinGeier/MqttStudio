import 'dart:async';
import 'package:event/event.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/mqtt/side_connection.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';

// the scanner's connection was lost before or during a scan; the next open connects again
class RetainedConnectionLostException implements Exception {
  @override
  String toString() => 'The connection to the broker was lost';
}

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
  // the connection open() is still making
  SideConnection? _connecting;
  bool _closed = false;
  // ends a running scan
  void Function({bool lost})? _finishScan;

  RetainedScanner({MqttAdapter Function()? connectionFactory}) : _factory = connectionFactory ?? MqttAdapter.new;

  // false again once the connection was lost
  bool get isOpen => _connection?.adapter?.isConnected() ?? false;

  // throws when the broker can't be reached. Closed while it connects, the new connection is closed again.
  Future<void> open(MqttSettings settings) async {
    _closed = false;
    _connection?.close();
    _connection = null;
    var connection = _connecting = SideConnection(_factory, reconnect: false);
    try {
      await connection.connect(SideConnection.settingsFor(settings, 'retained'));
    } on SideConnectionClosedError {
      // close() ran while connecting, the connection is closed already
      return;
    } finally {
      if (identical(_connecting, connection)) {
        _connecting = null;
      }
    }
    if (_closed) {
      connection.close();
      return;
    }
    connection.listen((_) {});
    _connection = connection;
  }

  // the retained messages below the filter, sorted by topic; onFound reports the count while they arrive. Fails with
  // RetainedConnectionLostException when the connection is lost before or during the scan.
  Future<List<ReceivedMqttMessage>> scan(String filter, {void Function(int found)? onFound}) {
    var connection = _connection;
    var adapter = connection?.adapter;
    if (connection == null || adapter == null || !adapter.isConnected()) {
      return Future.error(RetainedConnectionLostException());
    }
    var found = <String, ReceivedMqttMessage>{};
    var completer = Completer<List<ReceivedMqttMessage>>();
    Timer? quiet;
    Timer? limit;
    late void Function(ReceivedMqttMessage?) onMessage;
    late void Function(EventArgs?) onLost;

    void finish({bool lost = false}) {
      if (completer.isCompleted) {
        return;
      }
      _finishScan = null;
      quiet?.cancel();
      limit?.cancel();
      connection.messageReceivedEvent.unsubscribe(onMessage);
      connection.lostEvent.unsubscribe(onLost);
      if (lost) {
        completer.completeError(RetainedConnectionLostException());
        return;
      }
      if (adapter.isConnected()) {
        adapter.unSubscribeFromTopic(filter);
      }
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
    onLost = (_) => finish(lost: true);

    _finishScan = finish;
    connection.messageReceivedEvent.subscribe(onMessage);
    connection.lostEvent.subscribe(onLost);
    try {
      adapter.subscribeToTopic(TopicSubscription(filter, MqttQos.atMostOnce));
    } catch (_) {
      // the client can know the connection is gone before the adapter reported it
      finish(lost: true);
      return completer.future;
    }
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

  // ends a running scan with what it found so far
  void close() {
    _closed = true;
    _finishScan?.call();
    _connecting?.close();
    _connection?.close();
    _connection = null;
  }
}
