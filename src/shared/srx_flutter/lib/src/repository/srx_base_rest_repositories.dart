import 'package:srx_flutter/src/service/srx_http_service.dart';
import 'package:srx_flutter/src/service/srx_service_exception.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:uuid/uuid.dart';
import 'srx_repositories.dart';
import '../models/srx_base_model.dart';
import 'package:get_it/get_it.dart';
import 'package:easy_localization/easy_localization.dart';

abstract class SrxBaseRestReadOnlyRepository<T extends SrxBaseModel> implements SrxReadOnlyRepository<T> {
  final String entityUrl;

  SrxBaseRestReadOnlyRepository(this.entityUrl);

  T createModel(Map<String, dynamic> json);

  @override
  Future<T> get(String id) async {
    var httpService = GetIt.I.get<SrxHttpService>();
    try {
      var response = await httpService.get('$entityUrl/$id');
      return createModel(response.data);
    } on SrxServiceException catch (exc) {
      throw _getException(exc);
    } catch (exc) {
      throw SrxRepositoryException(exc.toString(), SrxRepositoryError.Unknown);
    }
  }

  @override
  Future<List<T>> getAll() async {
    var httpService = GetIt.I.get<SrxHttpService>();
    try {
      var response = await httpService.get('$entityUrl');
      List<T> result = [];
      for (var json in response.data) {
        result.add(createModel(json));
      }
      return result;
    } on SrxServiceException catch (exc) {
      throw _getException(exc);
    } catch (exc) {
      throw SrxRepositoryException(exc.toString(), SrxRepositoryError.Unknown);
    }
  }
}

abstract class SrxBaseRestCrudRepository<T extends SrxBaseModel> extends SrxBaseRestReadOnlyRepository<T> implements SrxCrudRepository<T> {
  SrxBaseRestCrudRepository(String entityUrl) : super(entityUrl);

  @override
  Future<T> create(T model) async {
    model.id = Uuid().v1();
    model.createdOn = DateTime.now();
    model.lastModifiedOn = model.createdOn;
    var httpService = GetIt.I.get<SrxHttpService>();
    try {
      var response = await httpService.post(entityUrl, data: model);
      model = createModel(response.data);
      return model;
    } on SrxServiceException catch (exc) {
      throw _getException(exc);
    } catch (exc) {
      throw SrxRepositoryException(exc.toString(), SrxRepositoryError.Unknown);
    }
  }

  @override
  Future delete(String id) async {
    var httpService = GetIt.I.get<SrxHttpService>();
    try {
      await httpService.delete('$entityUrl/$id');
    } on SrxServiceException catch (exc) {
      throw _getException(exc);
    } catch (exc) {
      throw SrxRepositoryException(exc.toString(), SrxRepositoryError.Unknown);
    }
  }

  @override
  Future<T> update(T model) async {
    model.lastModifiedOn = DateTime.now();
    var httpService = GetIt.I.get<SrxHttpService>();
    try {
      var response = await httpService.put(entityUrl, model);
      model = createModel(response.data);
      return model;
    } on SrxServiceException catch (exc) {
      throw _getException(exc);
    } catch (exc) {
      throw SrxRepositoryException(exc.toString(), SrxRepositoryError.Unknown);
    }
  }
}

Exception _getException(SrxServiceException exc) {
  switch (exc.serviceError) {
    case SrxServiceError.NoConnection:
      return SrxRepositoryException('srx.common.noconnection.error'.tr(), SrxRepositoryError.NoConnection);
    case SrxServiceError.Forbidden:
      return SrxRepositoryException('srx.common.forbidden.error'.tr(), SrxRepositoryError.Forbidden);
    case SrxServiceError.NotFound:
      return SrxRepositoryException('srx.common.notfound.error'.tr(), SrxRepositoryError.NotFound);
    case SrxServiceError.Conflict:
      return SrxRepositoryException('srx.common.dataintegrity.error'.tr(), SrxRepositoryError.DataIntegrityError);
    default:
      return SrxRepositoryException(exc.errorMessage, SrxRepositoryError.Unknown);
  }
}
