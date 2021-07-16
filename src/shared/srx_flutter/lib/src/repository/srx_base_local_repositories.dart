import 'srx_repositories.dart';
import '../controller/srx_local_database_controller.dart';
import '../models/srx_base_model.dart';
import 'package:get_it/get_it.dart';
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

abstract class SrxBaseLocalReadOnlyRepository<T extends SrxBaseModel> implements SrxReadOnlyRepository<T>, SrxSyncRepository<T> {
  final storeName;

  SrxBaseLocalReadOnlyRepository(this.storeName);

  T createModel(Map<String, dynamic> json);

  @override
  Future<T> get(String id) async {
    var db = GetIt.instance.get<SrxLocalDatabaseController>().database;
    var store = stringMapStoreFactory.store(storeName);
    var result = await store.record(id).get(db);
    if (result == null) {
      throw SrxRepositoryException("Record not found!", SrxRepositoryError.NotFound);
    }

    var model = createModel(result);
    return model;
  }

  @override
  Future<List<T>> getAll() async {
    var db = GetIt.instance.get<SrxLocalDatabaseController>().database;
    var store = stringMapStoreFactory.store(storeName);
    var records = await store.find(db);
    List<T> items = [];
    for (var r in records) {
      items.add(createModel(r.value));
    }

    return items;
  }

  Future clearAll() async {
    var db = GetIt.instance.get<SrxLocalDatabaseController>().database;
    var store = stringMapStoreFactory.store(storeName);
    await store.delete(db);
  }

  Future addAll(List<T> models) async {
    var db = GetIt.instance.get<SrxLocalDatabaseController>().database;
    var store = stringMapStoreFactory.store(storeName);
    for (T model in models) {
      await store.record(model.id!).add(db, model.toJson());
    }
  }
}

abstract class SrxBaseLocalCrudRepository<T extends SrxBaseModel> extends SrxBaseLocalReadOnlyRepository<T>
    implements SrxCrudRepository<T> {
  SrxBaseLocalCrudRepository(String storeName) : super(storeName);

  @override
  Future<T> create(T model) async {
    var db = GetIt.instance.get<SrxLocalDatabaseController>().database;
    var store = stringMapStoreFactory.store(storeName);
    model.id = Uuid().v1();
    model.createdOn = DateTime.now();
    model.lastModifiedOn = DateTime.now();
    var result = await store.record(model.id!).add(db, model.toJson());
    if (result == null) {
      throw SrxRepositoryException('Trying to add duplicate record!', SrxRepositoryError.DataIntegrityError);
    }

    return model;
  }

  @override
  Future delete(String id) async {
    var db = GetIt.instance.get<SrxLocalDatabaseController>().database;
    var store = stringMapStoreFactory.store(storeName);
    await store.record(id).delete(db);
  }

  @override
  Future<T> update(T model) async {
    var db = GetIt.instance.get<SrxLocalDatabaseController>().database;
    var store = stringMapStoreFactory.store(storeName);
    if (model.id == null) {
      throw SrxRepositoryException('Unable to update record. Model has never been saved!', SrxRepositoryError.NotFound);
    }

    model.lastModifiedOn = DateTime.now();

    var result = await store.record(model.id!).update(db, model.toJson());
    if (result == null) {
      throw SrxRepositoryException('Unable to update record! Record not found.', SrxRepositoryError.NotFound);
    }

    return model;
  }
}
