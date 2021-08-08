import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/contoller/mqtt_controller.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:srx_flutter/srx_flutter.dart';

typedef void OnErrorFunction(String errorMessage);

class MqttGlobalViewmodel extends SrxChangeNotifier {
  final _controller = GetIt.I.get<MqttController>();
  bool isBusy = false;
  OnErrorFunction? onError;

  MqttGlobalViewmodel({this.onError}) {
    _controller.onConnected = _onConnected;
    _controller.onDisconnected = onDisconnected;
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
    notifyListeners();
  }

  onDisconnected() {
    notifyListeners();
  }

  void subscribeToTopic(String topic, MqttQos qos) {
    _controller.subscribeToTopic(topic, qos);
    notifyListeners();
  }

  void unSubscribeFromTopic(String topic) {
    _controller.unSubscribeFromTopic(topic);
    notifyListeners();
  }
}
