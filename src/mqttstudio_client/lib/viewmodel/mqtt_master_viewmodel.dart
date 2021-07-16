import 'package:get_it/get_it.dart';
import 'package:mqttstudio_client/contoller/mqtt_controller.dart';
import 'package:srx_flutter/srx_flutter.dart';

class MqttMasterViewmodel extends SrxChangeNotifier {
  final _controller = GetIt.I.get<MqttController>();
  String? hostname;
  String? clientId;

  MqttMasterViewmodel() {
    _controller.onConnected = _onConnected;
    _controller.onDisconnected = onDisconnected;
  }

  Future connect() async {
    if (hostname != null && hostname!.trim().isNotEmpty && clientId != null && clientId!.trim().isNotEmpty) {
      await _controller.connect(hostname!, clientId!);
    }
    notifyListeners();
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
}
