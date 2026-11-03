import 'package:event/event.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:srx_flutter/srx_flutter.dart';

// The last used projects, shown in the topic viewer while no project is open
class RecentProjectsViewmodel extends SrxChangeNotifier {
  static const int maxProjects = 6;

  final ProjectManager _projectManager = GetIt.I.get<ProjectManager>();
  List<Project> projects = [];
  bool isLoaded = false;
  // loads can overlap when the projects change while one runs; only the newest one sets the projects
  int _loadCount = 0;

  RecentProjectsViewmodel() {
    _projectManager.projectsChangedEvent.subscribe(_projectsChanged);
    _loadProjects();
  }

  @override
  void dispose() {
    _projectManager.projectsChangedEvent.unsubscribe(_projectsChanged);
    super.dispose();
  }

  Future _loadProjects() async {
    var load = ++_loadCount;
    List<Project> saved;
    try {
      saved = await _projectManager.getProjects();
    } catch (exc) {
      // unreadable saved projects show as none instead of a panel that never loads
      debugPrint('Loading the recent projects failed: $exc');
      saved = [];
    }
    if (load != _loadCount) {
      return;
    }
    projects = saved.take(maxProjects).toList();
    isLoaded = true;
    notifyListeners();
  }

  Future _projectsChanged(EventArgs _) async {
    await _loadProjects();
  }
}
