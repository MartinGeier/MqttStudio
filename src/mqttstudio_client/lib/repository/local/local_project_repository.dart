import 'package:mqttstudio/model/project.dart';
import 'package:srx_flutter/srx_flutter.dart';

class LocalProjectRepository extends SrxBaseLocalCrudRepository<Project> {
  LocalProjectRepository() : super("projects");

  Project createModel(Map<String, dynamic> json) {
    return Project.fromJson(json);
  }

  @override
  Future getChangedSinceLastSync(DateTime? lastSyncDate) {
    throw UnimplementedError();
  }
}
