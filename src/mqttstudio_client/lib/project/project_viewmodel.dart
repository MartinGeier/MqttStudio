import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel for all project related operations.
class ProjectViewmodel extends SrxChangeNotifier {
  late ProjectManager _projectService;

  ProjectViewmodel() {
    _projectService = GetIt.I.get<ProjectManager>();
    _projectService.projectOpenedEvent.subscribe((_) => _projectOpened());
    _projectService.projectClosedEvent.subscribe((_) => _projectClosed());
  }

  @override
  void dispose() {
    _projectService.projectOpenedEvent.unsubscribeAll();
    _projectService.projectClosedEvent.unsubscribeAll();
    super.dispose();
  }

  Project? get currentProject => _projectService.currentProject;

  bool get isProjectOpen => _projectService.isProjectOpen;

  Future openProject(Project? newProject) async {
    await _projectService.openProject(newProject);
    notifyListeners();
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

  _projectOpened() {
    notifyListeners();
  }

  _projectClosed() {
    notifyListeners();
  }
}
