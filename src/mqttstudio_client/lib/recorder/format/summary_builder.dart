import 'dart:convert';
import 'dart:math';
import 'package:mqttstudio/common/utils/payload_utils.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_summary.dart';
import 'package:typed_data/typed_buffers.dart';

class _TopicState {
  int? lastPayloadHash;
  int currentSecond = -1;
  int countInSecond = 0;
}

// Keeps a RecordingSummary up to date message by message, so finishing a recording needs no second pass
class SummaryBuilder {
  // larger text payloads are not parsed to find their type
  static const int maxDetectLength = 64 * 1024;

  final RecordingSummary summary = RecordingSummary();
  final Map<String, _TopicState> _states = {};
  int _currentSecond = -1;
  int _countInSecond = 0;

  void add(RecordedMessage message) {
    summary.messages++;
    summary.payloadBytes += message.payloadLength;
    var second = message.offsetMicros ~/ Duration.microsecondsPerSecond;
    if (second != _currentSecond) {
      _currentSecond = second;
      _countInSecond = 0;
    }
    _countInSecond++;
    summary.peakRatePerSecond = max(summary.peakRatePerSecond, _countInSecond);

    var topic = summary.perTopic.putIfAbsent(message.topic, () => TopicSummary());
    var state = _states.putIfAbsent(message.topic, () => _TopicState());
    _addTo(topic, state, message, second);
  }

  void addMarker(RecordingMarker marker) => summary.markers.update(marker.kind, (count) => count + 1, ifAbsent: () => 1);

  void _addTo(TopicSummary topic, _TopicState state, RecordedMessage message, int second) {
    if (topic.count == 0) {
      topic
        ..firstOffsetMicros = message.offsetMicros
        ..payloadMin = message.payloadLength
        ..payloadMax = message.payloadLength;
    } else {
      var interval = max(0, message.offsetMicros - topic.lastOffsetMicros);
      topic
        ..intervalMinMicros = min(topic.intervalMinMicros ?? interval, interval)
        ..intervalMaxMicros = max(topic.intervalMaxMicros ?? interval, interval)
        ..intervalSumMicros += interval;
      topic.histogram[IntervalHistogram.bucketOf(interval)]++;
      topic
        ..payloadMin = min(topic.payloadMin, message.payloadLength)
        ..payloadMax = max(topic.payloadMax, message.payloadLength);
    }
    topic
      ..count += 1
      ..lastOffsetMicros = message.offsetMicros
      ..payloadTotal += message.payloadLength;
    if (message.retain) {
      topic.retainedCount++;
    }
    if (message.snapshot) {
      topic.snapshotCount++;
    }
    if (message.truncated) {
      topic.truncatedCount++;
    }

    if (second != state.currentSecond) {
      state
        ..currentSecond = second
        ..countInSecond = 0;
    }
    state.countInSecond++;
    topic.peakRatePerSecond = max(topic.peakRatePerSecond, state.countInSecond);

    var hash = _hashOf(message);
    if (state.lastPayloadHash == hash) {
      topic.consecutiveDuplicates++;
    }
    state.lastPayloadHash = hash;

    var kind = _kindOf(message);
    topic.kinds.update(kind, (count) => count + 1, ifAbsent: () => 1);
    if (kind == PayloadType.Number.name) {
      var value = double.tryParse(utf8.decode(message.payload, allowMalformed: true).trim());
      if (value != null) {
        topic
          ..numericMin = min(topic.numericMin ?? value, value)
          ..numericMax = max(topic.numericMax ?? value, value)
          ..numericSum += value
          ..numericCount += 1;
      }
    }
  }

  static int _hashOf(RecordedMessage message) => Object.hash(message.payloadLength, Object.hashAll(message.payload));

  static String _kindOf(RecordedMessage message) {
    var payload = message.payload;
    if (message.payloadLength == 0) {
      return 'Empty';
    }
    if (payload.length >= 4 && payload[0] == 137 && payload[1] == 80 && payload[2] == 78 && payload[3] == 71) {
      return PayloadType.Image.name;
    }
    if (payload.length >= 3 && payload[0] == 255 && payload[1] == 216 && payload[2] == 255) {
      return PayloadType.Image.name;
    }
    if (message.truncated || payload.length > maxDetectLength) {
      return PayloadType.Text.name;
    }
    return PayloadUtils.detectPayloadType(Uint8Buffer()..addAll(payload)).name;
  }
}
