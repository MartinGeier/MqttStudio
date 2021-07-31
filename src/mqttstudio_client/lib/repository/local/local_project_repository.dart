import 'package:mqttstudio/model/project.dart';
import 'package:srx_flutter/srx_flutter.dart';

class LocalProjectRepository extends SrxLocalCrudRepository<Project, Project> {
  LocalProjectRepository() : super("projects", (json) => Project.fromJson(json), (json) => Project.fromJson(json));

  @override
  Future getChangedSinceLastSync(DateTime? lastSyncDate) {
    throw UnimplementedError();
  }
}
