import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:mqttstudio/project/message_buffer_viewmodel.dart';
import 'package:srx_flutter/srx_flutter.dart';

class TopicViewerViewmodel extends SrxChangeNotifier {
  TopicViewMode _topicViewMode = TopicViewMode.Grouped;
  MessageGroupTimePeriod _groupTimePeriod = MessageGroupTimePeriod.tenSeconds;
  ReceivedMqttMessage? _selectedMessage;
  bool _autoSelect = false;
  StreamSubscription? _closeProjectStreamSubscription;
  late MessageBufferViewmodel _msgBufferViewmodel;

  bool get autoSelect => _autoSelect;

  set autoSelect(bool autoSelect) {
    _autoSelect = autoSelect;
    notifyListeners();
  }

  TopicViewerViewmodel() {
    _msgBufferViewmodel = GetIt.I.get<ProjectGlobalViewmodel>().messageBufferViewmodel;
    _msgBufferViewmodel.addListener(_onMessageReceived);
    _closeProjectStreamSubscription =
        GetIt.I.get<ProjectGlobalViewmodel>().closeProjectStreamController.stream.listen((_) => selectedMessage = null);
  }

  @override
  void dispose() {
    super.dispose();
    _closeProjectStreamSubscription?.cancel();
  }

  ReceivedMqttMessage? get selectedMessage => _selectedMessage;

  int getSelectedMessageCount() {
    return selectedMessage != null ? _msgBufferViewmodel.getTopicMessageCount(selectedMessage!.topicName) : 0;
  }

  set selectedMessage(ReceivedMqttMessage? selectedMessage) {
    _selectedMessage = selectedMessage;
    notifyListeners();
  }

  set topicViewMode(TopicViewMode value) {
    _topicViewMode = value;
    notifyListeners();
  }

  void clearRetainedTopic() {
    assert(_selectedMessage?.retain ?? false);

    GetIt.I.get<ProjectGlobalViewmodel>().publishTopic(_selectedMessage!.topicName, '', MqttPayloadType.string, true);
  }

  void rePublish() {
    assert(_selectedMessage != null);

    GetIt.I.get<ProjectGlobalViewmodel>().publishTopic(
        _selectedMessage!.topicName, _selectedMessage!.payload, MqttPayloadType.binary, _selectedMessage!.retain, _selectedMessage!.qos);
  }

  TopicViewMode get topicViewMode => _topicViewMode;

  set groupTimePeriod(MessageGroupTimePeriod value) {
    _groupTimePeriod = value;
    notifyListeners();
  }

  MessageGroupTimePeriod get groupTimePeriod => _groupTimePeriod;

  void _onMessageReceived() {
    if (autoSelect && _selectedMessage != null) {
      var lastMsg = _msgBufferViewmodel.getLastMessageForTopic(_selectedMessage!.topicName);
      if (lastMsg?.receivedOn != _selectedMessage!.receivedOn) {
        selectedMessage = lastMsg;
      }
    }
  }
}

enum TopicViewMode { Grouped, Tree, Sequential }
