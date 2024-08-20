import 'package:event/event.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/mqtt/mqtt_message_buffer.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Service for MQTT operations for message viewers. Receives messages from MQTTController and notifies listeners.
// Stores all received messages using MessageBuffer
class ViewerMqttService extends SrxChangeNotifier {
  final _mqttAdapter = GetIt.I.get<MqttAdapter>();
  final _refreshPeriod = 500;
  bool isBusy = false;
  DateTime _lastRefresh = DateTime.now();
  MQTTMessageBuffer messageBuffer = MQTTMessageBuffer();

  final onMessageReceivedEvent = Event<ReceivedMqttMessage>();

  ViewerMqttService() {
    _mqttAdapter.onMessageReceivedEvent.subscribe((args) => _onMessageReceived(args));
  }

  @override
  void dispose() {
    _mqttAdapter.onMessageReceivedEvent.unsubscribeAll();
    super.dispose();
  }

  void clearMessages() {
    messageBuffer.clear();
    notifyListeners();
  }

  void subscribeToTopic(String topic, MqttQos qos) {
    if (_mqttAdapter.isConnected()) {
      _mqttAdapter.subscribeToTopic(topic, qos);
      notifyListeners();
    }
  }

  void unSubscribeFromTopic(String topic) {
    if (_mqttAdapter.isConnected()) {
      _mqttAdapter.unSubscribeFromTopic(topic);
      notifyListeners();
    }
  }

  void publishTopic(String topic, dynamic payload, MqttPayloadType payloadType, bool retain, [MqttQos qos = MqttQos.atLeastOnce]) {
    if (_mqttAdapter.isConnected()) {
      _mqttAdapter.publish(topic, payload, payloadType, retain, qos);
    }
  }

  // called by the view to delay any updating of the view. Used to prevent the view updating during scrolling
  void delayViewUpdate() {
    _lastRefresh = DateTime.now();
  }

  _onMessageReceived(ReceivedMqttMessage msg) {
    messageBuffer.storeMessage(msg);

    onMessageReceivedEvent.broadcast(msg);

    // limit rebuild frequency
    if (DateTime.now().subtract(Duration(milliseconds: _refreshPeriod)).isAfter(_lastRefresh)) {
      _lastRefresh = DateTime.now();
      notifyListeners();
    }
  }
}
