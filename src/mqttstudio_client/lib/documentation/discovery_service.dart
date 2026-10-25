import 'dart:async';
import 'dart:typed_data';
import 'package:clock/clock.dart';
import 'package:event/event.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/documentation/engine/discovery_merger.dart';
import 'package:mqttstudio/documentation/engine/doc_index.dart';
import 'package:mqttstudio/documentation/engine/documentation_analyzer.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/message_viewer/message_viewer.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/mqtt/side_connection.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/format/recording_reader.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';

enum DiscoveryState { idle, connecting, running, reconnecting }

class DiscoveryErrorEventArgs extends EventArgs {
  final String message;

  DiscoveryErrorEventArgs(this.message);
}

// Discovers the topics of the current project's broker, of a recording or of the topic viewer's messages
// (doc/documentation-design.md §5). Live discovery has its own connection (T9), subscribes with QoS 2 and, on MQTT 5,
// Retain As Published (T10), and never publishes (T12). The result waits for the review; nothing changes the
// documentation before apply.
class DiscoveryService {
  // a retained message within this time after subscribing is part of the retained snapshot (§5.2)
  static const Duration snapshotWindow = Duration(seconds: 2);
  static const Duration statsInterval = Duration(seconds: 1);
  // recordings and the topic viewer buffer give the UI a turn every this many messages
  static const int batchSize = 2000;
  static const String sysFilter = r'$SYS/#';

  // null in the CLI, which discovers without the app's projects
  final ProjectManager? _projectManager;
  final MqttAdapter Function() _connectionFactory;
  final bool reconnect;

  final stateChangedEvent = Event();
  // at most once per statsInterval while running
  final statsChangedEvent = Event();
  // a result is ready for the review
  final resultEvent = Event();
  final errorEvent = Event<DiscoveryErrorEventArgs>();

  DiscoveryState _state = DiscoveryState.idle;
  DiscoverySettings? _settings;
  DiscoverySource _source = DiscoverySource.live;
  DocumentationAnalyzer? _analyzer;
  SideConnection? _connection;
  DocIndex? _index;
  List<RecorderFilter> _filters = [];
  List<String> _ignore = [];
  final List<String> _errors = [];
  bool _isMqtt5 = true;
  // the documentation the result is compared with
  TopicDocumentation? _documentation;
  RecordingLibrary? _library;
  bool _lostConnection = false;
  Stopwatch? _stopwatch;
  int _subscribedAtMicros = 0;
  int _newTopics = 0;
  int _total = 0;
  int _read = 0;
  bool _stopRequested = false;
  Timer? _stopTimer;
  Timer? _statsTimer;
  Future<void>? _finishing;
  DiscoveryResult? lastResult;

  DiscoveryService({MqttAdapter Function()? connectionFactory, bool withProjects = true, this.reconnect = true})
      : _connectionFactory = connectionFactory ?? MqttAdapter.new,
        _projectManager = withProjects ? GetIt.I.get<ProjectManager>() : null {
    _projectManager?.projectClosedEvent.subscribe(_onProjectClosed);
  }

  void dispose() {
    _projectManager?.projectClosedEvent.unsubscribe(_onProjectClosed);
    _cancel();
  }

  DiscoveryState get state => _state;

  bool get isRunning => _state != DiscoveryState.idle;

  DiscoverySource get source => _source;

  DiscoverySettings? get settings => _settings;

  Duration get elapsed => _stopwatch?.elapsed ?? Duration.zero;

  int get messages => _analyzer?.messages ?? 0;

  int get topicCount => _analyzer?.topicCount ?? 0;

  // topics no documented topic matches
  int get newTopicCount => _newTopics;

  int get reconnectAttempt => _connection?.reconnectAttempt ?? 0;

  // 0..1 for a live discovery that stops after a duration or a number of messages, a recording or the buffer
  double? get progress {
    var settings = _settings;
    if (!isRunning || settings == null) {
      return null;
    }
    if (_source != DiscoverySource.live) {
      return _total == 0 ? null : _read / _total;
    }
    return switch (settings.stop) {
      DiscoveryStop.duration => (elapsed.inMilliseconds / (settings.durationSeconds * 1000)).clamp(0, 1).toDouble(),
      DiscoveryStop.messages => (messages / settings.maxMessages).clamp(0, 1).toDouble(),
      DiscoveryStop.manual => null,
    };
  }

  // the connection was lost and reconnect is off, e.g. in the CLI
  bool get lostConnection => _lostConnection;

  // throws without an include filter, or when the broker or the recording can't be opened; nothing runs then.
  // The app discovers for the open project; the CLI passes the documentation, the broker settings and the library.
  Future<void> start(DiscoverySettings settings,
      {DiscoverySource source = DiscoverySource.live,
      RecordingInfo? recording,
      TopicDocumentation? documentation,
      MqttSettings? broker,
      RecordingLibrary? library}) async {
    if (isRunning) {
      throw StateError('A discovery is already running');
    }
    var project = _projectManager?.currentProject;
    var discovered = documentation ?? project?.documentation;
    var connection = broker ?? (project == null ? null : SideConnection.settingsFor(project.mqttSettings, 'doc'));
    if (discovered == null || (source == DiscoverySource.live && connection == null)) {
      throw StateError('Discovery needs an open project');
    }
    if (!settings.filters.any((filter) => !filter.exclude && filter.filter.isNotEmpty)) {
      throw ArgumentError('Discovery needs at least one topic filter');
    }
    _settings = settings.copy();
    _source = source;
    _filters = RecorderRules.normalize(settings.filters).filters;
    _documentation = discovered;
    _library = library;
    _lostConnection = false;
    _ignore = [...discovered.ignoreFilters, if (settings.ignoreSys) sysFilter];
    _index = DocIndex(discovered.nodes);
    _errors.clear();
    _newTopics = 0;
    _read = 0;
    _total = 0;
    _stopRequested = false;
    _finishing = null;
    _isMqtt5 = switch (source) {
      DiscoverySource.recording => recording!.header.protocol == MqttProtocolVersion.v5,
      _ => connection?.isMqtt5 ?? true,
    };
    _analyzer = DocumentationAnalyzer(source: source, sourceName: recording?.name, inferSchemas: settings.inferSchemas);
    _stopwatch = clock.stopwatch()..start();
    switch (source) {
      case DiscoverySource.live:
        await _startLive(connection!);
      case DiscoverySource.recording:
        _setState(DiscoveryState.running);
        _startStats();
        unawaited(_readRecording(recording!));
      case DiscoverySource.buffer:
        _setState(DiscoveryState.running);
        _startStats();
        unawaited(_readBuffer());
    }
  }

  // stops and builds the result for the review
  Future<void> stop() {
    if (!isRunning) {
      return Future.value();
    }
    if (_source != DiscoverySource.live) {
      // the reading loop finishes on its own
      _stopRequested = true;
      return _finishing ?? Future.value();
    }
    return _finishOnce();
  }

  // writes the reviewed result into the documentation
  void apply(DiscoveryResult result) {
    var documentation = _projectManager?.currentProject?.documentation;
    if (documentation == null) {
      return;
    }
    DiscoveryMerger.apply(documentation, result, _settings ?? documentation.discoverySettings, isMqtt5: _isMqtt5);
    if (identical(result, lastResult)) {
      lastResult = null;
    }
    GetIt.I.get<DocumentationService>().notifyChanged();
  }

  Future<void> _startLive(MqttSettings settings) async {
    _setState(DiscoveryState.connecting);
    var connection = SideConnection(_connectionFactory, reconnect: reconnect);
    try {
      await connection.connect(settings);
    } catch (_) {
      connection.close();
      _analyzer = null;
      _setState(DiscoveryState.idle);
      rethrow;
    }
    _connection = connection;
    connection.messageReceivedEvent.subscribe(_onLiveMessage);
    connection.lostEvent.subscribe(_onConnectionLost);
    connection.reconnectingEvent.subscribe(_onReconnecting);
    connection.reconnectedEvent.subscribe(_onReconnected);
    connection.subscribeFailedEvent.subscribe(_onSubscribeFailed);
    connection.listen(_subscribe);
    if (_settings!.stop == DiscoveryStop.duration) {
      _stopTimer = Timer(Duration(seconds: _settings!.durationSeconds), () => unawaited(stop()));
    }
    _startStats();
    _setState(DiscoveryState.running);
  }

  void _subscribe(MqttAdapter connection) {
    for (var filter in _filters.where((filter) => !filter.exclude)) {
      // QoS 2 delivers the publisher's QoS; Retain As Published keeps the publisher's retain flag (T10)
      connection.subscribeToTopic(TopicSubscription(filter.filter, MqttQos.exactlyOnce,
          retainAsPublished: _isMqtt5, retainHandling: SubscriptionRetainHandling.sendOnSubscribe));
    }
    _subscribedAtMicros = _stopwatch!.elapsedMicroseconds;
  }

  void _onLiveMessage(ReceivedMqttMessage? message) {
    if (message == null || _state != DiscoveryState.running) {
      return;
    }
    var offset = _stopwatch!.elapsedMicroseconds;
    var snapshot = message.retain && offset - _subscribedAtMicros <= snapshotWindow.inMicroseconds;
    _accept(
        RecordedMessage(
            offsetMicros: offset,
            topic: message.topicName,
            payload: Uint8List.fromList(message.payload),
            qos: message.qos,
            retain: message.retain,
            snapshot: snapshot,
            properties: message.properties),
        clock.now());
    if (_settings!.stop == DiscoveryStop.messages && messages >= _settings!.maxMessages) {
      unawaited(stop());
    }
  }

  void _accept(RecordedMessage message, DateTime at) {
    var analyzer = _analyzer!;
    if (!RecorderRules.isRecorded(message.topic, _filters) ||
        _ignore.any((filter) => RecorderRules.matches(message.topic, filter))) {
      return;
    }
    var known = analyzer.hasSeen(message.topic);
    analyzer.add(message, at);
    if (!known && analyzer.hasSeen(message.topic) && _index!.match(message.topic) == null) {
      _newTopics++;
    }
  }

  void _onConnectionLost(EventArgs? _) {
    _analyzer?.markGap();
    if (!reconnect) {
      _lostConnection = true;
      unawaited(stop());
      return;
    }
    _setState(DiscoveryState.reconnecting);
  }

  void _onReconnecting(EventArgs? _) => stateChangedEvent.broadcast();

  void _onReconnected(EventArgs? _) => _setState(DiscoveryState.running);

  void _onSubscribeFailed(SubscribeFailedEventArgs? args) {
    if (args == null) {
      return;
    }
    var message = '${args.topic}: ${args.reason ?? ''}'.trim();
    _errors.add(message);
    errorEvent.broadcast(DiscoveryErrorEventArgs(message));
  }

  Future<void> _readRecording(RecordingInfo info) async {
    RecordingReader? reader;
    try {
      reader = await (_library ?? GetIt.I.get<RecordingLibrary>()).open(info);
      _total = info.footer.summary.messages;
      var startedAt = info.header.startedAt;
      await for (var entry in reader.entries()) {
        if (_stopRequested || _analyzer == null) {
          break;
        }
        switch (entry) {
          case MessageEntry(:var message):
            _read++;
            _accept(message, startedAt.add(message.offset));
          case MarkerEntry(:var marker):
            if (marker.kind == RecordingMarker.connectionLost) {
              _analyzer!.markGap();
            }
        }
        if (_read % batchSize == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    } catch (exc) {
      _errors.add(exc.toString());
      errorEvent.broadcast(DiscoveryErrorEventArgs(exc.toString()));
    } finally {
      try {
        await reader?.close();
      } catch (_) {
        // the messages are read, a file that doesn't close doesn't change the result
      }
    }
    if (_analyzer != null) {
      _analyzer!.finish(info.header.startedAt.add(Duration(microseconds: info.footer.durationMicros)));
      await _finishOnce();
    }
  }

  Future<void> _readBuffer() async {
    var buffered = GetIt.I.get<MessageViewer>().messageBuffer.allMessages
      ..sort((a, b) => a.receivedOn.compareTo(b.receivedOn));
    _total = buffered.length;
    var first = buffered.isEmpty ? clock.now() : buffered.first.receivedOn;
    for (var message in buffered) {
      if (_stopRequested || _analyzer == null) {
        break;
      }
      _read++;
      _accept(
          RecordedMessage(
              offsetMicros: message.receivedOn.difference(first).inMicroseconds,
              topic: message.topicName,
              payload: Uint8List.fromList(message.payload),
              qos: message.qos,
              retain: message.retain,
              properties: message.properties),
          message.receivedOn);
      if (_read % batchSize == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (_analyzer != null) {
      await _finishOnce();
    }
  }

  // _finish runs to its end before it returns, so the future is kept until it completed and cleared afterwards;
  // assigning the result of _finish() after it cleared the field would keep a finished future for the next discovery
  Future<void> _finishOnce() => _finishing ??= _finish().whenComplete(() => _finishing = null);

  // always ends the discovery; a result that can't be built is reported as an error
  Future<void> _finish() async {
    var analyzer = _analyzer;
    _stopTimer?.cancel();
    _statsTimer?.cancel();
    _stopwatch?.stop();
    DiscoveryResult? result;
    try {
      _closeConnection();
      var documentation = _documentation;
      if (analyzer != null && documentation != null) {
        if (_source == DiscoverySource.live) {
          analyzer.finish(clock.now());
        }
        result =
            DiscoveryMerger.build(documentation, analyzer, _settings!, isMqtt5: _isMqtt5, errors: List.of(_errors));
      }
    } catch (exc) {
      errorEvent.broadcast(DiscoveryErrorEventArgs(exc.toString()));
    }
    _connection = null;
    _analyzer = null;
    if (result != null) {
      lastResult = result;
    }
    _setState(DiscoveryState.idle);
    if (result != null) {
      resultEvent.broadcast();
    }
  }

  // stops without a result, e.g. when the project closes
  void _cancel() {
    _analyzer = null;
    _stopRequested = true;
    _closeConnection();
    _stopTimer?.cancel();
    _statsTimer?.cancel();
    if (_state != DiscoveryState.idle) {
      _setState(DiscoveryState.idle);
    }
  }

  void _closeConnection() {
    var connection = _connection;
    if (connection == null) {
      return;
    }
    connection.messageReceivedEvent.unsubscribe(_onLiveMessage);
    connection.lostEvent.unsubscribe(_onConnectionLost);
    connection.reconnectingEvent.unsubscribe(_onReconnecting);
    connection.reconnectedEvent.unsubscribe(_onReconnected);
    connection.subscribeFailedEvent.unsubscribe(_onSubscribeFailed);
    connection.close();
    _connection = null;
  }

  void _startStats() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(statsInterval, (_) => statsChangedEvent.broadcast());
  }

  void _onProjectClosed(EventArgs? _) {
    lastResult = null;
    _cancel();
  }

  void _setState(DiscoveryState state) {
    _state = state;
    stateChangedEvent.broadcast();
  }
}
