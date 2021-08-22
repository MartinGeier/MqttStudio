import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:srx_flutter/srx_flutter.dart';

class MessageBufferViewmodel extends SrxChangeNotifier {
  List<ReceivedMqttMessage> _buffer = [];
  MessageGroupTimePeriod? _currentPeriod;
  List<MessageGroup> _groupedMessages = [];

  void storeMessage(ReceivedMqttMessage msg) {
    _buffer.insert(0, msg);
    addToLastMessageGroup(msg);

    notifyListeners();
  }

  int get length => _buffer.length;

  List<MessageGroup> getGroupMessages(MessageGroupTimePeriod period) {
    if (period == _currentPeriod && _groupedMessages.isNotEmpty) {
      return _groupedMessages;
    }

    _groupedMessages = [];
    if (_buffer.isEmpty) {
      return _groupedMessages;
    }
    DateTime groupEndTime = calcGroupEndTime(_buffer.first.receivedOn, period);
    DateTime groupBeginTime = calcGroupBeginTime(groupEndTime, period);
    MessageGroup msgGroup = MessageGroup(groupBeginTime);
    _groupedMessages.add(msgGroup);
    for (var msg in _buffer) {
      if (msg.receivedOn.isBefore(groupBeginTime)) {
        groupEndTime = calcGroupEndTime(msg.receivedOn, period);
        groupBeginTime = calcGroupBeginTime(groupEndTime, period);
        msgGroup = MessageGroup(groupBeginTime);
        _groupedMessages.add(msgGroup);
      }
      msgGroup.messages.add(msg);
    }

    _currentPeriod = period;
    return _groupedMessages;
  }

  void addToLastMessageGroup(ReceivedMqttMessage msg) {
    if (_currentPeriod == null) {
      return;
    }

    DateTime groupEndTime = calcGroupEndTime(msg.receivedOn, _currentPeriod!);
    DateTime groupBeginTime = calcGroupBeginTime(groupEndTime, _currentPeriod!);
    MessageGroup msgGroup = MessageGroup(groupBeginTime);
    if (_groupedMessages.isEmpty || _groupedMessages.first.beginOfPeriod.isBefore(groupBeginTime)) {
      msgGroup.messages.add(msg);
      _groupedMessages.insert(0, msgGroup);
    } else {
      _groupedMessages.first.messages.insert(0, msg);
    }
  }

  DateTime calcGroupEndTime(DateTime lastEntryTime, MessageGroupTimePeriod period) {
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

  DateTime calcGroupBeginTime(DateTime groupEndTime, MessageGroupTimePeriod period) {
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
}

class MessageGroup {
  final List<ReceivedMqttMessage> messages = [];
  final DateTime beginOfPeriod;

  MessageGroup(this.beginOfPeriod);
}

enum MessageGroupTimePeriod { second, tenSeconds, minute, hour }
