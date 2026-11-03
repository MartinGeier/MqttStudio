import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/message_viewer/message_buffer.dart';
import 'package:mqttstudio/message_viewer/topic_stats.dart';
import '../helpers/test_setup.dart';

void main() {
  var start = DateTime(2026, 10, 25, 12);

  group('TopicStats', () {
    test('measures the rates over the last ten seconds', () {
      var stats = TopicStats();
      for (var i = 0; i < 20; i++) {
        stats.add(start.add(Duration(milliseconds: 500 * i)), 100);
      }
      var now = start.add(Duration(milliseconds: 9500));

      expect(stats.messagesPerSecond(now), 2);
      expect(stats.bytesPerSecond(now), 200);
      expect(stats.messagesPerSecond(now.add(Duration(seconds: 30))), 0);
    });

    test('measures a young topic over the time since its first message', () {
      var stats = TopicStats();
      stats.add(start, 10);
      stats.add(start.add(Duration(seconds: 1)), 10);

      expect(stats.messagesPerSecond(start.add(Duration(seconds: 1))), 1);
    });

    test('knows the time since the last message', () {
      var stats = TopicStats();
      expect(stats.sinceLast(start), isNull);

      stats.add(start, 1);

      expect(stats.sinceLast(start.add(Duration(seconds: 3))), Duration(seconds: 3));
    });

    test('measures the mean interval and its jitter', () {
      var stats = TopicStats();
      stats.add(start, 1);
      expect(stats.meanInterval, isNull);
      stats.add(start.add(Duration(milliseconds: 900)), 1);
      expect(stats.jitter, isNull);
      stats.add(start.add(Duration(milliseconds: 2000)), 1);

      expect(stats.meanInterval, Duration(seconds: 1));
      // intervals of 900 and 1100 ms
      expect(stats.jitter!.inMilliseconds, 141);
    });

    test('leaves retained messages out of the intervals', () {
      var stats = TopicStats();
      stats.add(start, 1, retained: true);
      stats.add(start.add(Duration(seconds: 5)), 1);
      stats.add(start.add(Duration(seconds: 6)), 1);

      expect(stats.meanInterval, Duration(seconds: 1));
      expect(stats.count, 3);
    });

    test('formats rates, bytes and durations', () {
      expect(TopicStats.formatRate(0), '0');
      expect(TopicStats.formatRate(2.345), '2.3');
      expect(TopicStats.formatRate(1500), '1.5k');
      expect(TopicStats.formatBytesPerSecond(340), '340 B/s');
      expect(TopicStats.formatBytesPerSecond(1200), '1.2 kB/s');
      expect(TopicStats.formatDuration(Duration(milliseconds: 450)), '450 ms');
      expect(TopicStats.formatDuration(Duration(milliseconds: 2500)), '2.50 s');
      expect(TopicStats.formatDuration(Duration(minutes: 5)), '5.0 min');
    });
  });

  group('MQTTMessageBuffer topic nodes', () {
    test('keep statistics per topic', () {
      var buffer = MQTTMessageBuffer();
      buffer.storeMessage(message('a/b', '12345', receivedOn: start));
      buffer.storeMessage(message('a/b', '12345', receivedOn: start.add(Duration(seconds: 1))));

      var node = buffer.findNode('a/b')!;
      expect(node.isTopic, isTrue);
      expect(buffer.findNode('a')!.isTopic, isFalse);
      expect(node.stats.count, 2);
      expect(node.stats.totalBytes, 10);
      expect(buffer.findNode('a/c'), isNull);
    });

    test('find the previous message of the same topic', () {
      var buffer = MQTTMessageBuffer();
      buffer.storeMessage(message('a', '1'));
      buffer.storeMessage(message('b', '2'));
      buffer.storeMessage(message('a', '3'));
      var last = buffer.getLastMessageForTopic('a')!;

      expect(buffer.getPreviousMessage(last)!.payload, toPayload('1'));
      expect(buffer.getPreviousMessage(buffer.getPreviousMessage(last)!), isNull);
    });
  });
}
