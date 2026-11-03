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
  // the adapter of a connect that is still running
  MqttAdapter? _connecting;
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

  // true once close() was called; a closed connection stays closed
  bool get isClosed => _closed;

  // Throws when the broker can't be reached; nothing is left open then. A reconnect leaves the same will.
  // When close() runs before the connection is made, the connection is closed again and this throws a
  // SideConnectionClosedError, a StateError that callers can tell from a broker error by it or by isClosed.
  Future<void> connect(MqttSettings settings, {MqttWill? will}) async {
    if (_closed) {
      throw SideConnectionClosedError();
    }
    var adapter = _factory();
    _connecting = adapter;
    try {
      await adapter.connect(settings, will: will);
    } catch (_) {
      _connecting = null;
      adapter.disconnect();
      if (_closed) {
        throw SideConnectionClosedError();
      }
      rethrow;
    }
    _connecting = null;
    if (_closed) {
      adapter.disconnect();
      throw SideConnectionClosedError();
    }
    _adapter = adapter;
    _settings = settings;
    _will = will;
  }

  // starts receiving: subscribe is called now and after every reconnect; does nothing once the connection is closed
  void listen(void Function(MqttAdapter adapter) subscribe) {
    if (_closed) {
      return;
    }
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
    // stops a connect that is still running; connect closes its connection if it gets made anyway
    _connecting?.disconnect();
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
    var adapter = _adapter!;
    try {
      await adapter.connect(_settings!, will: _will);
    } catch (_) {
      if (!_closed) {
        _scheduleReconnect();
      }
      return;
    }
    if (_closed) {
      // close() ran during the reconnect, before this connection was made
      adapter.disconnect();
      return;
    }
    _reconnecting = false;
    _subscribe?.call(adapter);
    reconnectedEvent.broadcast();
  }
}

// connect() was stopped by close()
class SideConnectionClosedError extends StateError {
  SideConnectionClosedError() : super('The connection was closed while connecting');
}
