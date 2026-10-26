import 'dart:collection';
import 'dart:convert';
import 'package:event/event.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/mqtt/side_connection.dart';

class SysValue {
  final String value;
  final DateTime receivedOn;

  const SysValue(this.value, this.receivedOn);
}

// A broker statistic of the summary and the $SYS topics it is read from, the first one that has a value wins.
// Mosquitto's names come first; EMQX publishes version and uptime per node below $SYS/brokers/<node>/.
class SysSummaryItem {
  final String key;
  final List<RegExp> topics;
  // the value is a rate per minute
  final bool perMinute;

  SysSummaryItem(this.key, List<String> patterns, {this.perMinute = false})
      : topics = [for (var pattern in patterns) RegExp('^$pattern\$')];
}

// Receives the broker's $SYS topics on a connection of its own, so they don't show in the topic viewer. Brokers
// publish them periodically (Mosquitto every 10 s by default); brokers without $SYS topics or with an ACL that
// hides them send nothing.
class SysMonitor {
  static const String filter = r'$SYS/#';

  static final List<SysSummaryItem> summaryItems = [
    SysSummaryItem('version', [r'\$SYS/broker/version', r'\$SYS/brokers/[^/]+/version']),
    SysSummaryItem('uptime', [r'\$SYS/broker/uptime', r'\$SYS/brokers/[^/]+/uptime']),
    SysSummaryItem('clientsconnected', [r'\$SYS/broker/clients/connected', r'\$SYS/broker/clients/active']),
    SysSummaryItem('clientstotal', [r'\$SYS/broker/clients/total']),
    SysSummaryItem('clientsmaximum', [r'\$SYS/broker/clients/maximum']),
    SysSummaryItem('messagesreceived', [r'\$SYS/broker/load/messages/received/1min'], perMinute: true),
    SysSummaryItem('messagessent', [r'\$SYS/broker/load/messages/sent/1min'], perMinute: true),
    SysSummaryItem('bytesreceived', [r'\$SYS/broker/load/bytes/received/1min'], perMinute: true),
    SysSummaryItem('bytessent', [r'\$SYS/broker/load/bytes/sent/1min'], perMinute: true),
    SysSummaryItem('subscriptions', [r'\$SYS/broker/subscriptions/count']),
    SysSummaryItem('retained', [r'\$SYS/broker/retained messages/count']),
    SysSummaryItem('stored', [r'\$SYS/broker/store/messages/count']),
    SysSummaryItem('heap', [r'\$SYS/broker/heap/current']),
  ];

  final MqttAdapter Function() _factory;
  SideConnection? _connection;
  final SplayTreeMap<String, SysValue> values = SplayTreeMap();
  final changedEvent = Event();

  SysMonitor({MqttAdapter Function()? connectionFactory}) : _factory = connectionFactory ?? MqttAdapter.new;

  // throws when the broker can't be reached
  Future<void> open(MqttSettings settings) async {
    var connection = SideConnection(_factory);
    await connection.connect(SideConnection.settingsFor(settings, 'sys'));
    connection.messageReceivedEvent.subscribe(_onMessage);
    connection.listen((adapter) => adapter.subscribeToTopic(TopicSubscription(filter, MqttQos.atMostOnce)));
    _connection = connection;
  }

  void close() {
    _connection?.messageReceivedEvent.unsubscribe(_onMessage);
    _connection?.close();
    _connection = null;
  }

  String? valueOf(SysSummaryItem item) {
    for (var pattern in item.topics) {
      for (var entry in values.entries) {
        if (pattern.hasMatch(entry.key)) {
          return entry.value.value;
        }
      }
    }
    return null;
  }

  void _onMessage(ReceivedMqttMessage? message) {
    if (message == null || !message.topicName.startsWith(r'$SYS/')) {
      return;
    }
    values[message.topicName] = SysValue(utf8.decode(message.payload, allowMalformed: true), message.receivedOn);
    changedEvent.broadcast();
  }
}
