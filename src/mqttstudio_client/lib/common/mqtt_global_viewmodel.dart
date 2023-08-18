import 'package:get_it/get_it.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqttstudio/mqtt/mqtt_controller.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:srx_flutter/srx_flutter.dart';

class MqttGlobalViewmodel extends SrxChangeNotifier {
  final _controller = GetIt.I.get<MqttController>();
  final _refreshPeriod = 500;
  bool isBusy = false;
  DateTime _lastRefresh = DateTime.now();

  void Function(String errorMessage)? onError;
  void Function()? onDisconnected;
  void Function()? onConnected;
  void Function(ReceivedMqttMessage msg)? onMessageReceived;

  MqttGlobalViewmodel({this.onError, this.onConnected, this.onDisconnected, this.onMessageReceived}) {
    _controller.onConnected = _onConnected;
    _controller.onDisconnected = _onDisconnected;
    _controller.onMessageReceived = _onMessageReceived;
  }

  Future connect(MqttSettings mqttSettings) async {
    try {
      isBusy = true;
      notifyListeners();
      if (mqttSettings.hostname.trim().isNotEmpty && mqttSettings.clientId.trim().isNotEmpty) {
        await _controller.connect(mqttSettings);
      }
    } on SrxServiceException catch (exc) {
      if (onError != null) {
        onError!(exc.errorMessage);
      }
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  void disconnect() {
    _controller.disconnect();
    notifyListeners();
  }

  bool isConnected() {
    return _controller.isConnected();
  }

  _onConnected() {
    if (onConnected != null) {
      onConnected!();
    }
    notifyListeners();
  }

  _onDisconnected() {
    if (onDisconnected != null) {
      onDisconnected!();
    }
    notifyListeners();
  }

  void subscribeToTopic(String topic, MqttQos qos) {
    if (_controller.isConnected()) {
      _controller.subscribeToTopic(topic, qos);
      notifyListeners();
    }
  }

  void unSubscribeFromTopic(String topic) {
    if (_controller.isConnected()) {
      _controller.unSubscribeFromTopic(topic);
      notifyListeners();
    }
  }

  void publishTopic(String topic, dynamic payload, MqttPayloadType payloadType, bool retain, [MqttQos qos = MqttQos.atLeastOnce]) {
    if (_controller.isConnected()) {
      _controller.publish(topic, payload, payloadType, retain, qos);
    }
  }

  _onMessageReceived(ReceivedMqttMessage msg) {
    if (onMessageReceived != null) {
      onMessageReceived!(msg);
    }

    // limit rebuild frequency
    if (DateTime.now().subtract(Duration(milliseconds: _refreshPeriod)).isAfter(_lastRefresh)) {
      _lastRefresh = DateTime.now();
      notifyListeners();
    }
  }
}
