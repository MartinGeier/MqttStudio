import 'package:event/event.dart';
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

  MqttConnectionViewmodel() {
    _mqttAdapter.onConnectedEvent.subscribe(_onConnected);
    _mqttAdapter.onDisconnectedEvent.subscribe(_onDisconnected);
  }

  @override
  void dispose() {
    // only remove our own handlers, the events are shared with other services and viewmodels
    _mqttAdapter.onConnectedEvent.unsubscribe(_onConnected);
    _mqttAdapter.onDisconnectedEvent.unsubscribe(_onDisconnected);
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

  void _onConnected(EventArgs _) {
    notifyListeners();
  }

  void _onDisconnected(EventArgs _) {
    notifyListeners();
  }
}
