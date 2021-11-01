import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/topic_viewer/message_buffer_viewmodel.dart';
import 'package:srx_flutter/srx_flutter.dart';

class TopicViewerViewmodel extends SrxChangeNotifier {
  TopicViewMode _topicViewMode = TopicViewMode.Grouped;
  MessageGroupTimePeriod _groupTimePeriod = MessageGroupTimePeriod.tenSeconds;
  ReceivedMqttMessage? _selectedMessage;

  ReceivedMqttMessage? get selectedMessage => _selectedMessage;

  set selectedMessage(ReceivedMqttMessage? selectedMessage) {
    _selectedMessage = selectedMessage;
    notifyListeners();
  }

  set topicViewMode(TopicViewMode value) {
    _topicViewMode = value;
    notifyListeners();
  }

  TopicViewMode get topicViewMode => _topicViewMode;

  set groupTimePeriod(MessageGroupTimePeriod value) {
    _groupTimePeriod = value;
    notifyListeners();
  }

  MessageGroupTimePeriod get groupTimePeriod => _groupTimePeriod;
}

enum TopicViewMode { Grouped, Sequential }
