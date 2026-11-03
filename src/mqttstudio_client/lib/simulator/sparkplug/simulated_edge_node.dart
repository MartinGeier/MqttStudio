import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:clock/clock.dart';
import 'package:event/event.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/mqtt/mqtt_will.dart';
import 'package:mqttstudio/mqtt/side_connection.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_profile.dart';
import 'package:mqttstudio/simulator/engine/generator_instances.dart';
import 'package:mqttstudio/simulator/engine/placeholders.dart';
import 'package:mqttstudio/simulator/model/sparkplug_source.dart';
import 'package:mqttstudio/simulator/sparkplug/sparkplug_fault.dart';
import 'package:mqttstudio/simulator/sparkplug/metric_values.dart';
import 'package:typed_data/typed_buffers.dart';

enum EdgeNodeState { stopped, connecting, waitingForHost, online, reconnecting }

class _Metric {
  final SparkplugMetricSpec spec;
  final int? alias;
  final GeneratorInstance generator;
  Object? value;
  // the value the last birth or data message carried
  Object? published;
  // written by a command: the generator pauses until the next write (Q4)
  bool held = false;

  _Metric(this.spec, this.alias, this.generator);
}

class _Device {
  final String id;
  final List<_Metric> metrics;
  bool online = true;

  _Device(this.id, this.metrics);
}

// One simulated Sparkplug B 3.0 edge node with its devices (doc/sparkplug-design.md §10.2, §10.4): a connection of
// its own whose last will is the NDEATH, bdSeq counted per CONNECT, births after the primary host's STATE, data by
// exception and by alias, rebirth and writes through NCMD and DCMD. Runs on the clock and timers, so tests run it in
// fake time.
class SimulatedEdgeNode {
  static const List<Duration> reconnectDelays = SideConnection.reconnectDelays;
  // a lost primary host: disconnect, then connect again after this and wait for its STATE
  static const Duration hostLostDelay = Duration(seconds: 1);
  static const String algorithmMetric = 'algorithm';

  final SparkplugSource source;
  final MqttSettings settings;
  final MqttAdapter Function() connectionFactory;
  final String groupId;
  final String edgeNodeId;
  late final List<_Metric> _nodeMetrics;
  late final List<_Device> _devices;
  // the metric of a write or a rebirth request by alias; the rebirth metric has alias 0
  final Map<int, _Metric> _byAlias = {};

  EdgeNodeState _state = EdgeNodeState.stopped;
  // the bdSeq of the current connection, -1 before the first
  int bdSeq = -1;
  int _nextBdSeq = 0;
  // the seq of the next message
  int _seq = 0;
  int messages = 0;
  final changedEvent = Event();
  // after every message, e.g. for the simulator's statistics
  void Function()? onPublished;

  MqttAdapter? _adapter;
  Timer? _scanTimer;
  Timer? _retryTimer;
  int _attempt = 0;
  bool _stopped = true;
  bool _closing = false;
  int? _hostTimestamp;
  // toggled faults
  bool _dataAfterDeath = false;
  bool _noTimestamp = false;
  DateTime _lastScan;

  SimulatedEdgeNode(
    this.source, {
    required int instance,
    required this.settings,
    required this.connectionFactory,
    required Random random,
    required DateTime startedAt,
    String deviceName = '',
  }) : groupId = source.groupId,
       edgeNodeId = Placeholders.resolve(source.edgeNodeId, instance: instance, deviceName: deviceName),
       _lastScan = startedAt {
    var context = GeneratorContext(
      random: random,
      instanceNumber: instance,
      deviceName: deviceName,
      startedAt: startedAt,
    );
    var alias = 1;
    _Metric metric(SparkplugMetricSpec spec) {
      var created = _Metric(spec, source.aliases ? alias++ : null, createGeneratorInstance(spec.generator, context));
      if (created.alias != null) {
        _byAlias[created.alias!] = created;
      }
      return created;
    }

    _nodeMetrics = [for (var spec in source.nodeMetrics) metric(spec)];
    _devices = [
      for (var device in source.devices)
        for (var d = 1; d <= device.count; d++)
          _Device(Placeholders.resolve(device.id.replaceAll('{d}', '$d'), instance: instance, deviceName: deviceName), [
            for (var spec in device.metrics) metric(spec),
          ]),
    ];
    _sample(startedAt, Duration.zero);
  }

  EdgeNodeState get state => _state;

  // the seq the last message carried, null before the first birth
  int? get lastSeq => bdSeq < 0 || messages == 0 ? null : (_seq + 255) % 256;

  List<String> get deviceIds => [for (var device in _devices) device.id];

  bool isDeviceOnline(String id) => _device(id)?.online ?? false;

  String nodeTopic(String type) => SparkplugProfile.topicOf(type, groupId, edgeNodeId);

  String deviceTopic(String type, String device) => SparkplugProfile.topicOf(type, groupId, edgeNodeId, device);

  String? get _hostTopic => source.primaryHostId == null
      ? null
      : '${SparkplugProfile.namespace}/${SpbMessageType.state}/${source.primaryHostId}';

  Future<void> start() async {
    if (!_stopped) {
      return;
    }
    _stopped = false;
    await _connect();
  }

  // an intentional stop: the NDEATH is published here, the broker drops the will on a clean disconnect
  Future<void> stop() async {
    _stopped = true;
    _retryTimer?.cancel();
    _scanTimer?.cancel();
    if (_state == EdgeNodeState.online) {
      _publishDeath();
    }
    _close();
    _setState(EdgeNodeState.stopped);
  }

  // a device goes offline (DDEATH) or comes back (DBIRTH)
  void setDeviceOnline(String id, bool online) {
    var device = _device(id);
    if (device == null || device.online == online) {
      return;
    }
    device.online = online;
    if (_state != EdgeNodeState.online) {
      return;
    }
    if (online) {
      _deviceBirth(device);
    } else {
      _publish(deviceTopic(SpbMessageType.dDeath, id), SpbPayload(timestamp: _now(), seq: _nextSeq()));
    }
    changedEvent.broadcast();
  }

  _Device? _device(String id) => _devices.where((device) => device.id == id).firstOrNull;

  // ---------- connection ----------

  Future<void> _connect() async {
    _setState(_attempt == 0 ? EdgeNodeState.connecting : EdgeNodeState.reconnecting);
    // bdSeq counts every CONNECT, the will carries it
    var connectBdSeq = _nextBdSeq;
    _nextBdSeq = (_nextBdSeq + 1) % 256;
    var adapter = connectionFactory();
    try {
      await adapter.connect(
        settings,
        will: MqttWill(nodeTopic(SpbMessageType.nDeath), _deathPayload(connectBdSeq), qos: MqttQos.atLeastOnce),
      );
    } catch (_) {
      adapter.disconnect();
      _scheduleRetry();
      return;
    }
    if (_stopped) {
      adapter.disconnect();
      return;
    }
    bdSeq = connectBdSeq;
    _attempt = 0;
    _adapter = adapter;
    adapter.onDisconnectedEvent.subscribe(_onDisconnected);
    adapter.messageReceivedEvent.subscribe(_onMessage);
    // commands and the host's STATE are subscribed before the birth
    adapter.subscribeToTopic(TopicSubscription(nodeTopic(SpbMessageType.nCmd), MqttQos.atLeastOnce));
    adapter.subscribeToTopic(TopicSubscription('${deviceTopic(SpbMessageType.dCmd, '')}+', MqttQos.atLeastOnce));
    var hostTopic = _hostTopic;
    if (hostTopic == null) {
      _birth();
      return;
    }
    _setState(EdgeNodeState.waitingForHost);
    adapter.subscribeToTopic(TopicSubscription(hostTopic, MqttQos.atLeastOnce));
  }

  void _scheduleRetry({Duration? delay}) {
    if (_stopped) {
      return;
    }
    _scanTimer?.cancel();
    var wait = delay ?? reconnectDelays[min(_attempt, reconnectDelays.length - 1)];
    _attempt++;
    _setState(EdgeNodeState.reconnecting);
    _retryTimer = Timer(wait, _connect);
  }

  void _onDisconnected(EventArgs? _) {
    if (_closing) {
      return;
    }
    // the broker or the network dropped the connection: the broker publishes the will, a new CONNECT follows
    _detach();
    _scheduleRetry();
  }

  void _close() {
    var adapter = _adapter;
    if (adapter == null) {
      return;
    }
    _closing = true;
    _detach();
    adapter.disconnect();
    _closing = false;
  }

  void _detach() {
    var adapter = _adapter;
    _adapter = null;
    adapter?.onDisconnectedEvent.unsubscribe(_onDisconnected);
    adapter?.messageReceivedEvent.unsubscribe(_onMessage);
  }

  void _setState(EdgeNodeState state) {
    if (_state != state) {
      _state = state;
      changedEvent.broadcast();
    }
  }

  // ---------- births and data ----------

  void _birth() {
    _seq = 0;
    var now = _now();
    _publish(
      nodeTopic(SpbMessageType.nBirth),
      SpbPayload(
        timestamp: now,
        seq: _nextSeq(),
        metrics: [
          SpbMetric(name: SparkplugProfile.bdSeqMetric, timestamp: now, datatype: SpbDataType.int64.code, value: bdSeq),
          SpbMetric(
            name: SparkplugProfile.rebirthMetric,
            alias: source.aliases ? 0 : null,
            timestamp: now,
            datatype: SpbDataType.boolean.code,
            value: false,
          ),
          for (var metric in _nodeMetrics) _definition(metric, now),
        ],
      ),
    );
    for (var device in _devices.where((device) => device.online)) {
      _deviceBirth(device);
    }
    _setState(EdgeNodeState.online);
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(Duration(milliseconds: source.scanMs), (_) => _scan());
  }

  void _deviceBirth(_Device device) {
    var now = _now();
    _publish(
      deviceTopic(SpbMessageType.dBirth, device.id),
      SpbPayload(
        timestamp: now,
        seq: _nextSeq(),
        metrics: [for (var metric in device.metrics) _definition(metric, now)],
      ),
    );
  }

  // a birth defines a metric: name, alias, data type, unit and the current value
  SpbMetric _definition(_Metric metric, int now) {
    metric.published = metric.value;
    var unit = metric.spec.unit;
    return SpbMetric(
      name: metric.spec.name,
      alias: metric.alias,
      timestamp: now,
      datatype: metric.spec.type.code,
      isNull: metric.value == null,
      value: metric.value,
      properties: unit == null || unit.isEmpty
          ? null
          : SpbPropertySet({'engUnit': SpbPropertyValue(type: SpbDataType.string.code, value: unit)}),
    );
  }

  // data by alias, or by name without aliases; the data type is in the birth
  SpbMetric _change(_Metric metric, int now) {
    metric.published = metric.value;
    return SpbMetric(
      name: metric.alias == null ? metric.spec.name : null,
      alias: metric.alias,
      timestamp: now,
      isNull: metric.value == null,
      value: metric.value,
      datatype: metric.alias == null ? metric.spec.type.code : null,
      encodeAs: metric.spec.type,
    );
  }

  void _sample(DateTime now, Duration elapsed) {
    for (var metric in [..._nodeMetrics, for (var device in _devices) ...device.metrics]) {
      if (metric.held) {
        continue;
      }
      var value = SparkplugValues.fromGenerated(metric.generator.next(now, elapsed), metric.spec, now);
      if (value != null) {
        metric.value = value;
      }
    }
  }

  void _scan() {
    var now = clock.now();
    _sample(now, now.difference(_lastScan));
    _lastScan = now;
    if (_state != EdgeNodeState.online) {
      return;
    }
    _publishChanges(nodeTopic(SpbMessageType.nData), _nodeMetrics);
    for (var device in _devices.where((device) => device.online)) {
      _publishChanges(deviceTopic(SpbMessageType.dData, device.id), device.metrics);
    }
  }

  void _publishChanges(String topic, List<_Metric> metrics, {bool all = false}) {
    var changed = [
      for (var metric in metrics)
        if (all || SparkplugValues.changed(metric.published, metric.value, metric.spec)) metric,
    ];
    if (changed.isEmpty) {
      return;
    }
    var now = _now();
    _publish(
      topic,
      SpbPayload(timestamp: now, seq: _nextSeq(), metrics: [for (var metric in changed) _change(metric, now)]),
    );
  }

  // ---------- commands and the host ----------

  void _onMessage(ReceivedMqttMessage? message) {
    if (message == null) {
      return;
    }
    var bytes = Uint8List.fromList(message.payload);
    if (message.topicName == _hostTopic) {
      _onHostState(bytes);
      return;
    }
    if (_state != EdgeNodeState.online) {
      return;
    }
    SpbPayload command;
    try {
      command = SparkplugReader.read(bytes);
    } on FormatException {
      return;
    }
    if (message.topicName == nodeTopic(SpbMessageType.nCmd)) {
      _onNodeCommand(command);
      return;
    }
    var prefix = deviceTopic(SpbMessageType.dCmd, '');
    var device = message.topicName.startsWith(prefix) ? _device(message.topicName.substring(prefix.length)) : null;
    if (device != null && device.online) {
      var written = _write(command, device.metrics);
      _publishChanges(deviceTopic(SpbMessageType.dData, device.id), written, all: true);
    }
  }

  void _onNodeCommand(SpbPayload command) {
    for (var metric in command.metrics) {
      var rebirth =
          metric.name == SparkplugProfile.rebirthMetric || (metric.name == null && source.aliases && metric.alias == 0);
      if (rebirth && metric.value == true) {
        _birth();
        return;
      }
    }
    var written = _write(command, _nodeMetrics);
    _publishChanges(nodeTopic(SpbMessageType.nData), written, all: true);
  }

  // writable metrics take the commanded value and keep it until the next write
  List<_Metric> _write(SpbPayload command, List<_Metric> metrics) {
    var written = <_Metric>[];
    for (var sent in command.metrics) {
      var metric = sent.name != null
          ? metrics.where((metric) => metric.spec.name == sent.name).firstOrNull
          : (_byAlias[sent.alias] != null && metrics.contains(_byAlias[sent.alias]) ? _byAlias[sent.alias] : null);
      if (metric != null && sent.datatype == null) {
        SparkplugReader.retype(sent, metric.spec.type);
      }
      var value = metric == null ? null : SparkplugValues.coerce(sent.value, metric.spec.type);
      if (metric != null && metric.spec.writable && value != null) {
        metric
          ..value = value
          ..held = true;
        written.add(metric);
      }
    }
    return written;
  }

  // 3.0: {"online": bool, "timestamp": ms}; an older STATE than the last one is ignored
  void _onHostState(Uint8List bytes) {
    Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return;
    }
    if (json is! Map || json['online'] is! bool) {
      return;
    }
    var timestamp = json['timestamp'];
    if (timestamp is num && _hostTimestamp != null && timestamp < _hostTimestamp!) {
      return;
    }
    if (timestamp is num) {
      _hostTimestamp = timestamp.toInt();
    }
    var online = json['online'] as bool;
    if (online && _state == EdgeNodeState.waitingForHost) {
      _birth();
    } else if (!online && _state == EdgeNodeState.online) {
      // the primary host is gone: leave with the NDEATH and connect again to wait for it
      _leave();
    }
  }

  // ---------- messages ----------

  Uint8List _deathPayload(int bdSeq) => SparkplugWriter.write(
    SpbPayload(
      metrics: [SpbMetric(name: SparkplugProfile.bdSeqMetric, datatype: SpbDataType.int64.code, value: bdSeq)],
    ),
  );

  void _publishDeath({int? withBdSeq}) {
    _adapter?.publish(
      nodeTopic(SpbMessageType.nDeath),
      Uint8Buffer()..addAll(_deathPayload(withBdSeq ?? bdSeq)),
      MqttPayloadType.binary,
      false,
      MqttQos.atLeastOnce,
    );
    messages++;
    onPublished?.call();
  }

  // NDEATH, disconnect, and a new connection with the next bdSeq after a second
  void _leave({int? withBdSeq}) {
    _publishDeath(withBdSeq: withBdSeq);
    _close();
    _scheduleRetry(delay: hostLostDelay);
  }

  int _nextSeq() {
    var seq = _seq;
    _seq = (_seq + 1) % 256;
    return seq;
  }

  int _now() => clock.now().millisecondsSinceEpoch;

  void _publish(String topic, SpbPayload payload) {
    var adapter = _adapter;
    if (adapter == null) {
      return;
    }
    if (_noTimestamp) {
      payload.timestamp = null;
    }
    var bytes = SparkplugWriter.write(payload);
    if (source.compress) {
      bytes = SparkplugWriter.write(
        SpbPayload(
          uuid: SparkplugProfile.compressedUuid,
          body: Uint8List.fromList(GZipEncoder().encode(bytes)),
          metrics: [SpbMetric(name: algorithmMetric, datatype: SpbDataType.string.code, value: 'GZIP')],
        ),
      );
    }
    adapter.publish(topic, Uint8Buffer()..addAll(bytes), MqttPayloadType.binary, false, MqttQos.atMostOnce);
    messages++;
    onPublished?.call();
  }

  // ---------- faults (doc/sparkplug-design.md §10.5) ----------

  bool isFaultActive(SparkplugFault fault) => switch (fault) {
    SparkplugFault.devicesOffline => _devices.isNotEmpty && _devices.every((device) => !device.online),
    SparkplugFault.dataAfterDeath => _dataAfterDeath,
    SparkplugFault.noTimestamp => _noTimestamp,
    _ => false,
  };

  // most faults need a born edge node; a toggled one can always be turned off
  bool isFaultAvailable(SparkplugFault fault) {
    if (fault.toggle && isFaultActive(fault)) {
      return true;
    }
    if (_state != EdgeNodeState.online) {
      return false;
    }
    return switch (fault) {
      SparkplugFault.devicesOffline => _devices.isNotEmpty,
      SparkplugFault.wrongDatatype => _allMetrics.isNotEmpty,
      SparkplugFault.dropConnection || SparkplugFault.restart || SparkplugFault.wrongBdSeqInDeath => !_dataAfterDeath,
      _ => true,
    };
  }

  List<_Metric> get _allMetrics => [..._nodeMetrics, for (var device in _devices) ...device.metrics];

  void inject(SparkplugFault fault) {
    if (!isFaultAvailable(fault)) {
      return;
    }
    switch (fault) {
      case SparkplugFault.dropConnection:
        _adapter?.dropConnection();
      case SparkplugFault.restart:
        _leave();
      case SparkplugFault.devicesOffline:
        var offline = !isFaultActive(fault);
        for (var device in _devices) {
          setDeviceOnline(device.id, !offline);
        }
      case SparkplugFault.skipSeq:
        _nextSeq();
      case SparkplugFault.unknownMetric:
        _publish(
          nodeTopic(SpbMessageType.nData),
          SpbPayload(
            timestamp: _now(),
            seq: _nextSeq(),
            metrics: [
              source.aliases
                  ? SpbMetric(alias: 65000, value: 1, encodeAs: SpbDataType.int32)
                  : SpbMetric(name: 'Unknown/Metric', datatype: SpbDataType.int32.code, value: 1),
            ],
          ),
        );
      case SparkplugFault.wrongDatatype:
        _publishWrongDatatype();
      case SparkplugFault.dataAfterDeath:
        _dataAfterDeath = !_dataAfterDeath;
        if (_dataAfterDeath) {
          _publishDeath();
        } else {
          // a new session announces itself again
          _birth();
        }
      case SparkplugFault.unbornDevice:
        _publish(
          deviceTopic(SpbMessageType.dData, 'UnbornDevice'),
          SpbPayload(
            timestamp: _now(),
            seq: _nextSeq(),
            metrics: [SpbMetric(name: 'Value', datatype: SpbDataType.int32.code, value: 1)],
          ),
        );
      case SparkplugFault.wrongBdSeqInDeath:
        _leave(withBdSeq: (bdSeq + 255) % 256);
      case SparkplugFault.noTimestamp:
        _noTimestamp = !_noTimestamp;
      case SparkplugFault.notSparkplug:
        _adapter?.publish(
          nodeTopic(SpbMessageType.nData),
          Uint8Buffer()..addAll(utf8.encode('{"temperature": 21}')),
          MqttPayloadType.binary,
          false,
          MqttQos.atMostOnce,
        );
        messages++;
        onPublished?.call();
    }
    changedEvent.broadcast();
  }

  // a metric with another data type than its birth said, on a device when there is one
  void _publishWrongDatatype() {
    var device = _devices.where((device) => device.online && device.metrics.isNotEmpty).firstOrNull;
    var metric = device?.metrics.first ?? _nodeMetrics.firstOrNull;
    if (metric == null) {
      return;
    }
    var other = metric.spec.type == SpbDataType.string ? SpbDataType.int32 : SpbDataType.string;
    var wrong = SpbMetric(
      name: metric.alias == null ? metric.spec.name : null,
      alias: metric.alias,
      timestamp: _now(),
      datatype: other.code,
      value: other == SpbDataType.string ? 'wrong' : 1,
    );
    _publish(
      device == null ? nodeTopic(SpbMessageType.nData) : deviceTopic(SpbMessageType.dData, device.id),
      SpbPayload(timestamp: _now(), seq: _nextSeq(), metrics: [wrong]),
    );
  }
}
