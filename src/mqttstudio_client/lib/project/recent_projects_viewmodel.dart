import 'package:event/event.dart';
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
  bool _disposed = false;

  RecentProjectsViewmodel() {
    _projectManager.projectDeletedEvent.subscribe(_projectDeleted);
    _loadProjects();
  }

  @override
  void dispose() {
    _disposed = true;
    _projectManager.projectDeletedEvent.unsubscribe(_projectDeleted);
    super.dispose();
  }

  Future _loadProjects() async {
    var saved = await _projectManager.getProjects();
    // the panel goes away when a project opens, possibly before the projects are loaded
    if (_disposed) {
      return;
    }
    projects = saved.take(maxProjects).toList();
    isLoaded = true;
    notifyListeners();
  }

  Future _projectDeleted(EventArgs _) async {
    await _loadProjects();
  }
}
