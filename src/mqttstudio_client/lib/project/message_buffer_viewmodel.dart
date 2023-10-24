import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:darq/darq.dart';

class MessageBufferViewmodel extends SrxChangeNotifier {
  final _refreshPeriod = 1000;
  final _maxDisplayMessages = 2000; // this is the maximum number of messages returned be the methods called by the view. We need to
  // limit the number of messages for performance reasons
  bool paused = false;

  List<ReceivedMqttMessage> _buffer = [];
  MessageGroupTimePeriod? _currentPeriod;
  List<MessageGroup> _groupedMessages = [];
  MessageNode _messagesTree = MessageNode('', null);
  DateTime _lastRefresh = DateTime.now();

  // MessageBufferViewmodel() {
  //   Timer.periodic(Duration(milliseconds: _refreshPeriod), _notifyListeners);
  // }

  void storeMessage(ReceivedMqttMessage msg) {
    if (paused) {
      return;
    }

    _buffer.insert(0, msg);
    _addToLastMessageGroup(msg);
    _updateMessagesTree(msg, _messagesTree, 0);

    // limit rebuild frequency
    if (DateTime.now().subtract(Duration(milliseconds: _refreshPeriod)).isAfter(_lastRefresh)) {
      _lastRefresh = DateTime.now();
      notifyListeners();
    }
  }

  int get length => _buffer.length;

  MessageNode getMessagesTree(String? filter) {
    if (filter == null || filter.trim().isEmpty) {
      return _messagesTree;
    }

    // create a filtered copy of the messages tre
    return _getFilteredMessagesTree(filter);
  }

  // called be the view to delay any updating of the view. Used to prevent the view updating during scrolling
  void delayViewUpdate() {
    _lastRefresh = DateTime.now();
  }

  void pause() {
    paused = true;
    notifyListeners();
  }

  void play() {
    paused = false;
    notifyListeners();
  }

  List<ReceivedMqttMessage> getMessages(String? filter) {
    if (filter == null) {
      return _buffer.take(_maxDisplayMessages).toList();
    } else {
      return _buffer.where((x) => x.topicName.toLowerCase().contains(filter.toLowerCase())).take(_maxDisplayMessages).toList();
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

  List<MessageGroup> getGroupMessages(MessageGroupTimePeriod period, String? filter) {
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
    notifyListeners();
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

  MessageNode _getFilteredMessagesTree(String filter) {
    var filtererTree = _cloneMessagesTree();
    _deleteNotMatchingFromMessagesTree(filter, filtererTree);
    return filtererTree;
  }

  MessageNode _cloneMessagesTree([MessageNode? startNode]) {
    if (startNode == null) {
      startNode = _messagesTree;
    }

    var newNode = startNode.clone();
    for (var childNode in startNode.children) {
      newNode.children.add(_cloneMessagesTree(childNode));
    }

    return newNode;
  }

  bool _deleteNotMatchingFromMessagesTree(String filter, MessageNode messagesTree) {
    var match = messagesTree.topicLevelName.toLowerCase().contains(filter.toLowerCase());
    for (int i = messagesTree.children.length - 1; i >= 0; i--) {
      if (!match && _deleteNotMatchingFromMessagesTree(filter, messagesTree.children[i])) {
        messagesTree.children.removeAt(i);
      }
    }

    return messagesTree.children.isEmpty && (!match || messagesTree.messageCount == 0);
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
  ReceivedMqttMessage? message;
  int messageCount = 0;
  final List<MessageNode> children = [];

  MessageNode(this.topicLevelName, this.message);

  void messageReceived(msg) {
    message = msg;
    messageCount++;
  }

  MessageNode clone() {
    var newNode = MessageNode(topicLevelName, message);
    newNode.messageCount = messageCount;
    return newNode;
  }
}
