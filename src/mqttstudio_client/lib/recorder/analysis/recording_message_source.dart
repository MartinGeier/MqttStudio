import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/message_viewer/message_buffer.dart';
import 'package:mqttstudio/message_viewer/message_source.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/format/recording_reader.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:typed_data/typed_buffers.dart';

// The messages of a recording range for the topic viewer widgets (doc/recorder-design.md §7.2). It never touches
// the project: the colors come from the recording's filters, and each filter shows as one chip that hides or shows
// its topics.
class RecordingMessageSource implements MessageSource {
  static const int maxMessages = 100000;
  static const int _yieldEvery = 2000;

  @override
  final MQTTMessageBuffer messageBuffer = MQTTMessageBuffer();
  @override
  final messageReceivedEvent = Event<ReceivedMqttMessage>();
  @override
  final messagesClearedEvent = Event();
  @override
  final topicSubscriptionsChangedEvent = Event();

  List<RecorderFilter> _filters = [];
  final Set<String> _hidden = {};
  List<ReceivedMqttMessage> _loaded = [];
  // messages in the range, also those beyond maxMessages
  int messagesInRange = 0;

  @override
  bool get isLive => false;

  @override
  bool get paused => false;

  bool get isCut => messagesInRange > _loaded.length;

  int get loadedCount => _loaded.length;

  @override
  List<TopicSubscription> get topicSubscriptions => [
        for (var filter in _filters.where((filter) => !filter.exclude))
          TopicSubscription(filter.filter, filter.qos,
              color: filter.color ?? TopicColor(Colors.black), paused: _hidden.contains(filter.filter)),
      ];

  @override
  TopicColor getTopicColor(String topicName) =>
      RecorderRules.colorFilterOf(topicName, _filters)?.color ?? TopicColor(Colors.black);

  // Loads the messages between the offsets, at most maxMessages. Returns false when cancelled.
  Future<bool> load(RecordingReader reader, {int? fromMicros, int? toMicros, bool Function()? isCancelled}) async {
    var header = reader.header;
    var from = fromMicros ?? 0;
    var to = toMicros ?? reader.footer!.durationMicros;
    var loaded = <ReceivedMqttMessage>[];
    var inRange = 0;
    var cursor = reader.cursor(from: reader.seekEntryFor(from)?.position);
    var count = 0;
    while (true) {
      var entry = await cursor.next();
      if (entry == null) {
        break;
      }
      if (entry is MessageEntry) {
        var message = entry.message;
        if (message.offsetMicros > to) {
          break;
        }
        if (message.offsetMicros >= from) {
          inRange++;
          if (loaded.length < maxMessages) {
            loaded.add(ReceivedMqttMessage(
                loaded.length,
                message.topic,
                Uint8Buffer()..addAll(message.payload),
                message.qos,
                header.startedAt.add(message.offset).toLocal(),
                message.retain,
                properties: message.properties));
          }
        }
      }
      if (++count % _yieldEvery == 0) {
        await Future<void>.delayed(Duration.zero);
        if (isCancelled?.call() ?? false) {
          return false;
        }
      }
    }
    _filters = header.filters;
    _hidden.removeWhere((filter) => !_filters.any((f) => f.filter == filter));
    _loaded = loaded;
    messagesInRange = inRange;
    _fillBuffer();
    topicSubscriptionsChangedEvent.broadcast();
    return true;
  }

  void clear() {
    _loaded = [];
    messagesInRange = 0;
    _filters = [];
    messageBuffer.clear();
    messagesClearedEvent.broadcast();
  }

  bool isHidden(String filter) => _hidden.contains(filter);

  void toggleFilter(String filter) {
    if (!_hidden.remove(filter)) {
      _hidden.add(filter);
    }
    _fillBuffer();
    topicSubscriptionsChangedEvent.broadcast();
  }

  void _fillBuffer() {
    if (_hidden.isEmpty) {
      messageBuffer.storeAll(_loaded);
      return;
    }
    var shown = _filters.where((filter) => !filter.exclude && !_hidden.contains(filter.filter)).toList();
    messageBuffer.storeAll(_loaded.where((message) => RecorderRules.colorFilterOf(message.topicName, shown) != null).toList());
  }
}
