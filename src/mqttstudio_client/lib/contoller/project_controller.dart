import 'package:mqttstudio/model/project.dart';
import 'package:srx_flutter/srx_flutter.dart';

class ProjectController extends SrxChangeNotifier {
  Project? _currentProject;

  Project? get currentProject => _currentProject;

  set currentProject(Project? value) {
    _currentProject = value;
    notifyListeners();
  }

  bool get isProjectOpen => _currentProject != null;
}
