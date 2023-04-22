import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:darq/darq.dart';

class MessageBufferViewmodel extends SrxChangeNotifier {
  final _refreshPeriod = 500;
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

  MessageNode get messagesTree => _messagesTree;

  void pause() {
    paused = true;
    notifyListeners();
  }

  void play() {
    paused = false;
    notifyListeners();
  }

  List<ReceivedMqttMessage> getMessages() {
    return _buffer.take(500).toList();
  }

  ReceivedMqttMessage? getLastMessage() {
    return _buffer.isEmpty ? null : _buffer.first;
  }

  int getTopicMessageCount(String topicName) {
    return _buffer.count((x) => x.topicName == topicName);
  }

  List<MessageGroup> getGroupMessages(MessageGroupTimePeriod period) {
    if (period == _currentPeriod && _groupedMessages.isNotEmpty) {
      return _groupedMessages;
    }

    _groupedMessages = [];
    if (_buffer.isEmpty) {
      return _groupedMessages;
    }
    DateTime groupEndTime = _calcGroupEndTime(_buffer.first.receivedOn, period);
    DateTime groupBeginTime = _calcGroupBeginTime(groupEndTime, period);
    MessageGroup msgGroup = MessageGroup(groupBeginTime);
    _groupedMessages.add(msgGroup);
    for (var msg in _buffer) {
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
      }
    }
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
  int messageCount = 1;
  final List<MessageNode> children = [];

  MessageNode(this.topicLevelName, this.message);

  void messageReceived(msg) {
    message = msg;
    messageCount++;
  }
}
