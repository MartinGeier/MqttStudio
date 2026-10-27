import 'dart:async';
import 'package:darq/darq.dart';
import 'package:event/event.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_simple_treeview/flutter_simple_treeview.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/utils/payload_decoder.dart';
import 'package:mqttstudio/message_viewer/message_filter.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
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
import 'package:mqttstudio/protocol/protocol_profile.dart';
import 'package:mqttstudio/protocol/protocol_registry.dart';
import 'package:mqttstudio/protocol/vda5050/fleet_state.dart';
import 'package:mqttstudio/recorder/engine/recorder_service.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:mqttstudio/common/utils/payload_utils.dart';

// an interpretation or none; Expando can't hold null
class _Interpreted {
  final Interpretation? value;

  const _Interpreted(this.value);
}

// what the interpreters may look up: the last message of another topic in the buffer
class _BufferContext implements InterpretationContext {
  final MessageViewerViewmodel viewmodel;

  _BufferContext(this.viewmodel);

  @override
  Object? lastData(String topic) {
    var message = viewmodel.messageBuffer.getLastMessageForTopic(topic);
    return message == null ? null : viewmodel.protocolData(message);
  }
}

class MessageViewerViewmodel extends SrxChangeNotifier {
  TopicViewMode _topicViewMode = TopicViewMode.Grouped;
  MessageGroupTimePeriod _groupTimePeriod = MessageGroupTimePeriod.tenSeconds;
  ReceivedMqttMessage? _selectedMessage;
  bool _autoSelect = false;
  // the live MessageViewer, or the messages of a recording in the recorder tab
  late MessageSource _messageViewer;
  String _filterText = '';
  MessageFilterMode _filterMode = MessageFilterMode.topic;
  bool _filterRegex = false;
  MessageFilter? _filter;
  String? _filterError;
  final _refreshPeriod = 500;
  DateTime _lastRefresh = DateTime.now();
  // the payload decoder chosen per topic in the detail view, for this session only
  final Map<String, PayloadDecoder> _decoders = {};
  final Map<PayloadDecoder, Expando<DecodedPayload>> _decoded = {};
  bool _showChanges = false;
  ReceivedMqttMessage? _markedMessage;
  bool _showTopicStats = true;
  // protocol interpretation (doc/vda5050-design.md §5, §7): per message, topics switched to raw for this session, the
  // chart series chosen per protocol message type and the collapsed sections of the detail view
  final ProtocolRegistry _protocols = ProtocolRegistry.standard();
  Expando<_Interpreted> _interpreted = Expando();
  final Set<String> _rawTopics = {};
  final Map<String, String> _chartSeries = {};
  final Set<String> _collapsedSections = {};
  // the fleet view (doc/vda5050-design.md §8): built from the buffer while the mode is shown, null otherwise
  FleetState<ReceivedMqttMessage>? _fleet;
  bool? _hasRobots;
  String? _fleetMap;
  bool _showZones = true;
  bool _showFleetLegend = true;
  FleetColumn _fleetSortColumn = FleetColumn.robot;
  bool _fleetSortAscending = true;
  // ticks the time since the last message in the tree
  Timer? _statsTimer;
  // lives here because the page creates a new tree viewer widget on every update
  final treeController = TreeController();

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
    _statsTimer?.cancel();
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

  MessageFilter? get filter => _filter;

  String get filterText => _filterText;

  MessageFilterMode get filterMode => _filterMode;

  bool get filterRegex => _filterRegex;

  // why the filter text is invalid; all messages are shown then
  String? get filterError => _filterError;

  void setFilter(String text, {MessageFilterMode? mode, bool? regex}) {
    _filterText = text;
    _filterMode = mode ?? _filterMode;
    _filterRegex = regex ?? _filterRegex;
    try {
      _filter = MessageFilter.create(text, mode: _filterMode, regex: _filterRegex);
      _filterError = null;
    } on FormatException catch (exc) {
      _filter = null;
      _filterError = exc.message;
    }
    notifyListeners();
  }

  PayloadDecoder decoderOf(String topic) => _decoders[topic] ?? PayloadDecoder.auto;

  void setDecoder(String topic, PayloadDecoder decoder) {
    _decoders[topic] = decoder;
    // interpretations were made of the payload decoded the old way
    _interpreted = Expando();
    notifyListeners();
  }

  // ---------- protocol interpretation ----------

  // the profile that recognizes the topic, e.g. VDA 5050
  ProtocolTopic? protocolOf(String topic) => _protocols.match(topic);

  bool isRaw(String topic) => _rawTopics.contains(topic);

  // shows the topic's payload as it is (raw) or interpreted, for this session
  void setRaw(String topic, bool raw) {
    raw ? _rawTopics.add(topic) : _rawTopics.remove(topic);
    notifyListeners();
  }

  // what the message means, null when no profile recognizes it or the topic is switched to raw
  Interpretation? interpret(ReceivedMqttMessage message) =>
      _rawTopics.contains(message.topicName) ? null : interpretAnyway(message);

  // also for a topic switched to raw, e.g. to offer switching back
  Interpretation? interpretAnyway(ReceivedMqttMessage message) {
    var match = _protocols.match(message.topicName);
    if (match == null) {
      return null;
    }
    var cached = _interpreted[message];
    if (cached != null) {
      return cached.value;
    }
    var result = match.profile.interpret(match, protocolData(message), context: _BufferContext(this));
    _interpreted[message] = _Interpreted(result);
    return result;
  }

  // what a profile reads: the decoded data, else the bytes, e.g. Protobuf; the same bytes object for the same message,
  // so profiles can cache what they read from it
  Object? protocolData(ReceivedMqttMessage message) {
    var decoded = decode(message);
    return decoded.hasValue ? decoded.value : decoded.bytes;
  }

  bool isSectionCollapsed(String key) => _collapsedSections.contains(key);

  void toggleSection(String key) {
    _collapsedSections.contains(key) ? _collapsedSections.remove(key) : _collapsedSections.add(key);
    notifyListeners();
  }

  // the chart series of the selected message's type: the chosen one, else the first
  List<String> get chartSeries {
    var message = _selectedMessage;
    return message == null ? [] : interpret(message)?.values.keys.toList() ?? [];
  }

  String? get selectedChartSeries {
    var series = chartSeries;
    if (series.isEmpty) {
      return null;
    }
    var chosen = _chartSeries[_seriesKey(_selectedMessage!)];
    return series.contains(chosen) ? chosen : series.first;
  }

  set selectedChartSeries(String? series) {
    if (_selectedMessage != null && series != null) {
      _chartSeries[_seriesKey(_selectedMessage!)] = series;
      notifyListeners();
    }
  }

  String _seriesKey(ReceivedMqttMessage message) {
    var match = _protocols.match(message.topicName);
    return match == null ? message.topicName : '${match.profile.id}/${match.messageType}';
  }

  // ---------- fleet view ----------

  // the Fleet mode is offered once a robot sent its connection, state or visualization
  bool get canShowFleet => _hasRobots ??= messageBuffer.allMessages.any((message) => _showsRobot(message.topicName));

  bool _showsRobot(String topic) {
    var match = _protocols.match(topic);
    return match != null && FleetState.showsRobot(match);
  }

  FleetState<ReceivedMqttMessage> get fleet {
    var fleet = _fleet;
    if (fleet == null) {
      fleet = _fleet = FleetState();
      for (var message in messageBuffer.allMessages) {
        _addToFleet(fleet, message);
      }
    }
    return fleet;
  }

  bool _addToFleet(FleetState<ReceivedMqttMessage> fleet, ReceivedMqttMessage message) {
    var match = _protocols.match(message.topicName);
    if (match == null) {
      return false;
    }
    var decoded = decode(message);
    return decoded.hasValue && fleet.add(match, decoded.value, message.receivedOn, message);
  }

  // the robot of the selected message, of whatever type
  String? get selectedRobot {
    var message = _selectedMessage;
    var match = message == null ? null : _protocols.match(message.topicName);
    return match == null || fleet.vehicle(match.deviceKey) == null ? null : match.deviceKey;
  }

  // shows the robot's last state in the detail view, else its last message
  void selectRobot(VehicleState<ReceivedMqttMessage> vehicle) {
    selectedMessage = vehicle.stateMessage ??
        messageBuffer.getLastMessageForTopic('${vehicle.deviceKey}/visualization') ??
        vehicle.connectionMessage;
  }

  // the map shown: the chosen one, else the selected robot's, else the one with the most robots
  String? get fleetMap {
    var maps = fleet.maps;
    if (maps.contains(_fleetMap)) {
      return _fleetMap;
    }
    var robot = selectedRobot;
    var robotMap = robot == null ? null : fleet.vehicle(robot)?.position?.mapId;
    return maps.contains(robotMap) ? robotMap : maps.firstOrNull;
  }

  set fleetMap(String? mapId) {
    _fleetMap = mapId;
    notifyListeners();
  }

  bool get showZones => _showZones;

  set showZones(bool value) {
    _showZones = value;
    notifyListeners();
  }

  bool get showFleetLegend => _showFleetLegend;

  set showFleetLegend(bool value) {
    _showFleetLegend = value;
    notifyListeners();
  }

  FleetColumn get fleetSortColumn => _fleetSortColumn;

  bool get fleetSortAscending => _fleetSortAscending;

  void sortFleet(FleetColumn column, bool ascending) {
    _fleetSortColumn = column;
    _fleetSortAscending = ascending;
    notifyListeners();
  }

  List<VehicleState<ReceivedMqttMessage>> get sortedVehicles {
    var now = statsReference;
    Comparable<Object> key(VehicleState<ReceivedMqttMessage> vehicle) => switch (_fleetSortColumn) {
          FleetColumn.robot => vehicle.name,
          FleetColumn.version => vehicle.version,
          FleetColumn.connection => vehicle.connectionState ?? '',
          FleetColumn.mode => vehicle.state?.operatingMode ?? '',
          FleetColumn.driving => vehicle.status.index,
          FleetColumn.charge => vehicle.state?.powerSupply.stateOfCharge ?? -1,
          FleetColumn.order => vehicle.state?.orderId ?? '',
          FleetColumn.errors => vehicle.state?.errors.length ?? 0,
          FleetColumn.requests => vehicle.openRequests,
          FleetColumn.age => vehicle.stateAge(now)?.inMilliseconds ?? 1 << 40,
        };
    var vehicles = fleet.vehicles;
    vehicles.sort((a, b) {
      var result = key(a).compareTo(key(b));
      if (result == 0) {
        result = a.name.compareTo(b.name);
      }
      return _fleetSortAscending ? result : -result;
    });
    return vehicles;
  }

  DecodedPayload decode(ReceivedMqttMessage message) {
    var decoder = decoderOf(message.topicName);
    var cache = _decoded.putIfAbsent(decoder, Expando.new);
    return cache[message] ??= PayloadDecoding.decode(Uint8List.fromList(message.payload), decoder);
  }

  // the detail view highlights what changed since the previous message of the topic
  bool get showChanges => _showChanges;

  set showChanges(bool value) {
    _showChanges = value;
    notifyListeners();
  }

  ReceivedMqttMessage? get previousOfSelected =>
      _selectedMessage == null ? null : messageBuffer.getPreviousMessage(_selectedMessage!);

  // the message the selected one is compared with side by side
  ReceivedMqttMessage? get markedMessage => _markedMessage;

  void markForCompare() {
    _markedMessage = _selectedMessage;
    notifyListeners();
  }

  void clearMark() {
    _markedMessage = null;
    notifyListeners();
  }

  bool canEditPayload(ReceivedMqttMessage message) => PayloadDecoding.isUtf8(message.payload);

  bool get showTopicStats => _showTopicStats;

  set showTopicStats(bool value) {
    _showTopicStats = value;
    _updateStatsTimer();
    notifyListeners();
  }

  // live topics are measured until now, recorded ones until the last message of the recording
  DateTime get statsReference => isLive ? DateTime.now() : messageBuffer.getLastMessage()?.receivedOn ?? DateTime.now();

  void _updateStatsTimer() {
    // the fleet view's ages tick too
    var needed = isLive &&
        ((_showTopicStats && _topicViewMode == TopicViewMode.Tree) || _topicViewMode == TopicViewMode.Fleet);
    if (needed && _statsTimer == null) {
      _statsTimer = Timer.periodic(Duration(seconds: 1), (_) {
        if (messageBuffer.length > 0) {
          notifyListeners();
        }
      });
    } else if (!needed) {
      _statsTimer?.cancel();
      _statsTimer = null;
    }
  }

  static Key treeKeyOf(String topic) => ValueKey<String>('topic:$topic');

  void expandAll() {
    treeController.expandAll();
    notifyListeners();
  }

  void collapseAll() {
    treeController.collapseAll();
    notifyListeners();
  }

  void expandBranch(String topic) => _setBranchExpanded(topic, true);

  void collapseBranch(String topic) => _setBranchExpanded(topic, false);

  void _setBranchExpanded(String topic, bool expanded) {
    var node = messageBuffer.findNode(topic);
    if (node == null) {
      return;
    }
    void visit(MessageNode node, String path) {
      expanded ? treeController.expandNode(treeKeyOf(path)) : treeController.collapseNode(treeKeyOf(path));
      for (var child in node.children) {
        visit(child, '$path/${child.topicLevelName}');
      }
    }

    visit(node, topic);
    notifyListeners();
  }

  // subscriptions and the retained messages can only be changed for live messages of an open project
  bool get canChangeSubscriptions => isLive && GetIt.I.get<ProjectManager>().isProjectOpen;

  bool get isConnected => GetIt.I.get<MqttAdapter>().isConnected();

  static String branchFilterOf(String topic) => '$topic/#';

  // the subscriptions whose topics all lie in the branch, those can be removed for it
  List<TopicSubscription> subscriptionsInBranch(String topic) => _messageViewer.topicSubscriptions
      .where((sub) => RecorderRules.covers(branchFilterOf(topic), TopicSubscription.topicFilterOf(sub.topic)))
      .toList();

  bool isSubscribed(String topicFilter) => _messageViewer.topicSubscriptions.any((sub) => sub.topic == topicFilter);

  void subscribeToBranch(String topic) {
    _live.addTopicSubscription(TopicSubscription(branchFilterOf(topic), MqttQos.atLeastOnce));
  }

  void unsubscribeFromBranch(String topic) {
    for (var sub in subscriptionsInBranch(topic)) {
      _live.removeTopicSubscription(sub.topic);
    }
  }

  List<Tuple2<DateTime, double>> getChartValues() {
    var messages = selectedMessage != null
        ? _messageViewer.messageBuffer.getTopicMessages(selectedMessage!.topicName)
        : List<ReceivedMqttMessage>.empty();
    // an interpreted topic charts the chosen value of its messages
    var series = selectedChartSeries;
    if (series != null) {
      return messages
          .orderByDescending((x) => x.receivedOn)
          .select((x, _) => (x.receivedOn, interpret(x)?.values[series]))
          .where((x) => x.$2 != null)
          .take(100)
          .select((x, _) => Tuple2<DateTime, double>(x.$1, x.$2!))
          .toList();
    }
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
    if (value != TopicViewMode.Fleet) {
      _fleet = null;
    }
    _updateStatsTimer();
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
    if (_hasRobots == false && _showsRobot(msg.topicName)) {
      _hasRobots = true;
    }
    var fleet = _fleet;
    if (fleet != null) {
      _addToFleet(fleet, msg);
    }
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
    // a recording replaces the buffer and announces it as changed subscriptions: the fleet is built again
    if (!isLive) {
      _fleet = null;
      _hasRobots = null;
      if (_topicViewMode == TopicViewMode.Fleet && !canShowFleet) {
        topicViewMode = TopicViewMode.Sequential;
        return;
      }
    }
    notifyListeners();
  }

  void _messagesCleared(EventArgs _) {
    _markedMessage = null;
    _protocols.clearCache();
    _fleet = null;
    _hasRobots = null;
    notifyListeners();
  }

  void _projectClosed(EventArgs _) {
    _markedMessage = null;
    _fleet = null;
    _hasRobots = null;
    selectedMessage = null;
  }
}

enum TopicViewMode { Grouped, Tree, Sequential, Fleet }

// in the order of the fleet table; what tells whether a robot is fine comes first, the version last
enum FleetColumn { robot, connection, mode, driving, charge, errors, age, order, requests, version }
