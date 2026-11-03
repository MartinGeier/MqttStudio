import 'dart:collection';
import 'package:mqttstudio/message_viewer/message_filter.dart';
import 'package:mqttstudio/message_viewer/topic_stats.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:darq/darq.dart';

// Stores the received messages as sequential list, per topic and as hierarchy. Offers methods to get and filter
// messages. Received messages are kept up to maxMessages and maxBytes, after that the oldest are dropped; the tree
// keeps its topics, counts and statistics of everything received.
class MQTTMessageBuffer {
  static const int defaultMaxMessages = 100000;
  static const int defaultMaxBytes = 200 * 1024 * 1024;

  final _maxDisplayMessages = 2000; // this is the maximum number of messages returned by the methods called by the view. We need to
  // limit the number of messages for performance reasons

  final int maxMessages;
  // payload and topic bytes
  final int maxBytes;

  // oldest first
  final ListQueue<ReceivedMqttMessage> _buffer = ListQueue();
  final Map<String, ListQueue<ReceivedMqttMessage>> _byTopic = {};
  int _bytes = 0;
  int _droppedCount = 0;
  final MessageNode _messagesTree = MessageNode('', null);

  MQTTMessageBuffer({this.maxMessages = defaultMaxMessages, this.maxBytes = defaultMaxBytes});

  void storeMessage(ReceivedMqttMessage msg) {
    _add(msg);
    _updateMessagesTree(msg, _messagesTree, 0);
    while (_buffer.length > maxMessages || _bytes > maxBytes) {
      _dropOldest();
    }
  }

  // replaces the content with the given messages, oldest first, in one go. A recording is kept whole, without the
  // limits.
  void storeAll(List<ReceivedMqttMessage> messages) {
    clear();
    for (var msg in messages) {
      _add(msg);
      _updateMessagesTree(msg, _messagesTree, 0);
    }
  }

  int get length => _buffer.length;

  // the messages dropped since the last clear because the limits were reached
  int get droppedCount => _droppedCount;

  // every stored message, oldest first, without the display limit
  List<ReceivedMqttMessage> get allMessages => List.of(_buffer);

  MessageNode getMessagesTree(MessageFilter? filter) {
    if (filter == null) {
      return _messagesTree;
    }

    // create a filtered copy of the messages tree
    return _getFilteredMessagesTree(filter, _messagesTree, null) ?? MessageNode('', null);
  }

  // the topic of a node below the given one, null for the root; a topic like /a/b has the empty first level
  static String topicOf(String? parentTopic, String level) => parentTopic == null ? level : '$parentTopic/$level';

  List<ReceivedMqttMessage> getMessages(MessageFilter? filter) {
    var newestFirst = _newestFirst(_buffer);
    if (filter == null) {
      return newestFirst.take(_maxDisplayMessages).toList();
    } else {
      return newestFirst.where(filter.matches).take(_maxDisplayMessages).toList();
    }
  }

  ReceivedMqttMessage? getLastMessage() {
    return _buffer.isEmpty ? null : _buffer.last;
  }

  ReceivedMqttMessage? getLastMessageForTopic(String topic) {
    var messages = _byTopic[topic];
    return messages == null || messages.isEmpty ? null : messages.last;
  }

  // the messages of the topic still kept, not all that were received
  int getTopicMessageCount(String topicName) {
    return _byTopic[topicName]?.length ?? 0;
  }

  // newest first
  List<ReceivedMqttMessage> getTopicMessages(String topicName) {
    var messages = _byTopic[topicName];
    return messages == null ? [] : _newestFirst(messages).toList();
  }

  // the message received on the same topic before the given one, null for the first one kept
  ReceivedMqttMessage? getPreviousMessage(ReceivedMqttMessage message) {
    var messages = _byTopic[message.topicName];
    if (messages == null) {
      return null;
    }
    // the selected message is usually one of the newest, so search from the end
    for (var i = messages.length - 1; i > 0; i--) {
      if (identical(messages.elementAt(i), message)) {
        return messages.elementAt(i - 1);
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

  // built again on every call, newest group first
  List<MessageGroup> getGroupMessages(MessageGroupTimePeriod period, MessageFilter? filter) {
    var groupedMessages = <MessageGroup>[];
    var messages = getMessages(filter);
    if (messages.isEmpty) {
      return groupedMessages;
    }

    DateTime groupBeginTime = _calcGroupBeginTime(messages.first.receivedOn, period);
    MessageGroup msgGroup = MessageGroup(groupBeginTime);
    groupedMessages.add(msgGroup);
    for (var msg in messages) {
      if (msg.receivedOn.isBefore(groupBeginTime)) {
        groupBeginTime = _calcGroupBeginTime(msg.receivedOn, period);
        msgGroup = MessageGroup(groupBeginTime);
        groupedMessages.add(msgGroup);
      }
      msgGroup.messages.add(msg);
    }

    return groupedMessages;
  }

  void clear() {
    _buffer.clear();
    _byTopic.clear();
    _bytes = 0;
    _droppedCount = 0;
    _messagesTree.children.clear();
  }

  void _add(ReceivedMqttMessage msg) {
    _buffer.addLast(msg);
    _byTopic.putIfAbsent(msg.topicName, ListQueue.new).addLast(msg);
    _bytes += _sizeOf(msg);
  }

  // the oldest message is always the oldest of its topic too
  void _dropOldest() {
    var oldest = _buffer.removeFirst();
    var messages = _byTopic[oldest.topicName]!..removeFirst();
    if (messages.isEmpty) {
      _byTopic.remove(oldest.topicName);
    }
    _bytes -= _sizeOf(oldest);
    _droppedCount++;
  }

  int _sizeOf(ReceivedMqttMessage msg) => msg.payload.length + msg.topicName.length;

  static Iterable<ReceivedMqttMessage> _newestFirst(ListQueue<ReceivedMqttMessage> messages) sync* {
    for (var i = messages.length - 1; i >= 0; i--) {
      yield messages.elementAt(i);
    }
  }

  // A message exactly on a boundary closes the period before it. Hours begin on the local clock's hours, which are
  // not whole hours since the epoch in time zones with a half-hour offset.
  DateTime _calcGroupBeginTime(DateTime receivedOn, MessageGroupTimePeriod period) {
    var micros = receivedOn.microsecondsSinceEpoch - 1;
    switch (period) {
      case MessageGroupTimePeriod.second:
        return DateTime.fromMicrosecondsSinceEpoch((micros / 1000000).floor() * 1000000);
      case MessageGroupTimePeriod.tenSeconds:
        return DateTime.fromMicrosecondsSinceEpoch((micros / 1000000 / 10).floor() * 1000000 * 10);
      case MessageGroupTimePeriod.minute:
        return DateTime.fromMicrosecondsSinceEpoch((micros / 1000000 / 60).floor() * 1000000 * 60);
      case MessageGroupTimePeriod.hour:
        var local = DateTime.fromMicrosecondsSinceEpoch(micros);
        return DateTime(local.year, local.month, local.day, local.hour);
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
  MessageNode? _getFilteredMessagesTree(MessageFilter filter, MessageNode node, String? topicPath) {
    var newNode = node.clone();
    for (var childNode in node.children) {
      var childPath = topicOf(topicPath, childNode.topicLevelName);
      var clonedChild = _getFilteredMessagesTree(filter, childNode, childPath);
      if (clonedChild != null) {
        newNode.children.add(clonedChild);
      }
    }

    var matches = node.isTopic &&
        (filter.filtersPayload ? filter.matches(node.message!) : filter.matchesTopic(topicPath!));
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
