import 'dart:async';
import '../repository/srx_repositories.dart';
import '../controller/srx_session_controller.dart';
import '../models/srx_base_model.dart';
import '../service/srx_service_error.dart';
import '../service/srx_service_exception.dart';
import '../viewmodels/srx_changenotifier.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:easy_localization/easy_localization.dart';

// use this viewmodel as base class when data needs to be loaded but it is not a simple list
abstract class SrxBaseLoadingViewModel extends SrxChangeNotifier {
  var isBusy = false;
  var isError = false;
  String? errorMessage;

  SrxBaseLoadingViewModel() {
    loadData();
  }

  Future loadData() async {
    try {
      isBusy = true;
      notifyListeners();
      await retrieveData();
      isError = false;
    } on SrxRepositoryException catch (exc) {
      errorMessage = exc.errorMessage;
      isError = true;
    } on SrxServiceException catch (exc) {
      errorMessage = exc.errorMessage;
      isError = true;
    } catch (exc) {
      errorMessage = exc.toString();
      isError = true;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future retrieveData();
}

// use this viewmodel when a list of items needs to be loaded
class SrxListViewModel<T extends SrxBaseModel> extends SrxChangeNotifier {
  var items = List<T>.empty(growable: true);
  var isBusy = false;
  var isError = false;
  String? errorMessage;

  SrxListViewModel() {
    loadData();
  }

  Future loadData() async {
    try {
      isBusy = true;
      notifyListeners();
      items = await retrieveData();
      isError = false;
    } on SrxRepositoryException catch (exc) {
      errorMessage = exc.errorMessage;
      isError = true;
    } catch (exc) {
      errorMessage = exc.toString();
      isError = true;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<List<T>> retrieveData() async {
    final SrxReadOnlyRepository<T> repository = GetIt.instance.get<SrxReadOnlyRepository<T>>();
    return (await repository.getAll()).cast<T>();
  }

  Future delete(String id) async {
    try {
      isBusy = true;
      notifyListeners();
      final SrxCrudRepository<T> repository = GetIt.instance.get<SrxCrudRepository<T>>();
      await repository.delete(id);
      items.removeWhere((element) => element.id == id);
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }
}

typedef bool FilterFunction<T extends SrxBaseModel>(T item, String searchTerm);

class SrxDataTableViewModel<T extends SrxBaseModel> extends SrxListViewModel<T> {
  List<T> _selectedItems = [];
  String? _searchTerm;
  FilterFunction? filterItems;

  void toggleItemSelection(int itemIndex, {bool enableMultipleSelection = false}) {
    T item = items[itemIndex];
    if (_selectedItems.contains(item)) {
      _selectedItems.remove(item);
    } else {
      if (!enableMultipleSelection) {
        _selectedItems.clear(); // do not allow multiple selection
      }
      _selectedItems.add(item);
    }

    notifyListeners();
  }

  List<int> get selectedItems {
    return List<int>.generate(_selectedItems.length, (i) => items.indexOf(_selectedItems[i]));
  }

  void sort(int columnIndex, bool sortAscending) {
    throw UnimplementedError();
  }

  set searchTerm(String? value) {
    if (filterItems == null) {
      throw Exception('Search term cannot be set without a search function!');
    }
    _searchTerm = value?.toLowerCase();
    notifyListeners();
  }

  String? get seachTerm => _searchTerm;

  @override
  List<T> get items {
    if (_searchTerm != null && _searchTerm!.isNotEmpty && filterItems != null) {
      return super.items.where((x) => filterItems!(x, seachTerm!)).toList();
    } else {
      return super.items;
    }
  }
}

// use this viewmodel as base class if you need build a form
abstract class SrxBaseFormViewModel<T extends SrxBaseModel> extends SrxChangeNotifier {
  var isBusy = false;
  var isError = false;
  String? errorMessage;
  final SrxCrudRepository<T> _repository = GetIt.instance.get<SrxCrudRepository<T>>();
  T? model;
  late FormGroup form;

  SrxBaseFormViewModel(String? modelId) {
    form = buildFormGroup();
    if (modelId != null) {
      loadModel(modelId: modelId);
    }
  }

  FormGroup buildFormGroup();

  Future loadModel({String? modelId}) async {
    try {
      isBusy = true;
      notifyListeners();
      model = await retrieveData(modelId != null ? modelId : model!.id!);
      fromModel();
      isError = false;
    } on SrxRepositoryException catch (exc) {
      errorMessage = exc.errorMessage;
      isError = true;
    } on SrxServiceException catch (exc) {
      isError = true;
      switch (exc.serviceError) {
        case SrxServiceError.NoConnection:
          errorMessage = 'srx.common.noconnection.error'.tr();
          break;
        case SrxServiceError.InvalidCredentials:
          errorMessage = 'srx.common.invalidcredentials.error'.tr();
          break;
        default:
          errorMessage = exc.errorMessage;
      }
    } catch (exc) {
      errorMessage = exc.toString();
      isError = true;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<T> retrieveData(String modelId) async {
    return await _repository.get(modelId);
  }

  Future<bool> saveModel({bool validateForm = true}) async {
    if (validateForm) {
      form.markAllAsTouched();
      if (!form.valid) {
        return false;
      }
    }

    try {
      isBusy = true;
      notifyListeners();
      toModel();
      try {
        if (model!.id != null) {
          model = await _repository.update(model!);
        } else {
          model = await _repository.create(model!);
        }
        return true;
      } finally {
        fromModel();
      }
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  void fromModel();

  void toModel();
}

class SrxLoginFormViewModel extends SrxChangeNotifier {
  static String usernameField = 'username';
  static String passwordField = 'password';

  var isBusy = false;
  var isError = false;
  var _isObscureText = true;
  String? errorMessage;
  late FormGroup form;
  SrxSessionController sessionController;

  get isPasswordObscureText => _isObscureText;
  set isPasswordObscureText(value) {
    _isObscureText = value;
    notifyListeners();
  }

  SrxLoginFormViewModel(this.sessionController) {
    form = buildFormGroup();
  }

  FormGroup buildFormGroup() {
    return FormGroup({
      usernameField:
          FormControl<String>(value: kDebugMode ? 'fieldservicepartnerdispatcher@nowhere.com' : null, validators: [Validators.required]),
      passwordField: FormControl<String>(value: kDebugMode ? 'Backend.Password.1' : null, validators: [Validators.required]),
    });
  }

  Future login() async {
    try {
      isBusy = true;
      isError = false;
      notifyListeners();
      await sessionController.login(form.control(usernameField).value, form.control(passwordField).value);
    } on SrxServiceException catch (exc) {
      isError = true;
      switch (exc.serviceError) {
        case SrxServiceError.NoConnection:
          errorMessage = 'srx.common.noconnection.error'.tr();
          break;
        case SrxServiceError.InvalidCredentials:
          errorMessage = 'srx.common.invalidcredentials.error'.tr();
          break;
        default:
          errorMessage = exc.errorMessage;
      }
    } catch (exc) {
      isError = true;
      errorMessage = exc.toString();
    } finally {
      isBusy = false;
      if (isError) {
        notifyListeners();
      }
    }
  }
}
