import 'dart:async';
import 'package:event/event.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';

// Manages all operations concerning projects
class ProjectManager {
  Project? _currentProject;
  late MqttAdapter _mqttAdapter;
  final projectOpenedEvent = Event();
  final projectClosedEvent = Event();
  int? lastSavedProjectHash;
  final Future Function() _onClosingNotSaved;

  ProjectManager(this._onClosingNotSaved) {
    _mqttAdapter = GetIt.I.get<MqttAdapter>();
  }

  void dispose() {
    _mqttAdapter.onConnectedEvent.unsubscribeAll();
  }

  Project? get currentProject => _currentProject;

  bool get isProjectOpen => _currentProject != null;

  Future openProject(Project? newProject) async {
    await closeProject(true);

    if (_mqttAdapter.isConnected()) {
      if (newProject == null) {
        _mqttAdapter.disconnect();
      } else if (_currentProject != null) {
        // if connection setting have been changed than reconnect
        _mqttAdapter.disconnect();
        _mqttAdapter.connect(newProject.mqttSettings);
      }
    }

    _currentProject = newProject;
    if (newProject?.lastUsed != null) {
      _currentProject?.lastUsed = DateTime.now();
      await saveProject();
    } else {
      _currentProject?.lastUsed = DateTime.now();
    }

    // keep the hash to check for changes
    lastSavedProjectHash = _currentProject?.getHash();

    projectOpenedEvent.broadcast();
  }

  Future<bool> closeProject([bool forceSave = false]) async {
    if (forceSave) {
      await saveProject();
    } else if (hasProjectChanged()) {
      var result = await _onClosingNotSaved();

      if (result == null) {
        return false;
      } else if (result != null && result) {
        await saveProject();
      }
    }

    _mqttAdapter.disconnect();
    projectClosedEvent.broadcast();
    _currentProject = null;
    lastSavedProjectHash = null;
    projectClosedEvent.broadcast();
    return true;
  }

  Future saveProject() async {
    if (currentProject != null) {
      await LocalStore().saveProject(currentProject!);
    }
  }

  bool hasProjectChanged() {
    return currentProject?.getHash() != lastSavedProjectHash;
  }
}
