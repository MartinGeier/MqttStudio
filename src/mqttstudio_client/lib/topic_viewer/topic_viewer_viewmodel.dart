import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:mqttstudio/topic_viewer/message_buffer_viewmodel.dart';
import 'package:srx_flutter/srx_flutter.dart';

class TopicViewerViewmodel extends SrxChangeNotifier {
  TopicViewMode _topicViewMode = TopicViewMode.Grouped;
  MessageGroupTimePeriod _groupTimePeriod = MessageGroupTimePeriod.tenSeconds;
  ReceivedMqttMessage? _selectedMessage;
  bool _autoSelect = false;
  late MessageBufferViewmodel msgBufferViewmodel;

  bool get autoSelect => _autoSelect;

  set autoSelect(bool autoSelect) {
    _autoSelect = autoSelect;
    notifyListeners();
  }

  TopicViewerViewmodel() {
    msgBufferViewmodel = GetIt.I.get<ProjectGlobalViewmodel>().messageBufferViewmodel;
    msgBufferViewmodel.addListener(_onMessageReceived);
  }

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

  void _onMessageReceived() {
    var lastMsg = msgBufferViewmodel.getLastMessage();
    if (autoSelect && lastMsg.topicName == _selectedMessage?.topicName) {
      selectedMessage = lastMsg;
    }
  }
}

enum TopicViewMode { Grouped, Sequential }
