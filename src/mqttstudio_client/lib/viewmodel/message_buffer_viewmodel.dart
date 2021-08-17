import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:srx_flutter/srx_flutter.dart';

class MessageBufferViewmodel extends SrxChangeNotifier {
  List<ReceivedMqttMessage> _buffer = [];
  Map<String, TopicColor> _colors = Map();

  void storeMessage(ReceivedMqttMessage msg) {
    _buffer.insert(0, msg);
    _colors.putIfAbsent(msg.topicName, () => TopicColor.random());
    notifyListeners();
  }

  int get length => _buffer.length;

  List<MessageGroup> getGroupMessages(MessageGroupTimePeriod period) {
    List<MessageGroup> result = [];
    if (_buffer.isEmpty) {
      return result;
    }
    DateTime groupEndTime = _buffer.first.receivedOn;
    DateTime groupBeginTime = calcGroupBeginTime(groupEndTime, period);
    MessageGroup msgGroup = MessageGroup(groupBeginTime);
    result.add(msgGroup);
    for (var msg in _buffer) {
      if (msg.receivedOn.isBefore(groupBeginTime)) {
        groupEndTime = groupBeginTime.subtract(Duration(milliseconds: 1));
        groupBeginTime = calcGroupBeginTime(groupEndTime, period);
        msgGroup = MessageGroup(groupBeginTime);
        result.add(msgGroup);
      }
      msgGroup.messages.add(msg);
    }
    return result;
  }

  TopicColor getTopicColor(String topicName) {
    return _colors[topicName]!;
  }

  DateTime calcGroupBeginTime(DateTime groupEndTime, MessageGroupTimePeriod period) {
    switch (period) {
      case MessageGroupTimePeriod.second:
        return DateTime.fromMicrosecondsSinceEpoch(((groupEndTime.microsecondsSinceEpoch / 1000000).floor()) * 1000000);
      case MessageGroupTimePeriod.tenSeconds:
        return DateTime.fromMicrosecondsSinceEpoch(((groupEndTime.microsecondsSinceEpoch / 1000000 / 10).floor()) * 1000000 * 10);
      case MessageGroupTimePeriod.minute:
        return DateTime.fromMicrosecondsSinceEpoch(((groupEndTime.microsecondsSinceEpoch / 1000000 / 60).floor()) * 1000000 * 60);
      case MessageGroupTimePeriod.hour:
        return DateTime.fromMicrosecondsSinceEpoch(((groupEndTime.microsecondsSinceEpoch / 1000000 / 3600).floor()) * 1000000 * 3600);
    }
  }
}

class MessageGroup {
  final List<ReceivedMqttMessage> messages = [];
  final DateTime beginOfPeriod;

  MessageGroup(this.beginOfPeriod);
}

enum MessageGroupTimePeriod { second, tenSeconds, minute, hour }
