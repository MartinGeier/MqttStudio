import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:clock/clock.dart';
import 'package:event/event.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/mqtt/side_connection.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/engine/recording_ring.dart';
import 'package:mqttstudio/recorder/format/summary_builder.dart';
import 'package:mqttstudio/recorder/format/recording_writer.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recorder_config.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/model/recording_summary.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:uuid/uuid.dart';

// waiting: connected, the start trigger has not matched yet
enum RecorderState { idle, connecting, waiting, recording, reconnecting, stopping }

enum RecordingStopReason { user, duration, maxMessages, maxBytes, stopCondition, maxSaves, projectClosed, writeError, connectionLost }

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
// With a start trigger it waits and keeps the pre-roll in a RecordingRing; the flight recorder keeps its window there
// and writes a new recording on every save (§5.4, §5.5).
class RecorderService {
  // a retained message within this time after subscribing is part of the retained snapshot (MQTT 5, §5.2)
  static const Duration snapshotWindow = Duration(seconds: 2);
  static const Duration flushInterval = Duration(seconds: 1);

  final RecordingLibrary library;
  final MqttAdapter Function() _connectionFactory;
  final Future<String> Function() _appVersion;
  final Duration statsInterval;
  // null in the CLI, which records without the app's projects
  final ProjectManager? _projectManager;
  // the app reconnects on its own (R7); the CLI only with --reconnect (C4) and stops otherwise
  final bool reconnect;

  // asked before the project closes while recording; true lets it close and stops the recording
  Future<bool> Function()? confirmStopOnClose;

  final stateChangedEvent = Event();
  // raised at most once per statsInterval while recording
  final statsChangedEvent = Event();
  final finishedEvent = Event<RecordingFinishedEventArgs>();
  // the flight recorder wrote a recording and goes on
  final savedEvent = Event<RecordingFinishedEventArgs>();
  final errorEvent = Event<RecorderErrorEventArgs>();

  RecorderState _state = RecorderState.idle;
  RecorderConfig? _config;
  List<RecorderFilter> _filters = [];
  MqttSettings? _settings;
  SideConnection? _connection;
  RecordingWriter? _writer;
  // offset in the session where the recording starts: 0, or the first pre-roll message of a start trigger
  int _writerBase = 0;
  // what arrives between the start trigger and the opened file
  List<Object>? _pending;
  Future<void>? _opening;
  // pre-roll while waiting for the trigger, the window of the flight recorder
  RecordingRing? _ring;
  // statistics of everything received while no file is written
  SummaryBuilder? _sessionSummary;
  DateTime _sessionStartedAt = DateTime.utc(2000);
  String? _projectName;
  String _appVersionText = '';
  final Set<String> _seenTopics = {};
  RecorderState _resumeState = RecorderState.recording;
  Timer? _postRollTimer;
  Timer? _flightSaveTimer;
  Future<void>? _flightWriting;
  int _flightSaves = 0;
  Stopwatch? _stopwatch;
  int _subscribedAtMicros = 0;
  int _received = 0;
  int _excluded = 0;
  final List<Bookmark> _bookmarks = [];
  final Map<String, TopicColor?> _topicColors = {};
  Timer? _flushTimer;
  Timer? _statsTimer;
  Timer? _durationTimer;
  bool _statsDirty = false;
  Future<void>? _flushing;
  Future<RecordingInfo?>? _stopping;

  RecorderService(this.library,
      {MqttAdapter Function()? connectionFactory,
      Future<String> Function()? appVersion,
      this.statsInterval = const Duration(milliseconds: 500),
      ProjectManager? projectManager,
      bool withProjects = true,
      this.reconnect = true})
      : _connectionFactory = connectionFactory ?? MqttAdapter.new,
        _appVersion = appVersion ?? (() async => ''),
        _projectManager = withProjects ? projectManager ?? GetIt.I.get<ProjectManager>() : null {
    _projectManager?.addCloseGuard(_canCloseProject);
    _projectManager?.projectClosedEvent.subscribe(_onProjectClosed);
  }

  void dispose() {
    _projectManager?.removeCloseGuard(_canCloseProject);
    _projectManager?.projectClosedEvent.unsubscribe(_onProjectClosed);
  }

  RecorderState get state => _state;

  // a session runs: recording, connecting or reconnecting
  bool get isRecording => _state != RecorderState.idle && _state != RecorderState.stopping;

  RecorderConfig? get config => _config;

  // the filters subscribed to, after normalization, plus the exclusions
  List<RecorderFilter> get filters => List.unmodifiable(_filters);

  // the length of the recording; while waiting for the trigger the time waited
  Duration get elapsed => Duration(microseconds: max(0, (_stopwatch?.elapsedMicroseconds ?? 0) - _writerBase));

  int get received => _received;

  int get excluded => _excluded;

  int get storedMessages => _writer?.messageCount ?? _ring?.messageCount ?? 0;

  int get storedBytes => _writer?.length ?? _ring?.bytes ?? 0;

  bool get isFlightRecorder => _config?.isFlightRecorder ?? false;

  bool get isWaitingForTrigger =>
      _state == RecorderState.waiting || (_state == RecorderState.reconnecting && _resumeState == RecorderState.waiting);

  // the stop condition matched, the post-roll runs
  bool get isInPostRoll => _postRollTimer != null;

  // SAVE was pressed or saveWhen matched, the post-roll runs
  bool get isSaveScheduled => _flightSaveTimer != null;

  int get flightSaves => _flightSaves;

  // how much the flight recorder holds; shorter than its window at the start or when memory runs out
  Duration get flightSpan => Duration(microseconds: _ring?.spanMicros(_stopwatch?.elapsedMicroseconds ?? 0) ?? 0);

  bool get flightMemoryLimited => _ring?.memoryLimited ?? false;

  bool get canSaveFlight =>
      isFlightRecorder && isRecording && _state != RecorderState.connecting && _flightSaveTimer == null && !_maxSavesReached;

  bool get _maxSavesReached {
    var limit = _config?.flightOptions.maxSaves;
    return limit != null && _flightSaves >= limit;
  }

  int get reconnectAttempt => _connection?.reconnectAttempt ?? 0;

  RecordingSummary? get liveSummary => _writer?.summary ?? _sessionSummary?.summary;

  String? get fileName => _writer?.file.name;

  TopicColor? colorOf(String topic) =>
      _topicColors.putIfAbsent(topic, () => RecorderRules.colorFilterOf(topic, _filters)?.color);

  // throws when the connection or the file cannot be opened; nothing is left behind then
  // The app records from the open project. The CLI passes the broker settings and the project name instead; its
  // settings are used as they are, with the client id it chose.
  Future<void> start(RecorderConfig config, {MqttSettings? settings, String? projectName}) async {
    if (_state != RecorderState.idle) {
      throw StateError('A recording is already running');
    }
    var project = _projectManager?.currentProject;
    if (project == null && settings == null) {
      throw StateError('Recording needs an open project');
    }
    _config = config;
    _filters = _withColors(RecorderRules.normalize(config.filters).filters, project?.topicSubscriptions ?? []);
    _settings = settings ?? SideConnection.settingsFor(project!.mqttSettings, 'rec');
    _projectName = projectName ?? project?.name;
    _received = 0;
    _excluded = 0;
    _writerBase = 0;
    _pending = null;
    _ring = null;
    _sessionSummary = null;
    _flightSaves = 0;
    _bookmarks.clear();
    _topicColors.clear();
    _seenTopics.clear();
    _setState(RecorderState.connecting);

    // without a start trigger the file is created right away, so a problem shows before anything is recorded
    var immediate = !config.isFlightRecorder && config.startWhen == null;
    var connection = SideConnection(_connectionFactory, reconnect: reconnect);
    try {
      await connection.connect(_settings!);
      _appVersionText = await _appVersion();
      _sessionStartedAt = clock.now().toUtc();
      if (immediate) {
        _writer = await _createWriter(config.name, _sessionStartedAt, RecordingOrigin.live);
      }
    } catch (_) {
      connection.close();
      _setState(RecorderState.idle);
      rethrow;
    }

    if (config.isFlightRecorder) {
      var flight = config.flightOptions;
      _ring = RecordingRing(windowMicros: flight.windowSeconds * 1000000, maxBytes: flight.maxMemoryBytes);
      _sessionSummary = SummaryBuilder();
    } else if (!immediate) {
      _ring = RecordingRing(
          windowMicros: config.preRollSeconds * 1000000, maxBytes: FlightRecorderOptions.defaultMaxMemoryBytes);
      _sessionSummary = SummaryBuilder();
    }
    _connection = connection;
    _stopwatch = clock.stopwatch()..start();
    connection.messageReceivedEvent.subscribe(_onMessage);
    connection.lostEvent.subscribe(_onConnectionLost);
    connection.reconnectingEvent.subscribe(_onReconnecting);
    connection.reconnectedEvent.subscribe(_onReconnected);
    connection.subscribeFailedEvent.subscribe(_onSubscribeFailed);
    connection.listen(_subscribe);
    // the elapsed time moves on even when no messages arrive
    _flushTimer = Timer.periodic(flushInterval, (_) {
      _flush();
      _ring?.trim(_stopwatch!.elapsedMicroseconds);
      statsChangedEvent.broadcast();
    });
    if (immediate) {
      _startDurationTimer();
    }
    _setState(immediate || config.isFlightRecorder ? RecorderState.recording : RecorderState.waiting);
  }

  // a new file in the library with its header; nothing is left behind when that fails
  Future<RecordingWriter> _createWriter(String name, DateTime startedAt, RecordingOrigin origin) async {
    var file = await library.create(name, startedAt);
    try {
      return await RecordingWriter.start(
          file,
          RecordingHeader(
            id: const Uuid().v4(),
            startedAt: startedAt,
            filters: _filters.map((filter) => filter.copy()).toList(),
            broker: '${_settings!.hostname}:${_settings!.port}',
            protocol: _settings!.protocolVersion,
            clientId: _settings!.clientId,
            projectName: _projectName,
            appVersion: _appVersionText,
            origin: origin,
          ));
    } catch (_) {
      library.finishedWriting(file.name);
      await library.store.delete(file.name);
      rethrow;
    }
  }

  // the duration counts from the start trigger, not from pressing RECORD
  void _startDurationTimer() {
    var seconds = _config!.durationSeconds;
    if (seconds != null) {
      _durationTimer = Timer(Duration(seconds: seconds), () => _stop(RecordingStopReason.duration));
    }
  }

  Future<RecordingInfo?> stop() => _stop(RecordingStopReason.user);

  // keeps the flight recorder's window plus its post-roll as a new recording
  void saveFlightRecording() => _requestFlightSave();

  // Writes messages the topic viewer holds as a recording (§5.6). It needs no running recorder. The offsets come
  // from the receive times, which the browser only has in milliseconds.
  Future<RecordingInfo> saveMessages(String name, List<ReceivedMqttMessage> messages,
      {required List<RecorderFilter> filters, required MqttSettings settings, String? projectName}) async {
    if (messages.isEmpty) {
      throw StateError('There are no messages to save');
    }
    var sorted = List.of(messages)..sort((a, b) => a.receivedOn.compareTo(b.receivedOn));
    var startedAt = sorted.first.receivedOn.toUtc();
    var file = await library.create(name, startedAt);
    try {
      var writer = await RecordingWriter.start(
          file,
          RecordingHeader(
            id: const Uuid().v4(),
            startedAt: startedAt,
            filters: filters,
            broker: '${settings.hostname}:${settings.port}',
            protocol: settings.protocolVersion,
            clientId: settings.clientId,
            projectName: projectName,
            appVersion: await _appVersion(),
            origin: RecordingOrigin.viewerBuffer,
          ));
      for (var message in sorted) {
        writer.addMessage(RecordedMessage(
          offsetMicros: message.receivedOn.toUtc().difference(startedAt).inMicroseconds,
          topic: message.topicName,
          payload: Uint8List.fromList(message.payload),
          qos: message.qos,
          retain: message.retain,
          properties: message.properties,
        ));
      }
      var duration = sorted.last.receivedOn.toUtc().difference(startedAt).inMicroseconds;
      var footer = await writer.finish(name: name, durationMicros: duration);
      return RecordingInfo(file.name, writer.header, footer, writer.length);
    } catch (_) {
      try {
        await file.close();
      } catch (_) {
        // already closed by the writer
      }
      await library.store.delete(file.name);
      rethrow;
    } finally {
      library.finishedWriting(file.name);
    }
  }

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
    _postRollTimer?.cancel();
    _postRollTimer = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    var connection = _connection!;
    connection.messageReceivedEvent.unsubscribe(_onMessage);
    connection.lostEvent.unsubscribe(_onConnectionLost);
    connection.reconnectingEvent.unsubscribe(_onReconnecting);
    connection.reconnectedEvent.unsubscribe(_onReconnected);
    connection.subscribeFailedEvent.unsubscribe(_onSubscribeFailed);
    connection.close();
    // a save the user asked for is written now instead of after its post-roll
    if (_flightSaveTimer != null) {
      _flightSaveTimer!.cancel();
      await _saveFlight();
    }
    await _flightWriting;
    await _opening;
    _stopwatch!.stop();

    var writer = _writer;
    if (writer == null) {
      // the trigger never matched, or the flight recorder: nothing more to write
      _clearSession();
      _setState(RecorderState.idle);
      finishedEvent.broadcast(RecordingFinishedEventArgs(null, reason));
      return null;
    }
    RecordingInfo? info;
    try {
      await _flushing;
      var footer = await writer.finish(
          name: _config!.name,
          durationMicros: _stopwatch!.elapsedMicroseconds - _writerBase,
          bookmarks: _bookmarksBetween(_writerBase, _stopwatch!.elapsedMicroseconds));
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
    _clearSession();
    _setState(RecorderState.idle);
    finishedEvent.broadcast(RecordingFinishedEventArgs(info, reason));
    return info;
  }

  void _clearSession() {
    _connection = null;
    _writer = null;
    _pending = null;
    _ring = null;
    _flightSaveTimer = null;
  }

  // the bookmarks in a part of the session, counted from its start
  List<Bookmark> _bookmarksBetween(int fromMicros, int toMicros) => [
        for (var bookmark in _bookmarks)
          if (bookmark.offsetMicros >= fromMicros && bookmark.offsetMicros <= toMicros)
            Bookmark(bookmark.offsetMicros - fromMicros, bookmark.label)
      ];

  void _subscribe(MqttAdapter connection) {
    var isMqtt5 = _settings!.protocolVersion == MqttProtocolVersion.v5;
    for (var filter in _filters.where((filter) => !filter.exclude)) {
      connection.subscribeToTopic(TopicSubscription(filter.filter, filter.qos,
          color: filter.color,
          // with MQTT 5 live messages keep the publisher's retain flag
          retainAsPublished: isMqtt5,
          retainHandling:
              _config!.recordRetainedSnapshot ? SubscriptionRetainHandling.sendOnSubscribe : SubscriptionRetainHandling.doNotSend));
    }
    _subscribedAtMicros = _stopwatch!.elapsedMicroseconds;
  }

  void _onMessage(ReceivedMqttMessage? message) {
    if ((_state != RecorderState.recording && _state != RecorderState.waiting) || message == null) {
      return;
    }
    _received++;
    if (!RecorderRules.isRecorded(message.topicName, _filters)) {
      _excluded++;
      _markStatsDirty();
      return;
    }
    var config = _config!;
    var offset = _stopwatch!.elapsedMicroseconds;
    var firstOfTopic = _seenTopics.add(message.topicName);
    var snapshot = message.retain && firstOfTopic && _isSnapshotTime(offset);
    if (snapshot && !config.recordRetainedSnapshot) {
      return;
    }
    var payload = Uint8List.fromList(message.payload);
    var maxPayload = config.maxPayloadBytes;
    var truncated = maxPayload != null && payload.length > maxPayload;
    var recorded = RecordedMessage(
      offsetMicros: offset,
      topic: message.topicName,
      payload: truncated ? Uint8List.sublistView(payload, 0, maxPayload) : payload,
      payloadLength: payload.length,
      qos: message.qos,
      retain: message.retain,
      snapshot: snapshot,
      truncated: truncated,
      properties: message.properties,
    );
    _markStatsDirty();
    if (_state == RecorderState.waiting) {
      _sessionSummary?.add(recorded);
      _ring!.add(recorded);
      if (config.startWhen!.matches(message.topicName, payload)) {
        _trigger(recorded);
      }
    } else if (config.isFlightRecorder) {
      _sessionSummary?.add(recorded);
      _ring!.add(recorded);
      if (config.flightOptions.saveWhen?.matches(message.topicName, payload) ?? false) {
        _requestFlightSave();
      }
    } else {
      _write(recorded);
      if (_postRollTimer == null && (config.stopWhen?.matches(message.topicName, payload) ?? false)) {
        _onStopCondition();
      }
      _checkLimits();
    }
  }

  // a message or a marker of the session into the file, at its offset in the recording
  void _write(Object entry) {
    var writer = _writer;
    if (writer == null) {
      _pending?.add(entry);
      return;
    }
    if (entry is RecordedMessage) {
      writer.addMessage(entry.at(entry.offsetMicros - _writerBase));
    } else if (entry is RecordingMarker) {
      writer.addMarker(RecordingMarker(entry.offsetMicros - _writerBase, entry.kind));
    }
    if (writer.needsFlush) {
      _flush();
    }
  }

  // The start trigger matched: the pre-roll and the trigger message go first, then a triggerFired marker. Offsets
  // count from the first pre-roll message.
  void _trigger(RecordedMessage trigger) {
    var entries = _ring!.drain();
    _ring = null;
    _sessionSummary = null;
    _writerBase = RecordingRing.offsetOf(entries.first);
    _pending = [...entries, RecordingMarker(trigger.offsetMicros, RecordingMarker.triggerFired)];
    _setState(RecorderState.recording);
    _startDurationTimer();
    _opening = _openTriggered().whenComplete(() => _opening = null);
  }

  Future<void> _openTriggered() async {
    try {
      var writer = await _createWriter(
          _config!.name, _sessionStartedAt.add(Duration(microseconds: _writerBase)), RecordingOrigin.live);
      _writer = writer;
      var pending = _pending ?? [];
      _pending = null;
      pending.forEach(_write);
      _markStatsDirty();
      _checkLimits();
    } catch (exc) {
      _pending = null;
      errorEvent.broadcast(RecorderErrorEventArgs(exc.toString()));
      _stop(RecordingStopReason.writeError);
    }
  }

  void _onStopCondition() {
    var postRoll = _config!.postRollSeconds;
    if (postRoll <= 0) {
      _stop(RecordingStopReason.stopCondition);
      return;
    }
    _postRollTimer = Timer(Duration(seconds: postRoll), () => _stop(RecordingStopReason.stopCondition));
    stateChangedEvent.broadcast();
  }

  // triggers during the post-roll belong to the same save
  void _requestFlightSave() {
    if (!isFlightRecorder || _flightSaveTimer != null || _maxSavesReached || !isRecording) {
      return;
    }
    _flightSaveTimer = Timer(Duration(seconds: _config!.flightOptions.postRollSeconds), _saveFlight);
    stateChangedEvent.broadcast();
  }

  // writes what the flight recorder holds into a new recording; the flight recorder goes on
  Future<void> _saveFlight() async {
    _flightSaveTimer = null;
    _ring?.trim(_stopwatch!.elapsedMicroseconds);
    var entries = _ring?.toList() ?? [];
    if (!entries.any((entry) => entry is RecordedMessage)) {
      stateChangedEvent.broadcast();
      return;
    }
    var done = Completer<void>();
    _flightWriting = done.future;
    var base = RecordingRing.offsetOf(entries.first);
    var end = RecordingRing.offsetOf(entries.last);
    var name = '${_config!.name} ${DateFormat('yyyy-MM-dd HH:mm:ss').format(clock.now())}';
    try {
      var writer =
          await _createWriter(name, _sessionStartedAt.add(Duration(microseconds: base)), RecordingOrigin.flightRecorder);
      try {
        for (var entry in entries) {
          if (entry is RecordedMessage) {
            writer.addMessage(entry.at(entry.offsetMicros - base));
          } else if (entry is RecordingMarker) {
            writer.addMarker(RecordingMarker(entry.offsetMicros - base, entry.kind));
          }
        }
        var footer = await writer.finish(name: name, durationMicros: end - base, bookmarks: _bookmarksBetween(base, end));
        _flightSaves++;
        savedEvent.broadcast(RecordingFinishedEventArgs(
            RecordingInfo(writer.file.name, writer.header, footer, writer.length), RecordingStopReason.user));
      } finally {
        library.finishedWriting(writer.file.name);
      }
    } catch (exc) {
      errorEvent.broadcast(RecorderErrorEventArgs(exc.toString()));
    } finally {
      _flightWriting = null;
      done.complete();
    }
    if (_maxSavesReached) {
      _stop(RecordingStopReason.maxSaves);
    }
    stateChangedEvent.broadcast();
  }

  // MQTT 3.1.1 brokers clear the retain flag of live messages, so a retained message is always from the subscription.
  // MQTT 5 keeps it (retain as published), so only the first message of a topic right after subscribing counts.
  bool _isSnapshotTime(int offsetMicros) =>
      _settings!.protocolVersion == MqttProtocolVersion.v311 ||
      offsetMicros - _subscribedAtMicros <= snapshotWindow.inMicroseconds;

  void _checkLimits() {
    if (_writer == null) {
      return;
    }
    var config = _config!;
    if (config.maxMessages != null && storedMessages >= config.maxMessages!) {
      _stop(RecordingStopReason.maxMessages);
    } else if (storedBytes >= config.maxBytes) {
      _stop(RecordingStopReason.maxBytes);
    }
  }

  void _onConnectionLost(EventArgs? _) {
    if (_state != RecorderState.recording && _state != RecorderState.waiting) {
      return;
    }
    _resumeState = _state;
    _addMarker(RecordingMarker.connectionLost);
    if (!reconnect) {
      _stop(RecordingStopReason.connectionLost);
      return;
    }
    _setState(RecorderState.reconnecting);
  }

  // markers go where the messages go: the file, or the ring while waiting and in the flight recorder
  void _addMarker(String kind) {
    var marker = RecordingMarker(_stopwatch!.elapsedMicroseconds, kind);
    _sessionSummary?.addMarker(marker);
    if (_ring != null) {
      _ring!.add(marker);
    } else {
      _write(marker);
    }
  }

  // the REC indicator shows the attempt
  void _onReconnecting(EventArgs? _) => stateChangedEvent.broadcast();

  void _onReconnected(EventArgs? _) {
    if (_state != RecorderState.reconnecting) {
      return;
    }
    _addMarker(RecordingMarker.reconnected);
    _setState(_resumeState);
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

  // include filters take the color of the topic viewer subscription with the same filter, else a random one
  static List<RecorderFilter> _withColors(List<RecorderFilter> filters, List<TopicSubscription> subscriptions) => [
        for (var filter in filters)
          filter.copy()
            ..color = filter.exclude
                ? null
                : filter.color ??
                    subscriptions
                        .where((sub) => TopicSubscription.topicFilterOf(sub.topic) == filter.filter)
                        .map((sub) => sub.color)
                        .firstOrNull ??
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
