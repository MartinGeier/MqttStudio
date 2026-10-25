import 'package:darq/darq.dart';
import 'package:event/event.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/message_viewer/message_viewer.dart';
import 'package:mqttstudio/message_viewer/message_source.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/message_viewer/message_buffer.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/recorder/engine/recorder_service.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:mqttstudio/common/utils/payload_utils.dart';

class MessageViewerViewmodel extends SrxChangeNotifier {
  TopicViewMode _topicViewMode = TopicViewMode.Grouped;
  MessageGroupTimePeriod _groupTimePeriod = MessageGroupTimePeriod.tenSeconds;
  ReceivedMqttMessage? _selectedMessage;
  bool _autoSelect = false;
  // the live MessageViewer, or the messages of a recording in the recorder tab
  late MessageSource _messageViewer;
  String? _filter;
  final _refreshPeriod = 500;
  DateTime _lastRefresh = DateTime.now();

  bool get autoSelect => _autoSelect;

  set autoSelect(bool autoSelect) {
    _autoSelect = autoSelect;
    notifyListeners();
  }

  MessageViewerViewmodel({MessageSource? source}) {
    _messageViewer = source ?? GetIt.I.get<MessageViewer>();
    _messageViewer.messageReceivedEvent.subscribe(_onMessageReceived);
    _messageViewer.topicSubscriptionsChangedEvent.subscribe(_topicSubriptionsChanged);
    _messageViewer.messagesClearedEvent.subscribe(_messagesCleared);
    GetIt.I.get<ProjectManager>().projectClosedEvent.subscribe(_projectClosed);
    _documentation.documentationChangedEvent.subscribe(_documentationChanged);
  }

  @override
  void dispose() {
    // only remove our own handlers, the events are shared with other services and viewmodels
    GetIt.I.get<ProjectManager>().projectClosedEvent.unsubscribe(_projectClosed);
    _documentation.documentationChangedEvent.unsubscribe(_documentationChanged);
    _messageViewer.topicSubscriptionsChangedEvent.unsubscribe(_topicSubriptionsChanged);
    _messageViewer.messageReceivedEvent.unsubscribe(_onMessageReceived);
    _messageViewer.messagesClearedEvent.unsubscribe(_messagesCleared);
    super.dispose();
  }

  ReceivedMqttMessage? get selectedMessage => _selectedMessage;

  DocumentationService get _documentation => GetIt.I.get<DocumentationService>();

  // the documented title of a topic, for the tree viewer's tooltips
  String? documentedTitleOf(String topic) {
    var title = _documentation.match(topic)?.node.title;
    return title == null || title.isEmpty ? null : title;
  }

  void _documentationChanged(EventArgs? _) => notifyListeners();

  MQTTMessageBuffer get messageBuffer => _messageViewer.messageBuffer;

  bool get paused => _messageViewer.paused;

  bool get isLive => _messageViewer.isLive;

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
        .where((x) => double.tryParse(PayloadUtils.safePayloadToString(x.payload)) != null)
        .orderByDescending((x) => x.receivedOn)
        .take(100)
        .select((x, index) =>
            Tuple2<DateTime, double>(x.receivedOn, double.parse(PayloadUtils.safePayloadToString(x.payload))))
        .toList();
  }

  List<String> getValues() {
    var messages = selectedMessage != null
        ? _messageViewer.messageBuffer.getTopicMessages(selectedMessage!.topicName)
        : List<ReceivedMqttMessage>.empty();
    return messages
        .orderByDescending((x) => x.receivedOn)
        .take(1000)
        .select((x, index) => PayloadUtils.safePayloadToString(x.payload))
        .toList();
  }

  num? getMinValue() {
    var messages = selectedMessage != null
        ? _messageViewer.messageBuffer.getTopicMessages(selectedMessage!.topicName)
        : List<ReceivedMqttMessage>.empty();

    var numMessages = messages
        .select((x, _) => double.tryParse(PayloadUtils.safePayloadToString(x.payload)))
        .where((x) => x != null)
        .toList()
        .cast<double>();
    if (numMessages.isEmpty) {
      return null;
    }
    return numMessages.reduce((a, b) => a < b ? a : b);
  }

  num? getMaxValue() {
    var messages = selectedMessage != null
        ? _messageViewer.messageBuffer.getTopicMessages(selectedMessage!.topicName)
        : List<ReceivedMqttMessage>.empty();

    var numMessages = messages
        .select((x, _) => double.tryParse(PayloadUtils.safePayloadToString(x.payload)))
        .where((x) => x != null)
        .toList()
        .cast<double>();
    if (numMessages.isEmpty) {
      return null;
    }
    return numMessages.reduce((a, b) => a > b ? a : b);
  }

  num? getAvgValue() {
    var messages = selectedMessage != null
        ? _messageViewer.messageBuffer.getTopicMessages(selectedMessage!.topicName)
        : List<ReceivedMqttMessage>.empty();

    var numMessages = messages
        .select((x, _) => double.tryParse(PayloadUtils.safePayloadToString(x.payload)))
        .where((x) => x != null)
        .toList()
        .cast<double>();
    if (numMessages.isEmpty) {
      return null;
    }
    return numMessages.average(((x) => x));
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

  bool get canSaveAsRecording => isLive && GetIt.I.get<ProjectManager>().isProjectOpen && messageBuffer.length > 0;

  String get defaultRecordingName => GetIt.I.get<ProjectManager>().currentProject?.name ?? 'Topic viewer';

  // the messages received so far as a recording, with the subscriptions as its filters (doc/recorder-design.md §5.6)
  Future<RecordingInfo> saveAsRecording(String name) {
    var project = GetIt.I.get<ProjectManager>().currentProject!;
    var filters = <String, RecorderFilter>{};
    for (var sub in project.topicSubscriptions) {
      var filter = TopicSubscription.topicFilterOf(sub.topic);
      filters.putIfAbsent(filter, () => RecorderFilter(filter, qos: sub.qos, color: sub.color));
    }
    return GetIt.I.get<RecorderService>().saveMessages(name, messageBuffer.allMessages,
        filters: filters.values.toList(), settings: project.mqttSettings, projectName: project.name);
  }

  void rePublish() {
    assert(_selectedMessage != null);

    GetIt.I.get<MessageViewer>().publishTopic(_selectedMessage!.topicName, _selectedMessage!.payload,
        MqttPayloadType.binary, _selectedMessage!.retain, _selectedMessage!.qos, _selectedMessage!.properties);
  }

  TopicViewMode get topicViewMode => _topicViewMode;

  set groupTimePeriod(MessageGroupTimePeriod value) {
    _groupTimePeriod = value;
    notifyListeners();
  }

  TopicColor getTopicColor(String topicName) {
    return _messageViewer.getTopicColor(topicName);
  }

  MessageViewer get _live => _messageViewer as MessageViewer;

  void addTopicSubscription(TopicSubscription subscription) {
    _live.addTopicSubscription(subscription);
  }

  void removeTopicSubscription(String topic) {
    _live.removeTopicSubscription(topic);
  }

  void tooglePauseTopicSubscription(String topic) {
    _live.tooglePauseTopicSubscription(topic);
  }

  void pauseAllTopics() {
    _live.pauseAllTopics();
  }

  void playAllTopics() {
    _live.playAllTopics();
  }

  void clearMessages() {
    _live.clearMessages();
  }

  // recorded messages are published on the main connection too
  void publishTopic(String topic, dynamic payload, MqttPayloadType payloadType, bool retain,
      [MqttQos qos = MqttQos.atMostOnce]) {
    GetIt.I.get<MessageViewer>().publishTopic(topic, payload, payloadType, retain, qos);
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

  void _topicSubriptionsChanged(EventArgs _) {
    notifyListeners();
  }

  void _messagesCleared(EventArgs _) {
    notifyListeners();
  }

  void _projectClosed(EventArgs _) {
    selectedMessage = null;
  }
}

enum TopicViewMode { Grouped, Tree, Sequential }
