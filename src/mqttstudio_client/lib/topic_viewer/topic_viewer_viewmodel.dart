import 'dart:async';
import 'package:darq/darq.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqttstudio/mqtt/mqtt_global_viewmodel.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:mqttstudio/mqtt/mqtt_message_buffer.dart';
import 'package:srx_flutter/srx_flutter.dart';

class TopicViewerViewmodel extends SrxChangeNotifier {
  TopicViewMode _topicViewMode = TopicViewMode.Grouped;
  MessageGroupTimePeriod _groupTimePeriod = MessageGroupTimePeriod.tenSeconds;
  ReceivedMqttMessage? _selectedMessage;
  bool _autoSelect = false;
  StreamSubscription? _closeProjectStreamSubscription;
  late MqttGlobalViewmodel _mqttGlobalViewmodel;
  String? _filter;

  bool get autoSelect => _autoSelect;

  set autoSelect(bool autoSelect) {
    _autoSelect = autoSelect;
    notifyListeners();
  }

  TopicViewerViewmodel() {
    _mqttGlobalViewmodel = GetIt.I.get<MqttGlobalViewmodel>();
    _mqttGlobalViewmodel.addListener(_onMessageReceived);
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
    return selectedMessage != null ? _mqttGlobalViewmodel.messageBuffer.getTopicMessageCount(selectedMessage!.topicName) : 0;
  }

  String? get filter => _filter;
  set filter(String? value) {
    _filter = value;
    notifyListeners();
  }

  List<Tuple2<DateTime, double>> getChartValues() {
    var messages = selectedMessage != null
        ? _mqttGlobalViewmodel.messageBuffer.getTopicMessages(selectedMessage!.topicName)
        : List<ReceivedMqttMessage>.empty();
    return messages
        .where((x) => double.tryParse(MqttPublishPayload.bytesToStringAsString(x.payload)) != null)
        .orderByDescending((x) => x.receivedOn)
        .take(100)
        .select((x, index) => Tuple2<DateTime, double>(x.receivedOn, double.parse(MqttPublishPayload.bytesToStringAsString(x.payload))))
        .toList();
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
      var lastMsg = _mqttGlobalViewmodel.messageBuffer.getLastMessageForTopic(_selectedMessage!.topicName);
      if (lastMsg?.receivedOn != _selectedMessage!.receivedOn) {
        selectedMessage = lastMsg;
      }
    }
  }
}

enum TopicViewMode { Grouped, Tree, Sequential }
