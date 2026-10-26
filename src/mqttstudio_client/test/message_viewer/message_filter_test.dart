import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/message_viewer/message_buffer.dart';
import 'package:mqttstudio/message_viewer/message_filter.dart';
import '../helpers/test_setup.dart';

void main() {
  group('MessageFilter topics', () {
    test('finds part of the topic, ignoring case', () {
      var filter = MessageFilter('kitchen');

      expect(filter.matches(message('home/Kitchen/temp', '1')), isTrue);
      expect(filter.matches(message('home/garage', '1')), isFalse);
    });

    test('matches MQTT wildcards level by level', () {
      var single = MessageFilter('plant/+/temp');
      var multi = MessageFilter('sensors/#');

      expect(single.matches(message('plant/line1/temp', '1')), isTrue);
      expect(single.matches(message('plant/line1/m1/temp', '1')), isFalse);
      expect(multi.matches(message('sensors', '1')), isTrue);
      expect(multi.matches(message('sensors/a/b', '1')), isTrue);
      expect(multi.matches(message('other/sensors/a', '1')), isFalse);
    });

    test('rejects wildcards that do not fill a level', () {
      expect(() => MessageFilter('plant/li+'), throwsFormatException);
      expect(() => MessageFilter('plant/#/temp'), throwsFormatException);
    });

    test('takes regular expressions, ignoring case', () {
      var filter = MessageFilter(r'line[12]/TEMP$', regex: true);

      expect(filter.matches(message('plant/line2/temp', '1')), isTrue);
      expect(filter.matches(message('plant/line3/temp', '1')), isFalse);
      expect(() => MessageFilter('(', regex: true), throwsFormatException);
    });

    test('is null for an empty text', () {
      expect(MessageFilter.create('  '), isNull);
      expect(MessageFilter.create(null), isNull);
    });
  });

  group('MessageFilter payloads', () {
    test('finds text in the payload, ignoring case', () {
      var filter = MessageFilter('error', mode: MessageFilterMode.payload);

      expect(filter.matches(message('a', '{"state":"ERROR"}')), isTrue);
      expect(filter.matches(message('a', '{"state":"ok"}')), isFalse);
    });

    test('takes regular expressions', () {
      var filter = MessageFilter(r'"temp":\s*9\d', mode: MessageFilterMode.payload, regex: true);

      expect(filter.matches(message('a', '{"temp": 95}')), isTrue);
      expect(filter.matches(message('a', '{"temp": 85}')), isFalse);
    });
  });

  group('MessageFilter conditions', () {
    test('compares a JSON value on all topics without a topic filter', () {
      var filter = MessageFilter(r'$.status == "error"', mode: MessageFilterMode.condition);

      expect(filter.matches(message('a/b', '{"status":"error"}')), isTrue);
      expect(filter.matches(message('c', '{"status":"ok"}')), isFalse);
      expect(filter.matches(message('c', 'no json')), isFalse);
    });

    test('compares numbers and whole payloads', () {
      var nested = MessageFilter(r'$.temp > 80', mode: MessageFilterMode.condition);
      var whole = MessageFilter('> 80', mode: MessageFilterMode.condition);

      expect(nested.matches(message('a', '{"temp":81}')), isTrue);
      expect(nested.matches(message('a', '{"temp":79}')), isFalse);
      expect(whole.matches(message('a', '100')), isTrue);
      expect(whole.matches(message('a', '9')), isFalse);
    });

    test('applies a leading topic filter', () {
      var filter = MessageFilter(r'plant/+/temp $.value >= 10', mode: MessageFilterMode.condition);

      expect(filter.matches(message('plant/l1/temp', '{"value":10}')), isTrue);
      expect(filter.matches(message('plant/l1/hum', '{"value":10}')), isFalse);
    });

    test(r'keeps a $SYS topic filter a topic filter', () {
      var filter = MessageFilter(r'$SYS/broker/#', mode: MessageFilterMode.condition);

      expect(filter.matches(message(r'$SYS/broker/uptime', '1')), isTrue);
    });

    test('reports invalid conditions', () {
      expect(() => MessageFilter(r'$.temp >', mode: MessageFilterMode.condition), throwsFormatException);
      expect(() => MessageFilter(r'$.temp ? 3', mode: MessageFilterMode.condition), throwsFormatException);
    });
  });

  group('MQTTMessageBuffer with filters', () {
    late MQTTMessageBuffer buffer;

    setUp(() {
      buffer = MQTTMessageBuffer();
      buffer.storeMessage(message('plant/line1/temp', '{"value":50}'));
      buffer.storeMessage(message('plant/line2/temp', '{"value":90}'));
      buffer.storeMessage(message('plant/line2/hum', '{"value":95}'));
    });

    test('lists the matching messages', () {
      expect(buffer.getMessages(MessageFilter('plant/+/temp')).map((x) => x.topicName),
          ['plant/line2/temp', 'plant/line1/temp']);
    });

    test('keeps the matching topics in the tree and the levels above them', () {
      var tree = buffer.getMessagesTree(MessageFilter('plant/+/temp'));

      var plant = tree.children.single;
      expect(plant.children.map((x) => x.topicLevelName), ['line1', 'line2']);
      expect(plant.children.last.children.map((x) => x.topicLevelName), ['temp']);
    });

    test('tests the last message of each topic in the tree for payload conditions', () {
      var tree = buffer.getMessagesTree(MessageFilter(r'$.value > 80', mode: MessageFilterMode.condition));

      var line2 = tree.children.single.children.single;
      expect(line2.topicLevelName, 'line2');
      expect(line2.children.map((x) => x.topicLevelName), ['temp', 'hum']);
    });

    test('returns an empty tree when nothing matches', () {
      expect(buffer.getMessagesTree(MessageFilter('nothing')).children, isEmpty);
    });
  });
}
