import 'dart:async';
import 'dart:typed_data';
import 'package:clock/clock.dart';
import 'package:event/event.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/engine/conformance_checker.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/mqtt/side_connection.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';

enum CheckState { idle, connecting, running, reconnecting }

class CheckErrorEventArgs extends EventArgs {
  final String message;

  CheckErrorEventArgs(this.message);
}

// Checks the messages of the broker against the documentation (doc/documentation-design.md §7), on its own
// connection like discovery (T9) and without publishing (T12). The findings stay after the check stopped, until the
// next check or the project closes. The CLI runs it without the app's projects.
class CheckService {
  // a retained message within this time after subscribing is part of the retained snapshot
  static const Duration snapshotWindow = Duration(seconds: 2);
  static const Duration statsInterval = Duration(seconds: 1);

  final ProjectManager? _projectManager;
  final MqttAdapter Function() _connectionFactory;
  final bool reconnect;

  final stateChangedEvent = Event();
  // every statsInterval while checking: new findings, stale topics, counts
  final statsChangedEvent = Event();
  // the check stopped; checker holds the findings
  final finishedEvent = Event();
  final errorEvent = Event<CheckErrorEventArgs>();

  CheckState _state = CheckState.idle;
  ConformanceChecker? _checker;
  SideConnection? _connection;
  List<String> _filters = [];
  bool _isMqtt5 = true;
  Stopwatch? _stopwatch;
  int _subscribedAtMicros = 0;
  Timer? _statsTimer;
  Timer? _stopTimer;
  bool _lostConnection = false;

  CheckService({MqttAdapter Function()? connectionFactory, bool withProjects = true, this.reconnect = true})
      : _connectionFactory = connectionFactory ?? MqttAdapter.new,
        _projectManager = withProjects ? GetIt.I.get<ProjectManager>() : null {
    _projectManager?.projectClosedEvent.subscribe(_onProjectClosed);
  }

  void dispose() {
    _projectManager?.projectClosedEvent.unsubscribe(_onProjectClosed);
    _cancel();
  }

  CheckState get state => _state;

  bool get isRunning => _state != CheckState.idle;

  ConformanceChecker? get checker => _checker;

  List<String> get filters => List.unmodifiable(_filters);

  Duration get elapsed => _stopwatch?.elapsed ?? Duration.zero;

  int get messages => _checker?.messages ?? 0;

  int get reconnectAttempt => _connection?.reconnectAttempt ?? 0;

  // the connection was lost and reconnect is off, e.g. in the CLI
  bool get lostConnection => _lostConnection;

  // throws when there is nothing to check or the broker can't be reached; nothing runs then.
  // The app checks the open project; the CLI passes the documentation and the broker settings.
  Future<void> start(
      {TopicDocumentation? documentation, MqttSettings? settings, List<String>? filters, Duration? duration}) async {
    if (isRunning) {
      throw StateError('A check is already running');
    }
    var project = _projectManager?.currentProject;
    var checked = documentation ?? project?.documentation;
    var broker = settings ?? (project == null ? null : SideConnection.settingsFor(project.mqttSettings, 'chk'));
    if (checked == null || broker == null) {
      throw StateError('A check needs a documentation and a broker');
    }
    _filters = filters ?? ConformanceChecker.filtersOf(checked);
    if (_filters.isEmpty) {
      throw ArgumentError('There is nothing to check: no documented topic and no discovery filter');
    }
    _isMqtt5 = broker.isMqtt5;
    _lostConnection = false;
    _checker = ConformanceChecker(checked, isMqtt5: _isMqtt5, ignoreFilters: checked.ignoreFilters);
    _setState(CheckState.connecting);
    var connection = SideConnection(_connectionFactory, reconnect: reconnect);
    try {
      await connection.connect(broker);
    } catch (_) {
      connection.close();
      _checker = null;
      _setState(CheckState.idle);
      rethrow;
    }
    _connection = connection;
    _stopwatch = clock.stopwatch()..start();
    _checker!.start(clock.now());
    connection.messageReceivedEvent.subscribe(_onMessage);
    connection.lostEvent.subscribe(_onLost);
    connection.reconnectingEvent.subscribe(_onReconnecting);
    connection.reconnectedEvent.subscribe(_onReconnected);
    connection.subscribeFailedEvent.subscribe(_onSubscribeFailed);
    connection.listen(_subscribe);
    _statsTimer = Timer.periodic(statsInterval, (_) {
      _checker?.checkStale(clock.now());
      statsChangedEvent.broadcast();
    });
    if (duration != null) {
      _stopTimer = Timer(duration, stop);
    }
    _setState(CheckState.running);
  }

  void stop() {
    if (!isRunning) {
      return;
    }
    _checker?.checkStale(clock.now());
    _closeConnection();
    _stopwatch?.stop();
    _setState(CheckState.idle);
    finishedEvent.broadcast();
  }

  // the findings panel was closed
  void clear() {
    if (!isRunning) {
      _checker = null;
      statsChangedEvent.broadcast();
    }
  }

  void _subscribe(MqttAdapter connection) {
    for (var filter in _filters) {
      // QoS 2 and Retain As Published show the publisher's QoS and retain flag (T10)
      connection.subscribeToTopic(TopicSubscription(filter, MqttQos.exactlyOnce,
          retainAsPublished: _isMqtt5, retainHandling: SubscriptionRetainHandling.sendOnSubscribe));
    }
    _subscribedAtMicros = _stopwatch?.elapsedMicroseconds ?? 0;
  }

  void _onMessage(ReceivedMqttMessage? message) {
    var checker = _checker;
    if (message == null || checker == null || _state != CheckState.running) {
      return;
    }
    var offset = _stopwatch!.elapsedMicroseconds;
    checker.check(
        RecordedMessage(
            offsetMicros: offset,
            topic: message.topicName,
            payload: Uint8List.fromList(message.payload),
            qos: message.qos,
            retain: message.retain,
            snapshot: message.retain && offset - _subscribedAtMicros <= snapshotWindow.inMicroseconds,
            properties: message.properties),
        clock.now());
  }

  void _onLost(EventArgs? _) {
    if (!reconnect) {
      _lostConnection = true;
      stop();
      return;
    }
    _setState(CheckState.reconnecting);
  }

  void _onReconnecting(EventArgs? _) => stateChangedEvent.broadcast();

  void _onReconnected(EventArgs? _) => _setState(CheckState.running);

  void _onSubscribeFailed(SubscribeFailedEventArgs? args) {
    if (args != null) {
      errorEvent.broadcast(CheckErrorEventArgs('${args.topic}: ${args.reason ?? ''}'.trim()));
    }
  }

  void _closeConnection() {
    _statsTimer?.cancel();
    _stopTimer?.cancel();
    var connection = _connection;
    _connection = null;
    if (connection == null) {
      return;
    }
    connection.messageReceivedEvent.unsubscribe(_onMessage);
    connection.lostEvent.unsubscribe(_onLost);
    connection.reconnectingEvent.unsubscribe(_onReconnecting);
    connection.reconnectedEvent.unsubscribe(_onReconnected);
    connection.subscribeFailedEvent.unsubscribe(_onSubscribeFailed);
    try {
      connection.close();
    } catch (_) {
      // the connection is gone either way
    }
  }

  void _cancel() {
    _closeConnection();
    if (_state != CheckState.idle) {
      _setState(CheckState.idle);
    }
  }

  void _onProjectClosed(EventArgs? _) {
    _cancel();
    _checker = null;
  }

  void _setState(CheckState state) {
    _state = state;
    stateChangedEvent.broadcast();
  }
}
