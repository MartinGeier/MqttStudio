import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:clock/clock.dart';
import 'package:event/event.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/recorder/engine/recording_player.dart';
import 'package:mqttstudio/recorder/format/recording_reader.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';
import 'package:mqttstudio/simulator/engine/generator_instances.dart';
import 'package:mqttstudio/simulator/engine/placeholders.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/vda5050/simulated_fleet.dart';
import 'package:typed_data/typed_buffers.dart';

enum TopicRunState { stopped, running, error }

// Statistics of a simulated topic, summed up over all instances of its device
class TopicStats {
  int sent = 0;
  String? lastPayload;
  // the instance that sent the last payload
  int? lastInstance;
  DateTime? lastPublishedAt;
  // why the topic stopped or could not start, null while it is fine
  String? error;
  GeneratorError? generatorError;
  SimulationIssueKind? issue;
  String errorDetail = '';

  void _clearError() {
    error = null;
    generatorError = null;
    issue = null;
    errorDetail = '';
  }
}

class TopicErrorEventArgs extends EventArgs {
  final String device;
  final String topic;
  final String message;

  TopicErrorEventArgs(this.device, this.topic, this.message);
}

class _InstanceRun {
  final int instance;
  final String topic;
  final GeneratorInstance generator;
  final List<MqttUserPropertyEntry> userProperties;
  DateTime lastAt;
  Timer? timer;

  _InstanceRun(this.instance, this.topic, this.generator, this.userProperties, this.lastAt);
}

class _TopicRun {
  final SimulatedDevice device;
  final SimulatedTopic topic;
  final List<_InstanceRun> instances = [];

  _TopicRun(this.device, this.topic);

  double get rate => SimulationRules.topicRate(device, topic);

  void cancel() {
    for (var instance in instances) {
      instance.timer?.cancel();
    }
  }
}

// opens the file of the recording a recorded device plays; throws when it can't be found
typedef RecordingOpener = Future<RecordingFile> Function(RecordedSource source);

class _RecordedRun {
  final SimulatedDevice device;
  final double rate;
  final List<RecordingPlayer> players = [];
  final List<Timer> startTimers = [];
  int finished = 0;

  _RecordedRun(this.device, this.rate);

  void cancel() {
    for (var timer in startTimers) {
      timer.cancel();
    }
    for (var player in players) {
      player.dispose();
      player.reader.close();
    }
  }
}

// Publishes the messages of the running simulated topics. It only reports a lost connection, the owner decides
// whether to stop (the app) or to wait for a reconnect (the CLI). While the publisher is not connected, messages are
// skipped and the timers keep running.
class SimulatorRunner {
  final SimulatorPublisher _publisher;
  // seeds every generator, so two runs produce the same payloads
  final int? seed;
  final Duration statsInterval;
  final Random _random;

  final runStateChangedEvent = Event();
  // raised at most once per statsInterval
  final statsChangedEvent = Event();
  final connectionLostEvent = Event();
  final topicErrorEvent = Event<TopicErrorEventArgs>();

  // a recording up to this size is loaded once and shared by all instances of a recorded device
  static const int maxSharedRecordingBytes = 64 * 1024 * 1024;
  // the longest start delay of a staggered instance of a recorded device
  static const Duration maxStagger = Duration(seconds: 10);

  final RecordingOpener? openRecording;
  final Map<String, _TopicRun> _runs = {};
  final Map<String, _RecordedRun> _recordedRuns = {};
  // the robots of the running VDA 5050 devices, by device id (D26)
  final Map<String, SimulatedFleet> _fleets = {};
  // the fleets that ran last, so their robots and statistics stay visible after a stop
  final Map<String, SimulatedFleet> _lastFleets = {};
  // the recorded topics a recorded device played last, by device id
  final Map<String, List<String>> _recordedTopics = {};
  final Map<String, TopicStats> _stats = {};
  // kept apart from _stats so the messages of a recorded device are not counted twice
  final Map<String, TopicStats> _deviceStats = {};
  Timer? _statsTimer;
  bool _statsDirty = false;
  bool _connectionLostReported = false;

  SimulatorRunner(this._publisher,
      {this.seed, this.statsInterval = const Duration(milliseconds: 500), this.openRecording})
      : _random = Random(seed);

  bool isRunning(String topicId) => _runs.containsKey(topicId);

  // a recorded device plays or the robots of a VDA 5050 device drive
  bool isDeviceRunning(String deviceId) => _recordedRuns.containsKey(deviceId) || _fleets.containsKey(deviceId);

  bool get isAnyRunning => _runs.isNotEmpty || _recordedRuns.isNotEmpty || _fleets.isNotEmpty;

  // the robots of a VDA 5050 device while it runs, else of its last run; null before its first start
  SimulatedFleet? fleetOf(String deviceId) => _fleets[deviceId] ?? _lastFleets[deviceId];

  // statistics of a recorded topic of a recorded device, summed up over its instances
  TopicStats recordedStatsOf(String deviceId, String recordedTopic) => statsOf('$deviceId|$recordedTopic');

  // why a recorded device stopped or could not start
  TopicStats deviceStatsOf(String deviceId) => _deviceStats.putIfAbsent(deviceId, () => TopicStats());

  // the recorded topics the device played last, null before its first start
  List<String>? recordedTopicsOf(String deviceId) => _recordedTopics[deviceId];

  // offset in the recording of the first instance
  int? positionOf(String deviceId) => _recordedRuns[deviceId]?.players.firstOrNull?.positionMicros;

  Iterable<String> get runningTopicIds => _runs.keys;

  TopicStats statsOf(String topicId) => _stats.putIfAbsent(topicId, () => TopicStats());

  TopicRunState stateOf(String topicId) {
    if (_runs.containsKey(topicId)) {
      return TopicRunState.running;
    }
    return _stats[topicId]?.error != null ? TopicRunState.error : TopicRunState.stopped;
  }

  // estimated msg/s of the running topics
  double get runningRate =>
      _runs.values.fold(0.0, (sum, run) => sum + run.rate) +
      _recordedRuns.values.fold(0.0, (sum, run) => sum + run.rate) +
      _fleets.values.fold(0.0, (sum, fleet) => sum + SimulatedFleet.rateOf(fleet.device));

  int get totalSent =>
      _stats.values.fold(0, (sum, stats) => sum + stats.sent) +
      _lastFleets.values.fold(0, (sum, fleet) => sum + fleet.sent);

  int get errorCount =>
      _stats.values.where((stats) => stats.error != null).length +
      _deviceStats.values.where((stats) => stats.error != null).length;

  // recorded devices start once their recording is open, their errors go to deviceStatsOf
  void startAll(Simulation simulation) {
    for (var device in simulation.devices) {
      if (device.isRecorded) {
        startRecorded(device);
      } else if (device.isVda5050) {
        _startFleet(device);
      } else {
        _startTopics(device, device.topics);
      }
    }
    runStateChangedEvent.broadcast();
  }

  void startDevice(SimulatedDevice device) {
    if (device.isRecorded) {
      startRecorded(device);
    } else if (device.isVda5050) {
      _startFleet(device);
      runStateChangedEvent.broadcast();
    } else {
      start(device, device.topics);
    }
  }

  void start(SimulatedDevice device, Iterable<SimulatedTopic> topics) {
    _startTopics(device, topics);
    runStateChangedEvent.broadcast();
  }

  // starts the given topics again with their current configuration, if they are running
  void restart(SimulatedDevice device, Iterable<SimulatedTopic> topics) {
    var running = topics.where((topic) => isRunning(topic.id)).toList();
    if (running.isNotEmpty) {
      start(device, running);
    }
  }

  void stopTopic(String topicId) => stopTopics([topicId]);

  void stopTopics(Iterable<String> topicIds) {
    for (var id in topicIds.toList()) {
      _runs.remove(id)?.cancel();
    }
    runStateChangedEvent.broadcast();
  }

  void stopDevice(SimulatedDevice device) {
    if (device.isRecorded) {
      _recordedRuns.remove(device.id)?.cancel();
      runStateChangedEvent.broadcast();
    } else if (device.isVda5050) {
      _stopFleet(device.id);
      runStateChangedEvent.broadcast();
    } else {
      stopTopics(device.topics.map((topic) => topic.id));
    }
  }

  void stopAll() {
    for (var run in _runs.values) {
      run.cancel();
    }
    _runs.clear();
    for (var run in _recordedRuns.values) {
      run.cancel();
    }
    _recordedRuns.clear();
    for (var id in _fleets.keys.toList()) {
      _stopFleet(id);
    }
    runStateChangedEvent.broadcast();
  }

  // Starts the robots of a VDA 5050 device and its fleet control (doc/vda5050-design.md §10). Problems end up in
  // deviceStatsOf.
  void _startFleet(SimulatedDevice device) {
    _stopFleet(device.id);
    var deviceStats = deviceStatsOf(device.id)
      ..sent = 0
      .._clearError();
    var issues = SimulationRules.validateVda5050(device);
    if (issues.isNotEmpty) {
      _setDeviceError(device, issues.first.kind, issues.first.describe(), issues.first.detail);
      return;
    }
    var source = device.vda5050!;
    var random = Random(source.seed ?? (seed == null ? null : _seedFor(device.id, 0)));
    var fleet = SimulatedFleet(device, (topic, json, qos, retain) => _publishJson(deviceStats, topic, json, qos, retain),
        random,
        onPublished: _markStatsDirty);
    _fleets[device.id] = fleet;
    _lastFleets[device.id] = fleet;
    fleet.start();
  }

  // the robots of a connected device say goodbye (OFFLINE); without a connection they just stop
  void _stopFleet(String deviceId) => _fleets.remove(deviceId)?.stop(goodbye: _publisher.isConnected);

  void _publishJson(TopicStats stats, String topic, Map<String, Object?> json, MqttQos qos, bool retain) {
    if (!_publisher.isConnected) {
      _reportConnectionLost();
      return;
    }
    try {
      var payload = Uint8Buffer()..addAll(utf8.encode(jsonEncode(json)));
      var properties = _publisher.supportsProperties
          ? MqttMessageProperties(contentType: 'application/json', payloadFormatUtf8: true)
          : null;
      _publisher.publish(topic, payload, qos, retain, properties);
    } on Exception {
      _reportConnectionLost();
      return;
    }
    _connectionLostReported = false;
    stats
      ..sent += 1
      ..lastPublishedAt = clock.now();
  }

  // Plays the recording of a recorded device, one player per instance (D22, D24). {n} and {device} in the remap
  // targets are resolved per instance. Problems end up in deviceStatsOf.
  Future<void> startRecorded(SimulatedDevice device) async {
    _recordedRuns.remove(device.id)?.cancel();
    var deviceStats = deviceStatsOf(device.id)
      ..sent = 0
      .._clearError();
    var issues = SimulationRules.validateRecorded(device);
    if (issues.isNotEmpty) {
      _setDeviceError(device, issues.first.kind, issues.first.describe(), issues.first.detail);
      return;
    }
    var source = device.recorded!;
    var readers = await _openReaders(device, source);
    if (readers == null) {
      return;
    }
    if (_recordedRuns.containsKey(device.id)) {
      // started twice while the recording was opening
      for (var reader in readers) {
        reader.close();
      }
      return;
    }
    var footer = readers.first.footer!;
    var options = source.playback;
    var rate = RecordingPlayer.estimateFooter(footer, options).rate * device.instanceCount;
    var run = _RecordedRun(device, rate);
    var topics = footer.topics.where(options.plays).toList();
    _recordedTopics[device.id] = topics;
    for (var topic in topics) {
      recordedStatsOf(device.id, topic)
        ..sent = 0
        ..lastPayload = null
        ..lastInstance = null
        ..lastPublishedAt = null;
    }
    var stagger = _staggerOf(footer, topics);
    var rangeStart = options.rangeStartMicros ?? 0;
    var rangeEnd = options.rangeEndMicros ?? footer.durationMicros;
    var index = 0;
    for (var n in device.instanceNumbers) {
      var startPosition = source.instanceStart == InstanceStart.randomPosition && rangeEnd > rangeStart
          ? rangeStart + _random.nextInt(max(1, min(rangeEnd - rangeStart, 0x7fffffff)))
          : null;
      var player = RecordingPlayer(readers[index++], options, _publisher,
          mapTopic: (topic) => Placeholders.resolve(options.remap(topic), instance: n, deviceName: device.name),
          onPublished: (message, _) => _recordedPublished(device, n, message),
          startPositionMicros: startPosition);
      player.connectionLostEvent.subscribe((_) => _reportConnectionLost());
      player.finishedEvent.subscribe((_) => _recordedFinished(run));
      run.players.add(player);
      if (source.instanceStart == InstanceStart.staggered && stagger > Duration.zero) {
        run.startTimers.add(Timer(stagger * _random.nextDouble(), player.play));
      } else {
        player.play();
      }
    }
    _recordedRuns[device.id] = run;
    deviceStats.sent = 0;
    runStateChangedEvent.broadcast();
  }

  // One reader per instance. A small recording is read once and shared from memory.
  Future<List<RecordingReader>?> _openReaders(SimulatedDevice device, RecordedSource source) async {
    var readers = <RecordingReader>[];
    try {
      if (openRecording == null) {
        throw StateError('no recordings');
      }
      var file = await openRecording!(source);
      var length = await file.length();
      if (length <= maxSharedRecordingBytes) {
        var shared = BytesRecordingFile(file.name, await file.read(0, length));
        await file.close();
        for (var i = 0; i < device.instanceCount; i++) {
          readers.add(await RecordingReader.open(shared));
        }
      } else {
        readers.add(await RecordingReader.open(file));
        for (var i = 1; i < device.instanceCount; i++) {
          readers.add(await RecordingReader.open(await openRecording!(source)));
        }
      }
      if (!readers.first.isComplete) {
        throw StateError('unfinished recording');
      }
      return readers;
    } catch (_) {
      for (var reader in readers) {
        reader.close();
      }
      var issue = SimulationIssue(SimulationIssueKind.recordingMissing, device: device.name, detail: source.recordingName);
      _setDeviceError(device, issue.kind, issue.describe(), issue.detail);
      return null;
    }
  }

  // staggered instances start within the average time between two messages of one played topic
  static Duration _staggerOf(RecordingFooter footer, List<String> topics) {
    var count = topics.fold(0, (sum, topic) => sum + (footer.summary.perTopic[topic]?.count ?? 0));
    if (count == 0 || topics.isEmpty) {
      return Duration.zero;
    }
    var interval = Duration(microseconds: footer.durationMicros * topics.length ~/ count);
    return interval > maxStagger ? maxStagger : interval;
  }

  void _recordedPublished(SimulatedDevice device, int instance, RecordedMessage message) {
    var text = message.payload.length > 200 ? null : _tryUtf8(message.payload);
    recordedStatsOf(device.id, message.topic)
      ..sent += 1
      ..lastPayload = text ?? '<binary ${(message.payloadLength / 1000).toStringAsFixed(1)} KB>'
      ..lastInstance = instance
      ..lastPublishedAt = clock.now();
    deviceStatsOf(device.id).sent += 1;
    _markStatsDirty();
  }

  static String? _tryUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }

  void _recordedFinished(_RecordedRun run) {
    run.finished++;
    if (run.finished < run.players.length || _recordedRuns[run.device.id] != run) {
      return;
    }
    _recordedRuns.remove(run.device.id)?.cancel();
    runStateChangedEvent.broadcast();
  }

  void _setDeviceError(SimulatedDevice device, SimulationIssueKind kind, String message, String detail) {
    deviceStatsOf(device.id)
      ..error = message
      ..issue = kind
      ..errorDetail = detail;
    topicErrorEvent.broadcast(TopicErrorEventArgs(device.name, '', message));
    _markStatsDirty();
    runStateChangedEvent.broadcast();
  }

  // stops everything and forgets the statistics, e.g. when the project is closed
  void reset() {
    stopAll();
    _stats.clear();
    _deviceStats.clear();
    _recordedTopics.clear();
    _lastFleets.clear();
    statsChangedEvent.broadcast();
  }

  // removes the retained messages of the simulated topics from the broker by publishing an empty retained message
  int clearRetained(Iterable<(SimulatedDevice, SimulatedTopic)> topics) {
    if (!_publisher.isConnected) {
      return 0;
    }
    var count = 0;
    for (var (device, topic) in topics) {
      if (!topic.retain) {
        continue;
      }
      for (var resolved in SimulationRules.resolvedTopics(device, topic)) {
        _publisher.publish(resolved, Uint8Buffer(), topic.qos, true, null);
        count++;
      }
    }
    return count;
  }

  // removes the retained connection messages of the robots of VDA 5050 devices
  int clearRetainedConnections(Iterable<SimulatedDevice> devices) {
    if (!_publisher.isConnected) {
      return 0;
    }
    var count = 0;
    for (var device in devices.where((device) => device.isVda5050 && device.vda5050 != null)) {
      for (var n in device.instanceNumbers) {
        var prefix = Placeholders.resolve(device.vda5050!.topicPrefix, instance: n, deviceName: device.name);
        _publisher.publish('$prefix/connection', Uint8Buffer(), MqttQos.atLeastOnce, true, null);
        count++;
      }
    }
    return count;
  }

  void dispose() {
    stopAll();
    _statsTimer?.cancel();
  }

  void _startTopics(SimulatedDevice device, Iterable<SimulatedTopic> topics) {
    for (var topic in topics.toList()) {
      _startTopic(device, topic);
    }
  }

  void _startTopic(SimulatedDevice device, SimulatedTopic topic) {
    _runs.remove(topic.id)?.cancel();
    var stats = statsOf(topic.id)
      ..sent = 0
      ..lastPayload = null
      ..lastInstance = null
      ..lastPublishedAt = null
      .._clearError();

    var issues = SimulationRules.validateTopic(device, topic);
    if (issues.isNotEmpty) {
      stats
        ..error = issues.first.describe()
        ..issue = issues.first.kind
        ..errorDetail = issues.first.detail;
      _reportError(device, topic, stats.error!);
      return;
    }

    var run = _TopicRun(device, topic);
    var now = clock.now();
    try {
      for (var n in device.instanceNumbers) {
        var context = GeneratorContext(
            random: seed == null ? Random() : Random(_seedFor(topic.id, n)),
            instanceNumber: n,
            deviceName: device.name,
            startedAt: now);
        var userProperties = topic.mqtt5.userProperties
            .map((property) => MqttUserPropertyEntry(
                property.key, Placeholders.resolve(property.value, instance: n, deviceName: device.name)))
            .toList();
        run.instances.add(_InstanceRun(n, Placeholders.resolve(topic.topic, instance: n, deviceName: device.name),
            createGeneratorInstance(topic.generator, context), userProperties, now));
      }
    } on GeneratorException catch (exc) {
      _setGeneratorError(device, topic, exc);
      return;
    }

    _runs[topic.id] = run;
    // the first messages are spread over one interval, so many instances don't publish at the same moment
    for (var instance in run.instances) {
      _schedule(run, instance, _sampleInterval(topic) * _random.nextDouble());
    }
  }

  void _schedule(_TopicRun run, _InstanceRun instance, num delayMs) {
    instance.timer = Timer(Duration(microseconds: (delayMs * 1000).round()), () => _fire(run, instance));
  }

  void _fire(_TopicRun run, _InstanceRun instance) {
    if (_runs[run.topic.id] != run) {
      return;
    }
    var now = clock.now();
    var elapsed = now.difference(instance.lastAt);
    instance.lastAt = now;

    GeneratedValue value;
    try {
      value = instance.generator.next(now, elapsed);
    } on GeneratorException catch (exc) {
      _runs.remove(run.topic.id)?.cancel();
      _setGeneratorError(run.device, run.topic, exc);
      runStateChangedEvent.broadcast();
      return;
    }

    _publish(run.topic, instance, value, now);
    _schedule(run, instance, _sampleInterval(run.topic));
  }

  void _publish(SimulatedTopic topic, _InstanceRun instance, GeneratedValue value, DateTime now) {
    if (!_publisher.isConnected) {
      _reportConnectionLost();
      return;
    }
    try {
      var payload = Uint8Buffer()..addAll(value.payload);
      _publisher.publish(instance.topic, payload, topic.qos, topic.retain, _propertiesOf(topic, instance, value));
    } on Exception {
      // the connection broke between the check and the publish
      _reportConnectionLost();
      return;
    }
    _connectionLostReported = false;

    statsOf(topic.id)
      ..sent += 1
      ..lastPayload = value.describe()
      ..lastInstance = instance.instance
      ..lastPublishedAt = now;
    _markStatsDirty();
  }

  MqttMessageProperties? _propertiesOf(SimulatedTopic topic, _InstanceRun instance, GeneratedValue value) {
    if (!_publisher.supportsProperties) {
      return null;
    }
    var contentType = topic.mqtt5.contentType;
    var properties = MqttMessageProperties(
      contentType: contentType == null || contentType.isEmpty ? value.contentType : contentType,
      messageExpiryInterval: topic.mqtt5.messageExpirySeconds,
      payloadFormatUtf8: !value.isBinary,
      userProperties: instance.userProperties,
    );
    return properties.isEmpty ? null : properties;
  }

  int _sampleInterval(SimulatedTopic topic) {
    var minMs = topic.interval.minMs;
    var maxMs = max(minMs, topic.interval.maxMs);
    return minMs + _random.nextInt(maxMs - minMs + 1);
  }

  int _seedFor(String topicId, int instance) {
    var hash = seed!;
    for (var unit in topicId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return (hash * 31 + instance) & 0x7fffffff;
  }

  void _setGeneratorError(SimulatedDevice device, SimulatedTopic topic, GeneratorException exc) {
    statsOf(topic.id)
      ..error = exc.message
      ..generatorError = exc.error
      ..errorDetail = exc.detail;
    _reportError(device, topic, exc.message);
  }

  void _reportError(SimulatedDevice device, SimulatedTopic topic, String message) {
    topicErrorEvent.broadcast(TopicErrorEventArgs(device.name, topic.topic, message));
    _markStatsDirty();
  }

  void _reportConnectionLost() {
    if (!_connectionLostReported) {
      _connectionLostReported = true;
      connectionLostEvent.broadcast();
    }
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
