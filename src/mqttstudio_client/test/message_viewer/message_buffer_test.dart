import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/message_viewer/message_buffer.dart';
import '../helpers/test_setup.dart';

void main() {
  late MQTTMessageBuffer buffer;
  var start = DateTime(2026, 10, 23, 12, 0, 0);

  setUp(() => buffer = MQTTMessageBuffer());

  group('MQTTMessageBuffer messages', () {
    test('returns the newest message first', () {
      buffer.storeMessage(message('a', '1'));
      buffer.storeMessage(message('b', '2'));

      expect(buffer.length, 2);
      expect(buffer.getMessages(null).map((x) => x.topicName), ['b', 'a']);
      expect(buffer.getLastMessage()!.topicName, 'b');
    });

    test('filters by topic, ignoring case', () {
      buffer.storeMessage(message('home/Kitchen/temp', '1'));
      buffer.storeMessage(message('office/printer', '2'));

      expect(buffer.getMessages('kitchen').map((x) => x.topicName), ['home/Kitchen/temp']);
      expect(buffer.getMessages('nothing'), isEmpty);
    });

    test('returns at most 2000 messages to the view', () {
      for (var i = 0; i < 2100; i++) {
        buffer.storeMessage(message('a', '$i'));
      }

      expect(buffer.length, 2100);
      expect(buffer.getMessages(null).length, 2000);
    });

    test('counts and returns the messages of one topic', () {
      buffer.storeMessage(message('a', '1'));
      buffer.storeMessage(message('b', '2'));
      buffer.storeMessage(message('a', '3'));

      expect(buffer.getTopicMessageCount('a'), 2);
      expect(buffer.getTopicMessages('a').length, 2);
      expect(buffer.getTopicMessageCount('c'), 0);
    });

    test('returns the last message of a topic', () {
      buffer.storeMessage(message('a', 'old'));
      buffer.storeMessage(message('b', 'other'));
      buffer.storeMessage(message('a', 'new'));

      expect(buffer.getLastMessageForTopic('a')!.payload, toPayload('new'));
      expect(buffer.getLastMessageForTopic('c'), isNull);
    });

    test('is empty when no message was received', () {
      expect(buffer.getLastMessage(), isNull);
      expect(buffer.getLastMessageForTopic('a'), isNull);
      expect(buffer.getGroupMessages(MessageGroupTimePeriod.second, null), isEmpty);
    });

    test('clear removes all messages, groups and tree nodes', () {
      buffer.storeMessage(message('a/b', '1'));
      buffer.getGroupMessages(MessageGroupTimePeriod.second, null);

      buffer.clear();

      expect(buffer.length, 0);
      expect(buffer.getMessages(null), isEmpty);
      expect(buffer.getMessagesTree(null).children, isEmpty);
    });
  });

  group('MQTTMessageBuffer groups', () {
    test('groups messages by ten seconds, newest group first', () {
      buffer.storeMessage(message('a', '1', receivedOn: start.add(Duration(seconds: 1))));
      buffer.storeMessage(message('a', '2', receivedOn: start.add(Duration(seconds: 5))));
      buffer.storeMessage(message('a', '3', receivedOn: start.add(Duration(seconds: 12))));

      var groups = buffer.getGroupMessages(MessageGroupTimePeriod.tenSeconds, null);

      expect(groups.map((x) => x.beginOfPeriod), [start.add(Duration(seconds: 10)), start]);
      expect(groups.map((x) => x.messages.length), [1, 2]);
    });

    test('groups by second, minute and hour', () {
      buffer.storeMessage(message('a', '1', receivedOn: start.add(Duration(milliseconds: 200))));
      buffer.storeMessage(message('a', '2', receivedOn: start.add(Duration(milliseconds: 1200))));
      buffer.storeMessage(message('a', '3', receivedOn: start.add(Duration(minutes: 1, seconds: 1))));
      buffer.storeMessage(message('a', '4', receivedOn: start.add(Duration(hours: 1, seconds: 1))));

      expect(buffer.getGroupMessages(MessageGroupTimePeriod.second, null).length, 4);
      expect(buffer.getGroupMessages(MessageGroupTimePeriod.minute, null).length, 3);
      expect(buffer.getGroupMessages(MessageGroupTimePeriod.hour, null).length, 2);
    });

    test('only groups messages matching the filter', () {
      buffer.storeMessage(message('home/temp', '1', receivedOn: start));
      buffer.storeMessage(message('office/temp', '2', receivedOn: start.add(Duration(seconds: 30))));

      var groups = buffer.getGroupMessages(MessageGroupTimePeriod.tenSeconds, 'home');

      expect(groups.single.messages.single.topicName, 'home/temp');
    });

    test('adds new messages to the groups after they were built', () {
      buffer.storeMessage(message('a', '1', receivedOn: start.add(Duration(seconds: 1))));
      var groups = buffer.getGroupMessages(MessageGroupTimePeriod.tenSeconds, null);

      buffer.storeMessage(message('a', '2', receivedOn: start.add(Duration(seconds: 3))));
      buffer.storeMessage(message('a', '3', receivedOn: start.add(Duration(seconds: 15))));

      expect(groups.length, 2);
      expect(groups.first.messages.length, 1);
      expect(groups.last.messages.length, 2);
    });
  });

  group('MQTTMessageBuffer tree', () {
    test('builds one node per topic level and counts messages', () {
      buffer.storeMessage(message('home/kitchen/temp', '1'));
      buffer.storeMessage(message('home/kitchen/temp', '2'));
      buffer.storeMessage(message('home/garage', '3'));

      var home = buffer.getMessagesTree(null).children.single;
      expect(home.topicLevelName, 'home');
      expect(home.children.map((x) => x.topicLevelName), ['kitchen', 'garage']);

      var temp = home.children.first.children.single;
      expect(temp.topicLevelName, 'temp');
      expect(temp.messageCount, 2);
      expect(temp.message!.payload, toPayload('2'));
    });

    test('filtered tree keeps matching branches only', () {
      buffer.storeMessage(message('home/kitchen/temp', '1'));
      buffer.storeMessage(message('office/printer', '2'));

      var tree = buffer.getMessagesTree('kitchen');

      expect(tree.children.map((x) => x.topicLevelName), ['home']);
      expect(tree.children.single.children.single.topicLevelName, 'kitchen');
    });

    test('filtering does not change the full tree', () {
      buffer.storeMessage(message('home/kitchen/temp', '1'));
      buffer.storeMessage(message('office/printer', '2'));

      buffer.getMessagesTree('kitchen');

      expect(buffer.getMessagesTree(null).children.length, 2);
      expect(buffer.getMessagesTree('  ').children.length, 2);
    });
  });
}
