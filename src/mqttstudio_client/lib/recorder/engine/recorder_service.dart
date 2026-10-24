import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:clock/clock.dart';
import 'package:event/event.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/format/recording_writer.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recorder_config.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/model/recording_summary.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:uuid/uuid.dart';

enum RecorderState { idle, connecting, recording, reconnecting, stopping }

enum RecordingStopReason { user, duration, maxMessages, maxBytes, projectClosed, writeError }

class RecordingFinishedEventArgs extends EventArgs {
  final RecordingInfo? info;
  final RecordingStopReason reason;

  RecordingFinishedEventArgs(this.info, this.reason);
}

class RecorderErrorEventArgs extends EventArgs {
  final String message;

  RecorderErrorEventArgs(this.message);
}

// Records the messages of the configured filters into the recordings library (doc/recorder-design.md §5). It uses
// its own MQTT connection (R6), so the topic viewer's subscriptions and the CONNECT button don't affect it, and
// reconnects on its own (R7). A recording belongs to the open project: closing the project stops it (R16).
class RecorderService {
  // a retained message within this time after subscribing is part of the retained snapshot (MQTT 5, §5.2)
  static const Duration snapshotWindow = Duration(seconds: 2);
  static const Duration flushInterval = Duration(seconds: 1);
  static const List<Duration> reconnectDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  final RecordingLibrary library;
  final MqttAdapter Function() _connectionFactory;
  final Future<String> Function() _appVersion;
  final Duration statsInterval;
  final _projectManager = GetIt.I.get<ProjectManager>();

  // asked before the project closes while recording; true lets it close and stops the recording
  Future<bool> Function()? confirmStopOnClose;

  final stateChangedEvent = Event();
  // raised at most once per statsInterval while recording
  final statsChangedEvent = Event();
  final finishedEvent = Event<RecordingFinishedEventArgs>();
  final errorEvent = Event<RecorderErrorEventArgs>();

  RecorderState _state = RecorderState.idle;
  RecorderConfig? _config;
  List<RecorderFilter> _filters = [];
  MqttSettings? _settings;
  MqttAdapter? _connection;
  RecordingWriter? _writer;
  Stopwatch? _stopwatch;
  int _subscribedAtMicros = 0;
  int _received = 0;
  int _excluded = 0;
  int _reconnectAttempt = 0;
  final List<Bookmark> _bookmarks = [];
  final Map<String, TopicColor?> _topicColors = {};
  Timer? _flushTimer;
  Timer? _statsTimer;
  Timer? _durationTimer;
  Timer? _reconnectTimer;
  bool _statsDirty = false;
  Future<void>? _flushing;
  Future<RecordingInfo?>? _stopping;

  RecorderService(this.library,
      {MqttAdapter Function()? connectionFactory,
      Future<String> Function()? appVersion,
      this.statsInterval = const Duration(milliseconds: 500)})
      : _connectionFactory = connectionFactory ?? MqttAdapter.new,
        _appVersion = appVersion ?? (() async => '') {
    _projectManager.addCloseGuard(_canCloseProject);
    _projectManager.projectClosedEvent.subscribe(_onProjectClosed);
  }

  void dispose() {
    _projectManager.removeCloseGuard(_canCloseProject);
    _projectManager.projectClosedEvent.unsubscribe(_onProjectClosed);
  }

  RecorderState get state => _state;

  // a session runs: recording, connecting or reconnecting
  bool get isRecording => _state != RecorderState.idle && _state != RecorderState.stopping;

  RecorderConfig? get config => _config;

  // the filters subscribed to, after normalization, plus the exclusions
  List<RecorderFilter> get filters => List.unmodifiable(_filters);

  Duration get elapsed => _stopwatch?.elapsed ?? Duration.zero;

  int get received => _received;

  int get excluded => _excluded;

  int get storedMessages => _writer?.messageCount ?? 0;

  int get storedBytes => _writer?.length ?? 0;

  int get reconnectAttempt => _reconnectAttempt;

  RecordingSummary? get liveSummary => _writer?.summary;

  String? get fileName => _writer?.file.name;

  TopicColor? colorOf(String topic) =>
      _topicColors.putIfAbsent(topic, () => RecorderRules.colorFilterOf(topic, _filters)?.color);

  // throws when the connection or the file cannot be opened; nothing is left behind then
  Future<void> start(RecorderConfig config) async {
    if (_state != RecorderState.idle) {
      throw StateError('A recording is already running');
    }
    var project = _projectManager.currentProject;
    if (project == null) {
      throw StateError('Recording needs an open project');
    }
    _config = config;
    _filters = _withColors(RecorderRules.normalize(config.filters).filters, project.topicSubscriptions);
    _settings = _recorderSettings(project.mqttSettings);
    _received = 0;
    _excluded = 0;
    _reconnectAttempt = 0;
    _bookmarks.clear();
    _topicColors.clear();
    _setState(RecorderState.connecting);

    var connection = _connectionFactory();
    try {
      await connection.connect(_settings!);
      var startedAt = clock.now().toUtc();
      var file = await library.create(config.name, startedAt);
      try {
        _writer = await RecordingWriter.start(
            file,
            RecordingHeader(
              id: const Uuid().v4(),
              startedAt: startedAt,
              filters: _filters.map((filter) => filter.copy()).toList(),
              broker: '${_settings!.hostname}:${_settings!.port}',
              protocol: _settings!.protocolVersion,
              clientId: _settings!.clientId,
              projectName: project.name,
              appVersion: await _appVersion(),
            ));
      } catch (_) {
        library.finishedWriting(file.name);
        await library.store.delete(file.name);
        rethrow;
      }
    } catch (_) {
      connection.disconnect();
      _setState(RecorderState.idle);
      rethrow;
    }

    _connection = connection;
    _stopwatch = clock.stopwatch()..start();
    connection.messageReceivedEvent.subscribe(_onMessage);
    connection.onDisconnectedEvent.subscribe(_onDisconnected);
    connection.subscribeFailedEvent.subscribe(_onSubscribeFailed);
    _subscribe();
    // the elapsed time moves on even when no messages arrive
    _flushTimer = Timer.periodic(flushInterval, (_) {
      _flush();
      statsChangedEvent.broadcast();
    });
    if (config.durationSeconds != null) {
      _durationTimer = Timer(Duration(seconds: config.durationSeconds!), () => _stop(RecordingStopReason.duration));
    }
    _setState(RecorderState.recording);
  }

  Future<RecordingInfo?> stop() => _stop(RecordingStopReason.user);

  void addBookmark(String label) {
    if (isRecording) {
      _bookmarks.add(Bookmark(_stopwatch!.elapsedMicroseconds, label));
      _markStatsDirty();
    }
  }

  List<Bookmark> get bookmarks => List.unmodifiable(_bookmarks);

  Future<RecordingInfo?> _stop(RecordingStopReason reason) {
    if (_state == RecorderState.idle) {
      return Future.value(null);
    }
    return _stopping ??= _finish(reason).whenComplete(() => _stopping = null);
  }

  Future<RecordingInfo?> _finish(RecordingStopReason reason) async {
    _setState(RecorderState.stopping);
    _flushTimer?.cancel();
    _durationTimer?.cancel();
    _reconnectTimer?.cancel();
    _statsTimer?.cancel();
    _statsTimer = null;
    var connection = _connection!;
    connection.messageReceivedEvent.unsubscribe(_onMessage);
    connection.onDisconnectedEvent.unsubscribe(_onDisconnected);
    connection.subscribeFailedEvent.unsubscribe(_onSubscribeFailed);
    connection.disconnect();
    _stopwatch!.stop();

    var writer = _writer!;
    RecordingInfo? info;
    try {
      await _flushing;
      var footer = await writer.finish(
          name: _config!.name, durationMicros: _stopwatch!.elapsedMicroseconds, bookmarks: List.of(_bookmarks));
      info = RecordingInfo(writer.file.name, writer.header, footer, writer.length);
    } catch (exc) {
      reason = RecordingStopReason.writeError;
      errorEvent.broadcast(RecorderErrorEventArgs(exc.toString()));
      try {
        await writer.abandon();
      } catch (_) {
        // the library recovers the file the next time it lists it
      }
    }
    library.finishedWriting(writer.file.name);
    _connection = null;
    _writer = null;
    _setState(RecorderState.idle);
    finishedEvent.broadcast(RecordingFinishedEventArgs(info, reason));
    return info;
  }

  void _subscribe() {
    var isMqtt5 = _settings!.protocolVersion == MqttProtocolVersion.v5;
    for (var filter in _filters.where((filter) => !filter.exclude)) {
      _connection!.subscribeToTopic(TopicSubscription(filter.filter, filter.qos,
          color: filter.color,
          // with MQTT 5 live messages keep the publisher's retain flag
          retainAsPublished: isMqtt5,
          retainHandling:
              _config!.recordRetainedSnapshot ? SubscriptionRetainHandling.sendOnSubscribe : SubscriptionRetainHandling.doNotSend));
    }
    _subscribedAtMicros = _stopwatch!.elapsedMicroseconds;
  }

  void _onMessage(ReceivedMqttMessage? message) {
    if (_state != RecorderState.recording || message == null) {
      return;
    }
    _received++;
    if (!RecorderRules.isRecorded(message.topicName, _filters)) {
      _excluded++;
      _markStatsDirty();
      return;
    }
    var offset = _stopwatch!.elapsedMicroseconds;
    var writer = _writer!;
    var snapshot = message.retain && !writer.summary.perTopic.containsKey(message.topicName) && _isSnapshotTime(offset);
    if (snapshot && !_config!.recordRetainedSnapshot) {
      return;
    }
    var payload = Uint8List.fromList(message.payload);
    var maxPayload = _config!.maxPayloadBytes;
    var truncated = maxPayload != null && payload.length > maxPayload;
    writer.addMessage(RecordedMessage(
      offsetMicros: offset,
      topic: message.topicName,
      payload: truncated ? Uint8List.sublistView(payload, 0, maxPayload) : payload,
      payloadLength: payload.length,
      qos: message.qos,
      retain: message.retain,
      snapshot: snapshot,
      truncated: truncated,
      properties: message.properties,
    ));
    _markStatsDirty();
    if (writer.needsFlush) {
      _flush();
    }
    _checkLimits();
  }

  // MQTT 3.1.1 brokers clear the retain flag of live messages, so a retained message is always from the subscription.
  // MQTT 5 keeps it (retain as published), so only the first message of a topic right after subscribing counts.
  bool _isSnapshotTime(int offsetMicros) =>
      _settings!.protocolVersion == MqttProtocolVersion.v311 ||
      offsetMicros - _subscribedAtMicros <= snapshotWindow.inMicroseconds;

  void _checkLimits() {
    var config = _config!;
    if (config.maxMessages != null && storedMessages >= config.maxMessages!) {
      _stop(RecordingStopReason.maxMessages);
    } else if (storedBytes >= config.maxBytes) {
      _stop(RecordingStopReason.maxBytes);
    }
  }

  void _onDisconnected(EventArgs? _) {
    if (_state != RecorderState.recording) {
      return;
    }
    _writer!.addMarker(RecordingMarker(_stopwatch!.elapsedMicroseconds, RecordingMarker.connectionLost));
    _reconnectAttempt = 0;
    _setState(RecorderState.reconnecting);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    var delay = reconnectDelays[min(_reconnectAttempt, reconnectDelays.length - 1)];
    _reconnectAttempt++;
    _reconnectTimer = Timer(delay, _reconnect);
    stateChangedEvent.broadcast();
  }

  Future<void> _reconnect() async {
    if (_state != RecorderState.reconnecting) {
      return;
    }
    try {
      await _connection!.connect(_settings!);
    } catch (_) {
      if (_state == RecorderState.reconnecting) {
        _scheduleReconnect();
      }
      return;
    }
    if (_state != RecorderState.reconnecting) {
      return;
    }
    _writer!.addMarker(RecordingMarker(_stopwatch!.elapsedMicroseconds, RecordingMarker.reconnected));
    _subscribe();
    _setState(RecorderState.recording);
  }

  void _onSubscribeFailed(SubscribeFailedEventArgs? args) {
    if (args != null && isRecording) {
      errorEvent.broadcast(RecorderErrorEventArgs('${args.topic}: ${args.reason ?? ''}'.trim()));
    }
  }

  void _flush() {
    var writer = _writer;
    if (writer == null || _flushing != null) {
      return;
    }
    _flushing = writer.flush().catchError((Object exc) {
      _stop(RecordingStopReason.writeError);
      errorEvent.broadcast(RecorderErrorEventArgs(exc.toString()));
    }).whenComplete(() => _flushing = null);
  }

  Future<bool> _canCloseProject() async {
    if (!isRecording) {
      return true;
    }
    return await confirmStopOnClose?.call() ?? true;
  }

  void _onProjectClosed(EventArgs? _) {
    if (isRecording) {
      _stop(RecordingStopReason.projectClosed);
    }
  }

  // the project's settings with a client id of its own, so the broker doesn't drop the app's main connection
  static MqttSettings _recorderSettings(MqttSettings settings) {
    var copy = MqttSettings.fromJson(settings.toJson());
    var suffix = Random().nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    copy
      ..clientId = '${settings.clientId}-rec-$suffix'
      ..cleanStart = true
      ..sessionExpiryInterval = 0;
    return copy;
  }

  // include filters take the color of the topic viewer subscription with the same filter, else a random one
  static List<RecorderFilter> _withColors(List<RecorderFilter> filters, List<TopicSubscription> subscriptions) => [
        for (var filter in filters)
          filter.copy()
            ..color = filter.exclude
                ? null
                : filter.color ??
                    subscriptions.where((sub) => sub.topic == filter.filter).map((sub) => sub.color).firstOrNull ??
                    TopicColor.random()
      ];

  void _setState(RecorderState state) {
    _state = state;
    stateChangedEvent.broadcast();
  }

  void _markStatsDirty() {
    _statsDirty = true;
    _statsTimer ??= Timer(statsInterval, () {
      _statsTimer = null;
      if (_statsDirty) {
        _statsDirty = false;
        statsChangedEvent.broadcast();
      }
    });
  }
}
