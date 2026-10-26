import 'package:mqttstudio/message_viewer/message_filter.dart';
import 'package:mqttstudio/message_viewer/topic_stats.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:darq/darq.dart';

// Stores all received messages as sequential list and as hierarchy. Offers methods to get and filter messages.
class MQTTMessageBuffer {
  final _maxDisplayMessages = 2000; // this is the maximum number of messages returned by the methods called by the view. We need to
  // limit the number of messages for performance reasons

  List<ReceivedMqttMessage> _buffer = [];
  MessageGroupTimePeriod? _currentPeriod;
  List<MessageGroup> _groupedMessages = [];
  MessageNode _messagesTree = MessageNode('', null);

  void storeMessage(ReceivedMqttMessage msg) {
    _buffer.insert(0, msg);
    _addToLastMessageGroup(msg);
    _updateMessagesTree(msg, _messagesTree, 0);
  }

  // replaces the content with the given messages, oldest first, in one go instead of one insert per message
  void storeAll(List<ReceivedMqttMessage> messages) {
    clear();
    _currentPeriod = null;
    _buffer = List.of(messages.reversed);
    for (var msg in messages) {
      _updateMessagesTree(msg, _messagesTree, 0);
    }
  }

  int get length => _buffer.length;

  // every stored message, oldest first, without the display limit
  List<ReceivedMqttMessage> get allMessages => List.of(_buffer.reversed);

  MessageNode getMessagesTree(MessageFilter? filter) {
    if (filter == null) {
      return _messagesTree;
    }

    // create a filtered copy of the messages tree
    return _getFilteredMessagesTree(filter, _messagesTree, '') ?? MessageNode('', null);
  }

  List<ReceivedMqttMessage> getMessages(MessageFilter? filter) {
    if (filter == null) {
      return _buffer.take(_maxDisplayMessages).toList();
    } else {
      return _buffer.where(filter.matches).take(_maxDisplayMessages).toList();
    }
  }

  ReceivedMqttMessage? getLastMessage() {
    return _buffer.isEmpty ? null : _buffer.first;
  }

  ReceivedMqttMessage? getLastMessageForTopic(String topic) {
    return _buffer.isEmpty ? null : _buffer.firstWhereOrDefault((value) => value.topicName == topic);
  }

  int getTopicMessageCount(String topicName) {
    return _buffer.count((x) => x.topicName == topicName);
  }

  List<ReceivedMqttMessage> getTopicMessages(String topicName) {
    return _buffer.where((x) => x.topicName == topicName).toList();
  }

  // the message received on the same topic before the given one, null for the first one
  ReceivedMqttMessage? getPreviousMessage(ReceivedMqttMessage message) {
    var index = _buffer.indexWhere((x) => identical(x, message));
    if (index < 0) {
      return null;
    }
    for (var i = index + 1; i < _buffer.length; i++) {
      if (_buffer[i].topicName == message.topicName) {
        return _buffer[i];
      }
    }
    return null;
  }

  // the node of a topic or topic level, null when no message arrived below it
  MessageNode? findNode(String topic) {
    var node = _messagesTree;
    for (var level in topic.split('/')) {
      var child = node.children.firstWhereOrDefault((x) => x.topicLevelName == level);
      if (child == null) {
        return null;
      }
      node = child;
    }
    return node;
  }

  List<MessageGroup> getGroupMessages(MessageGroupTimePeriod period, MessageFilter? filter) {
    _groupedMessages = [];
    if (_buffer.isEmpty) {
      return _groupedMessages;
    }

    var messages = getMessages(filter);
    if (messages.isEmpty) {
      return _groupedMessages;
    }

    DateTime groupEndTime = _calcGroupEndTime(messages.first.receivedOn, period);
    DateTime groupBeginTime = _calcGroupBeginTime(groupEndTime, period);
    MessageGroup msgGroup = MessageGroup(groupBeginTime);
    _groupedMessages.add(msgGroup);
    for (var msg in messages) {
      if (msg.receivedOn.isBefore(groupBeginTime)) {
        groupEndTime = _calcGroupEndTime(msg.receivedOn, period);
        groupBeginTime = _calcGroupBeginTime(groupEndTime, period);
        msgGroup = MessageGroup(groupBeginTime);
        _groupedMessages.add(msgGroup);
      }
      msgGroup.messages.add(msg);
    }

    _currentPeriod = period;
    return _groupedMessages;
  }

  void clear() {
    _buffer.clear();
    _groupedMessages.clear();
    _messagesTree.children.clear();
  }

  void _addToLastMessageGroup(ReceivedMqttMessage msg) {
    if (_currentPeriod == null) {
      return;
    }

    DateTime groupEndTime = _calcGroupEndTime(msg.receivedOn, _currentPeriod!);
    DateTime groupBeginTime = _calcGroupBeginTime(groupEndTime, _currentPeriod!);
    MessageGroup msgGroup = MessageGroup(groupBeginTime);
    if (_groupedMessages.isEmpty || _groupedMessages.first.beginOfPeriod.isBefore(groupBeginTime)) {
      msgGroup.messages.add(msg);
      _groupedMessages.insert(0, msgGroup);
    } else {
      _groupedMessages.first.messages.insert(0, msg);
    }

    if (_groupedMessages.fold<int>(0, (previousValue, element) => previousValue + element.messages.length) > _maxDisplayMessages) {
      _groupedMessages.removeLast();
    }
  }

  DateTime _calcGroupEndTime(DateTime lastEntryTime, MessageGroupTimePeriod period) {
    switch (period) {
      case MessageGroupTimePeriod.second:
        return DateTime.fromMicrosecondsSinceEpoch(((lastEntryTime.microsecondsSinceEpoch / 1000000).ceil()) * 1000000);
      case MessageGroupTimePeriod.tenSeconds:
        return DateTime.fromMicrosecondsSinceEpoch(((lastEntryTime.microsecondsSinceEpoch / 1000000 / 10).ceil()) * 1000000 * 10);
      case MessageGroupTimePeriod.minute:
        return DateTime.fromMicrosecondsSinceEpoch(((lastEntryTime.microsecondsSinceEpoch / 1000000 / 60).ceil()) * 1000000 * 60);
      case MessageGroupTimePeriod.hour:
        return DateTime.fromMicrosecondsSinceEpoch(((lastEntryTime.microsecondsSinceEpoch / 1000000 / 3600).ceil()) * 1000000 * 3600);
    }
  }

  DateTime _calcGroupBeginTime(DateTime groupEndTime, MessageGroupTimePeriod period) {
    switch (period) {
      case MessageGroupTimePeriod.second:
        return DateTime.fromMicrosecondsSinceEpoch((((groupEndTime.microsecondsSinceEpoch - 1) / 1000000).floor()) * 1000000);
      case MessageGroupTimePeriod.tenSeconds:
        return DateTime.fromMicrosecondsSinceEpoch((((groupEndTime.microsecondsSinceEpoch - 1) / 1000000 / 10).floor()) * 1000000 * 10);
      case MessageGroupTimePeriod.minute:
        return DateTime.fromMicrosecondsSinceEpoch((((groupEndTime.microsecondsSinceEpoch - 1) / 1000000 / 60).floor()) * 1000000 * 60);
      case MessageGroupTimePeriod.hour:
        return DateTime.fromMicrosecondsSinceEpoch((((groupEndTime.microsecondsSinceEpoch - 1) / 1000000 / 3600).floor()) * 1000000 * 3600);
    }
  }

  void _updateMessagesTree(ReceivedMqttMessage msg, MessageNode rootNode, int level) {
    var topicLevels = msg.topicName.split('/');

    var targetNode = rootNode.children.trySingleWhereOrDefault((x) => x.topicLevelName == topicLevels[level]);
    if (targetNode != null) {
      if (topicLevels.length > level + 1) {
        _updateMessagesTree(msg, targetNode, level + 1);
      } else {
        targetNode.messageReceived(msg);
      }
    } else {
      var newNode = MessageNode(topicLevels[level], msg);
      rootNode.children.add(newNode);
      if (topicLevels.length > level + 1) {
        _updateMessagesTree(msg, newNode, level + 1);
      } else {
        newNode.messageReceived(msg);
      }
    }
  }

  // Keeps the topics that match and the levels above them. Payload filters test the last message of a topic.
  MessageNode? _getFilteredMessagesTree(MessageFilter filter, MessageNode node, String topicPath) {
    var newNode = node.clone();
    for (var childNode in node.children) {
      var childPath = topicPath.isEmpty ? childNode.topicLevelName : '$topicPath/${childNode.topicLevelName}';
      var clonedChild = _getFilteredMessagesTree(filter, childNode, childPath);
      if (clonedChild != null) {
        newNode.children.add(clonedChild);
      }
    }

    var matches = node.isTopic &&
        (filter.filtersPayload ? filter.matches(node.message!) : filter.matchesTopic(topicPath));
    return matches || newNode.children.isNotEmpty ? newNode : null;
  }
}

class MessageGroup {
  final List<ReceivedMqttMessage> messages = [];
  final DateTime beginOfPeriod;

  MessageGroup(this.beginOfPeriod);
}

enum MessageGroupTimePeriod { second, tenSeconds, minute, hour }

class MessageNode {
  String topicLevelName;
  // the last message of the topic; for a level without messages of its own the first message below it
  ReceivedMqttMessage? message;
  int messageCount = 0;
  final List<MessageNode> children = [];
  // shared with the clones of a filtered tree
  TopicStats stats = TopicStats();

  MessageNode(this.topicLevelName, this.message);

  // false for a topic level that only has topics below it
  bool get isTopic => messageCount > 0;

  void messageReceived(ReceivedMqttMessage msg) {
    message = msg;
    messageCount++;
    stats.add(msg.receivedOn, msg.payload.length, retained: msg.retain);
  }

  MessageNode clone() {
    var newNode = MessageNode(topicLevelName, message);
    newNode.messageCount = messageCount;
    newNode.stats = stats;
    return newNode;
  }
}
