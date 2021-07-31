import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/viewmodel/mqtt_global_viewmodel.dart';
import 'package:srx_flutter/srx_flutter.dart';

class ProjectGlobalViewmodel extends SrxChangeNotifier {
  Project? _currentProject;

  Project? get currentProject => _currentProject;

  bool get isProjectOpen => _currentProject != null;

  void openProject(Project? newProject) {
    if (GetIt.I.get<MqttGlobalViewmodel>().isConnected()) {
      if (newProject == null) {
        GetIt.I.get<MqttGlobalViewmodel>().disconnect();
      } else if (_currentProject != null && _currentProject!.mqttSettings.connectionSettingsChanged(newProject.mqttSettings)) {
        // if connection setting have been changed than reconnect
        var mqttGlobalViewmodel = GetIt.I.get<MqttGlobalViewmodel>();
        mqttGlobalViewmodel.disconnect();
        mqttGlobalViewmodel.connect(newProject.mqttSettings);
      }
    }

    _currentProject = newProject;
    notifyListeners();
  }

  void closeProject() {
    _currentProject = null;
    notifyListeners();
  }
}
