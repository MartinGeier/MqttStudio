import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/contoller/mqtt_controller.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/viewmodel/message_buffer_viewmodel.dart';
import 'package:srx_flutter/srx_flutter.dart';

class MqttGlobalViewmodel extends SrxChangeNotifier {
  final _controller = GetIt.I.get<MqttController>();
  bool isBusy = false;
  late MessageBufferViewmodel _messageBufferViewmodel;

  void Function(String errorMessage)? onError;
  void Function()? onDisconnected;
  void Function()? onConnected;
  void Function(ReceivedMqttMessage msg)? onMessageReceived;

  MqttGlobalViewmodel({this.onError, this.onConnected, this.onDisconnected, this.onMessageReceived}) {
    _controller.onConnected = _onConnected;
    _controller.onDisconnected = _onDisconnected;
    _controller.onMessageReceived = _onMessageReceived;
    _messageBufferViewmodel = GetIt.I.get<MessageBufferViewmodel>();
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
    _controller.subscribeToTopic(topic, qos);
    notifyListeners();
  }

  void unSubscribeFromTopic(String topic) {
    _controller.unSubscribeFromTopic(topic);
    notifyListeners();
  }

  _onMessageReceived(ReceivedMqttMessage msg) {
    _messageBufferViewmodel.storeMessage(msg);
    notifyListeners();
  }
}
