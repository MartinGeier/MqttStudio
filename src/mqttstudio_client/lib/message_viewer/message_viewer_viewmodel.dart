import 'package:darq/darq.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/message_viewer/message_viewer.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/message_viewer/message_buffer.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:srx_flutter/srx_flutter.dart';

class MessageViewerViewmodel extends SrxChangeNotifier {
  TopicViewMode _topicViewMode = TopicViewMode.Grouped;
  MessageGroupTimePeriod _groupTimePeriod = MessageGroupTimePeriod.tenSeconds;
  ReceivedMqttMessage? _selectedMessage;
  bool _autoSelect = false;
  late MessageViewer _messageViewer;
  String? _filter;
  final _refreshPeriod = 500;
  DateTime _lastRefresh = DateTime.now();

  bool get autoSelect => _autoSelect;

  set autoSelect(bool autoSelect) {
    _autoSelect = autoSelect;
    notifyListeners();
  }

  MessageViewerViewmodel() {
    _messageViewer = GetIt.I.get<MessageViewer>();
    _messageViewer.messageReceivedEvent.subscribe((args) => _onMessageReceived(args));
    _messageViewer.topicSubscriptionsChangedEvent.subscribe((_) => _topicSubriptionsChanged());
    _messageViewer.messagesClearedEvent.subscribe((_) => notifyListeners());
    GetIt.I.get<ProjectManager>().projectClosedEvent.subscribe((_) => selectedMessage = null);
  }

  @override
  void dispose() {
    GetIt.I.get<ProjectManager>().projectClosedEvent.unsubscribeAll();
    _messageViewer.topicSubscriptionsChangedEvent.unsubscribeAll();
    _messageViewer.messageReceivedEvent.unsubscribeAll();
    _messageViewer.messagesClearedEvent.unsubscribeAll();
    super.dispose();
  }

  ReceivedMqttMessage? get selectedMessage => _selectedMessage;

  MQTTMessageBuffer get messageBuffer => _messageViewer.messageBuffer;

  bool get paused => _messageViewer.paused;

  int getSelectedMessageCount() {
    return selectedMessage != null ? _messageViewer.messageBuffer.getTopicMessageCount(selectedMessage!.topicName) : 0;
  }

  String? get filter => _filter;
  set filter(String? value) {
    _filter = value;
    notifyListeners();
  }

  List<Tuple2<DateTime, double>> getChartValues() {
    var messages = selectedMessage != null
        ? _messageViewer.messageBuffer.getTopicMessages(selectedMessage!.topicName)
        : List<ReceivedMqttMessage>.empty();
    return messages
        .where((x) => double.tryParse(MqttPublishPayload.bytesToStringAsString(x.payload)) != null)
        .orderByDescending((x) => x.receivedOn)
        .take(100)
        .select((x, index) => Tuple2<DateTime, double>(x.receivedOn, double.parse(MqttPublishPayload.bytesToStringAsString(x.payload))))
        .toList();
  }

  List<String> getValues() {
    var messages = selectedMessage != null
        ? _messageViewer.messageBuffer.getTopicMessages(selectedMessage!.topicName)
        : List<ReceivedMqttMessage>.empty();
    return messages
        .orderByDescending((x) => x.receivedOn)
        .take(100)
        .select((x, index) => MqttPublishPayload.bytesToStringAsString(x.payload))
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

    GetIt.I.get<MessageViewer>().publishTopic(_selectedMessage!.topicName, '', MqttPayloadType.string, true);
  }

  void rePublish() {
    assert(_selectedMessage != null);

    GetIt.I.get<MessageViewer>().publishTopic(
        _selectedMessage!.topicName, _selectedMessage!.payload, MqttPayloadType.binary, _selectedMessage!.retain, _selectedMessage!.qos);
  }

  TopicViewMode get topicViewMode => _topicViewMode;

  set groupTimePeriod(MessageGroupTimePeriod value) {
    _groupTimePeriod = value;
    notifyListeners();
  }

  TopicColor getTopicColor(String topicName) {
    return _messageViewer.getTopicColor(topicName);
  }

  void addTopicSubscription(TopicSubscription subscription) {
    _messageViewer.addTopicSubscription(subscription);
  }

  void removeTopicSubscription(String topic) {
    _messageViewer.removeTopicSubscription(topic);
  }

  void tooglePauseTopicSubscription(String topic) {
    _messageViewer.tooglePauseTopicSubscription(topic);
  }

  void pauseAllTopics() {
    _messageViewer.pauseAllTopics();
  }

  void playAllTopics() {
    _messageViewer.playAllTopics();
  }

  void clearMessages() {
    _messageViewer.clearMessages();
  }

  void publishTopic(String topic, dynamic payload, MqttPayloadType payloadType, bool retain, [MqttQos qos = MqttQos.atMostOnce]) {
    _messageViewer.publishTopic(topic, payload, payloadType, retain, qos);
  }

  MessageGroupTimePeriod get groupTimePeriod => _groupTimePeriod;

  void _onMessageReceived(ReceivedMqttMessage msg) {
    if (autoSelect && _selectedMessage != null && msg.topicName == _selectedMessage!.topicName) {
      if (msg.receivedOn != _selectedMessage!.receivedOn) {
        selectedMessage = msg;
      }
    }

    // limit rebuild frequency
    if (DateTime.now().subtract(Duration(milliseconds: _refreshPeriod)).isAfter(_lastRefresh)) {
      _lastRefresh = DateTime.now();
      notifyListeners();
    }
  }

  // called by the view to delay any updating of the view. Used to prevent the view updating during scrolling
  void delayViewUpdate() {
    _lastRefresh = DateTime.now();
  }

  _topicSubriptionsChanged() {
    notifyListeners();
  }
}

enum TopicViewMode { Grouped, Tree, Sequential }
