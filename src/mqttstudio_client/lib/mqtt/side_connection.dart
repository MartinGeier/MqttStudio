import 'dart:async';
import 'dart:math';
import 'package:event/event.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/mqtt/mqtt_will.dart';

// An MQTT connection of its own next to the app's main one, used by the recorder and the documentation's discovery
// (recorder R6, documentation T9). The topic viewer's subscriptions and the CONNECT button don't affect it. When the
// connection is lost it reconnects with growing delays and subscribes again, unless reconnect is off.
class SideConnection {
  static const List<Duration> reconnectDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  final MqttAdapter Function() _factory;
  final bool reconnect;

  final messageReceivedEvent = Event<ReceivedMqttMessage>();
  // the connection was lost; with reconnect, attempts follow until reconnectedEvent
  final lostEvent = Event();
  // a reconnect attempt is scheduled, reconnectAttempt counts them
  final reconnectingEvent = Event();
  // connected and subscribed again
  final reconnectedEvent = Event();
  final subscribeFailedEvent = Event<SubscribeFailedEventArgs>();

  MqttAdapter? _adapter;
  MqttSettings? _settings;
  MqttWill? _will;
  void Function(MqttAdapter adapter)? _subscribe;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _reconnecting = false;
  bool _closed = false;

  SideConnection(MqttAdapter Function() factory, {this.reconnect = true}) : _factory = factory;

  bool get isReconnecting => _reconnecting;

  int get reconnectAttempt => _reconnectAttempt;

  MqttAdapter? get adapter => _adapter;

  // throws when the broker can't be reached; nothing is left open then. A reconnect leaves the same will.
  Future<void> connect(MqttSettings settings, {MqttWill? will}) async {
    var adapter = _factory();
    try {
      await adapter.connect(settings, will: will);
    } catch (_) {
      adapter.disconnect();
      rethrow;
    }
    _adapter = adapter;
    _settings = settings;
    _will = will;
  }

  // starts receiving: subscribe is called now and after every reconnect
  void listen(void Function(MqttAdapter adapter) subscribe) {
    var adapter = _adapter!;
    _subscribe = subscribe;
    adapter.messageReceivedEvent.subscribe(_onMessage);
    adapter.onDisconnectedEvent.subscribe(_onDisconnected);
    adapter.subscribeFailedEvent.subscribe(_onSubscribeFailed);
    subscribe(adapter);
  }

  void close() {
    _closed = true;
    _reconnectTimer?.cancel();
    _reconnecting = false;
    var adapter = _adapter;
    if (adapter == null) {
      return;
    }
    adapter.messageReceivedEvent.unsubscribe(_onMessage);
    adapter.onDisconnectedEvent.unsubscribe(_onDisconnected);
    adapter.subscribeFailedEvent.unsubscribe(_onSubscribeFailed);
    adapter.disconnect();
  }

  // the project's settings with a client id of its own, so the broker doesn't drop the app's main connection
  static MqttSettings settingsFor(MqttSettings settings, String tag) {
    var copy = MqttSettings.fromJson(settings.toJson());
    var suffix = Random().nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    copy
      ..clientId = '${settings.clientId}-$tag-$suffix'
      ..cleanStart = true
      ..sessionExpiryInterval = 0;
    return copy;
  }

  void _onMessage(ReceivedMqttMessage? message) {
    if (message != null) {
      messageReceivedEvent.broadcast(message);
    }
  }

  void _onSubscribeFailed(SubscribeFailedEventArgs? args) {
    if (args != null) {
      subscribeFailedEvent.broadcast(args);
    }
  }

  void _onDisconnected(EventArgs? _) {
    if (_closed || _reconnecting) {
      return;
    }
    _reconnectAttempt = 0;
    _reconnecting = reconnect;
    lostEvent.broadcast();
    if (_reconnecting) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    var delay = reconnectDelays[min(_reconnectAttempt, reconnectDelays.length - 1)];
    _reconnectAttempt++;
    _reconnectTimer = Timer(delay, _reconnect);
    reconnectingEvent.broadcast();
  }

  Future<void> _reconnect() async {
    if (_closed) {
      return;
    }
    try {
      await _adapter!.connect(_settings!, will: _will);
    } catch (_) {
      if (!_closed) {
        _scheduleReconnect();
      }
      return;
    }
    if (_closed) {
      return;
    }
    _reconnecting = false;
    _subscribe?.call(_adapter!);
    reconnectedEvent.broadcast();
  }
}
