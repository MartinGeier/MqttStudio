import 'dart:async';
import 'dart:math';
import 'package:clock/clock.dart';
import 'package:event/event.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/simulator/engine/generator_instances.dart';
import 'package:mqttstudio/simulator/engine/placeholders.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
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

  final Map<String, _TopicRun> _runs = {};
  final Map<String, TopicStats> _stats = {};
  Timer? _statsTimer;
  bool _statsDirty = false;
  bool _connectionLostReported = false;

  SimulatorRunner(this._publisher, {this.seed, this.statsInterval = const Duration(milliseconds: 500)})
      : _random = Random(seed);

  bool isRunning(String topicId) => _runs.containsKey(topicId);

  bool get isAnyRunning => _runs.isNotEmpty;

  Iterable<String> get runningTopicIds => _runs.keys;

  TopicStats statsOf(String topicId) => _stats.putIfAbsent(topicId, () => TopicStats());

  TopicRunState stateOf(String topicId) {
    if (_runs.containsKey(topicId)) {
      return TopicRunState.running;
    }
    return _stats[topicId]?.error != null ? TopicRunState.error : TopicRunState.stopped;
  }

  // estimated msg/s of the running topics
  double get runningRate => _runs.values.fold(0.0, (sum, run) => sum + run.rate);

  int get totalSent => _stats.values.fold(0, (sum, stats) => sum + stats.sent);

  int get errorCount => _stats.values.where((stats) => stats.error != null).length;

  void startAll(Simulation simulation) {
    for (var device in simulation.devices) {
      _startTopics(device, device.topics);
    }
    runStateChangedEvent.broadcast();
  }

  void startDevice(SimulatedDevice device) => start(device, device.topics);

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

  void stopDevice(SimulatedDevice device) => stopTopics(device.topics.map((topic) => topic.id));

  void stopAll() {
    for (var run in _runs.values) {
      run.cancel();
    }
    _runs.clear();
    runStateChangedEvent.broadcast();
  }

  // stops everything and forgets the statistics, e.g. when the project is closed
  void reset() {
    stopAll();
    _stats.clear();
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
