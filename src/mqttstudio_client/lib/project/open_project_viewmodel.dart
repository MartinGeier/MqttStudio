import 'package:mqttstudio/common/localstore.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../common/localstore.dart';

class OpenProjectViewmodel extends SrxChangeNotifier {
  List<Project> projects = [];

  OpenProjectViewmodel() {
    _loadProjects();
  }

  Future _loadProjects() async {
    projects = await LocalStore().getProjects();
    notifyListeners();
  }

  Future deleteProject(Project project) async {
    projects = await LocalStore().deleteProject(project);
    notifyListeners();
  }
}
