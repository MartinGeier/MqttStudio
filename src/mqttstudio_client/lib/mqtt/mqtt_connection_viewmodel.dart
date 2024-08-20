import 'package:get_it/get_it.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel for the MQTT connection. Notifies listeners about connection status changes.
// Offers basic operations such as connecting, disconnecting
class MqttConnectionViewmodel extends SrxChangeNotifier {
  final _mqttAdapter = GetIt.I.get<MqttAdapter>();
  bool isBusy = false;

  void Function(String errorMessage)? onError;

  ViewerMqttService() {
    _mqttAdapter.onConnectedEvent.subscribe((args) => _onConnected());
    _mqttAdapter.onDisconnectedEvent.subscribe((args) => _onDisconnected());
  }

  @override
  void dispose() {
    _mqttAdapter.onConnectedEvent.unsubscribeAll();
    _mqttAdapter.onDisconnectedEvent.unsubscribeAll();
    super.dispose();
  }

  Future connect(MqttSettings mqttSettings) async {
    try {
      isBusy = true;
      notifyListeners();
      if (mqttSettings.hostname.trim().isNotEmpty && mqttSettings.clientId.trim().isNotEmpty) {
        await _mqttAdapter.connect(mqttSettings);
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
    _mqttAdapter.disconnect();
    notifyListeners();
  }

  bool isConnected() {
    return _mqttAdapter.isConnected();
  }

  _onConnected() {
    notifyListeners();
  }

  _onDisconnected() {
    notifyListeners();
  }
}
