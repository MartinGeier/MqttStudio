import '../models/srx_base_model.dart';

abstract class SrxReadOnlyRepository<T extends SrxBaseModel> {
  Future<T> get(String id);
  Future<List<T>> getAll();
}

abstract class SrxCrudRepository<T extends SrxBaseModel> implements SrxReadOnlyRepository<T> {
  Future<T> create(T model);
  Future<T> update(T model);
  Future delete(String id);
}

abstract class SrxSyncRepository<T extends SrxBaseModel> {
  Future clearAll();
  Future addAll(List<T> models);
  Future getChangedSinceLastSync(DateTime? lastSyncDate);
}

enum SrxRepositoryError { NotFound, DataIntegrityError, NoConnection, Unknown, Forbidden }

class SrxRepositoryException implements Exception {
  String errorMessage;
  SrxRepositoryError repositoryError;
  SrxRepositoryException(this.errorMessage, this.repositoryError);
}
