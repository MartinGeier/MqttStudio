import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:srx_flutter/srx_flutter.dart';

class OpenProjectViewmodel extends SrxChangeNotifier {
  final ProjectManager _projectManager = GetIt.I.get<ProjectManager>();
  List<Project> projects = [];

  OpenProjectViewmodel() {
    _loadProjects();
  }

  Future _loadProjects() async {
    projects = await _projectManager.getProjects();
    notifyListeners();
  }

  Future deleteProject(Project project) async {
    await _projectManager.deleteProject(project);
    await _loadProjects();
  }
}
