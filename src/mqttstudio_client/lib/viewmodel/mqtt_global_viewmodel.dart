import 'package:get_it/get_it.dart';
import 'package:mqttstudio/contoller/mqtt_controller.dart';
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

  Future connect(String? hostname, String? clientId, int port) async {
    try {
      isBusy = true;
      notifyListeners();
      if (hostname != null && hostname.trim().isNotEmpty && clientId != null && clientId.trim().isNotEmpty) {
        await _controller.connect(hostname, clientId, port);
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
}
