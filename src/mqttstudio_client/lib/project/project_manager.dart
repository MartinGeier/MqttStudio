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
  // raised when a project is saved or deleted
  final projectsChangedEvent = Event();
  int? lastSavedProjectHash;
  // the name the current project was last saved under, null while it was never saved
  String? _savedName;
  final Future Function() _onClosingNotSaved;
  // asked before a project closes; one that returns false keeps it open, e.g. the recorder while recording
  final List<Future<bool> Function()> _closeGuards = [];

  ProjectManager(this._onClosingNotSaved) {
    _mqttAdapter = GetIt.I.get<MqttAdapter>();
  }

  void dispose() {
    _mqttAdapter.onConnectedEvent.unsubscribeAll();
  }

  Project? get currentProject => _currentProject;

  bool get isProjectOpen => _currentProject != null;

  // the dialog renames the project in place, saving it then replaces the entry under this name
  String? get savedProjectName => _savedName;

  void addCloseGuard(Future<bool> Function() guard) => _closeGuards.add(guard);

  void removeCloseGuard(Future<bool> Function() guard) => _closeGuards.remove(guard);

  // false when a close guard kept the current project open
  Future<bool> openProject(Project? newProject) async {
    // also disconnects from the broker, callers that want to stay connected reconnect after opening
    if (!await closeProject(true)) {
      return false;
    }

    _currentProject = newProject;
    _currentProject?.lastUsed = DateTime.now();
    // also a new project, so closing it without changes does not lose it; this keeps the hash to check for changes
    await saveProject();

    projectOpenedEvent.broadcast();
    return true;
  }

  Future<bool> closeProject([bool forceSave = false]) async {
    if (isProjectOpen) {
      for (var guard in List.of(_closeGuards)) {
        if (!await guard()) {
          return false;
        }
      }
    }
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
    _currentProject = null;
    _savedName = null;
    lastSavedProjectHash = null;
    projectClosedEvent.broadcast();
    return true;
  }

  Future saveProject() async {
    if (currentProject != null) {
      await LocalStore().saveProject(currentProject!, previousName: _savedName);
      _savedName = currentProject!.name;
      // the saved state is the new reference to check for changes
      lastSavedProjectHash = currentProject!.getHash();
      projectsChangedEvent.broadcast();
    }
  }

  // the names of the saved projects except the current one, a project can't be saved under them
  Future<Set<String>> otherProjectNames() async {
    return {
      for (var project in await LocalStore().getProjects())
        if (project.name != _savedName) project.name
    };
  }

  // the saved projects, last used first
  Future<List<Project>> getProjects() async {
    return _sortByLastUse(await LocalStore().getProjects());
  }

  // returns the remaining saved projects, last used first
  Future<List<Project>> deleteProject(Project project) async {
    var projects = _sortByLastUse(await LocalStore().deleteProject(project));
    projectsChangedEvent.broadcast();
    return projects;
  }

  List<Project> _sortByLastUse(List<Project> projects) {
    projects.sort((x, y) => (y.lastUsed ?? DateTime(2000, 1, 1)).compareTo(x.lastUsed ?? DateTime(2000, 1, 1)));
    return projects;
  }

  bool hasProjectChanged() {
    return currentProject?.getHash() != lastSavedProjectHash;
  }
}
