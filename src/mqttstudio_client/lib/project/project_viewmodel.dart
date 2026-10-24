import 'dart:async';
import 'package:event/event.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel for all project related operations.
class ProjectViewmodel extends SrxChangeNotifier {
  late ProjectManager _projectService;

  ProjectViewmodel() {
    _projectService = GetIt.I.get<ProjectManager>();
    _projectService.projectOpenedEvent.subscribe(_projectOpened);
    _projectService.projectClosedEvent.subscribe(_projectClosed);
  }

  @override
  void dispose() {
    // only remove our own handlers, the events are shared with other services and viewmodels
    _projectService.projectOpenedEvent.unsubscribe(_projectOpened);
    _projectService.projectClosedEvent.unsubscribe(_projectClosed);
    super.dispose();
  }

  Project? get currentProject => _projectService.currentProject;

  bool get isProjectOpen => _projectService.isProjectOpen;

  // false when the current project stayed open, e.g. because the user kept a recording running
  Future<bool> openProject(Project? newProject) async {
    var opened = await _projectService.openProject(newProject);
    notifyListeners();
    return opened;
  }

  Future<bool> closeProject([bool forceSave = false]) async {
    bool result = await _projectService.closeProject(forceSave);
    if (result) {
      notifyListeners();
    }
    return result;
  }

  Future saveProject() async {
    await _projectService.saveProject();
  }

  void _projectOpened(EventArgs _) {
    notifyListeners();
  }

  void _projectClosed(EventArgs _) {
    notifyListeners();
  }
}
