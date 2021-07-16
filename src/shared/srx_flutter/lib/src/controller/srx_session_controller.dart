import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'srx_local_database_controller.dart';
import '../models/srx_session.dart';
import '../service/srx_http_service.dart';
import '../service/srx_navigation_service.dart';
import 'package:get_it/get_it.dart';
import 'package:sembast/sembast.dart';

class SrxSessionController {
  final _storeName = "session";
  final _sessionKey = "sessionKey";
  final useLocalDb;
  SrxSessionController(this.useLocalDb);

  SrxSession? _session;

  SrxSession? get session => _session;
  bool get isLoggedIn => _session != null;

  Future login(String username, String password) async {
    var httpService = GetIt.instance.get<SrxHttpService>();
    var token = await httpService.getToken(username, password);
    _session = SrxSession.fromToken(token);
    await _storeSession();
    await GetIt.I.get<SrxNavigationService>().popOrHomeView();
  }

  Future logout() async {
    _session = null;
    if (useLocalDb) {
      var db = GetIt.I.get<SrxLocalDatabaseController>().database;
      var store = stringMapStoreFactory.store(_storeName);
      await store.record(_sessionKey).delete(db);
    } else {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString(_sessionKey, '');
    }

    await GetIt.I.get<SrxNavigationService>().navigateToLogin();
  }

  Future restoreSession() async {
    if (useLocalDb) {
      var db = GetIt.I.get<SrxLocalDatabaseController>().database;
      var store = stringMapStoreFactory.store(_storeName);
      var json = await store.record(_sessionKey).get(db);
      if (json != null) {
        _session = SrxSession.fromJson(json);
      }
    } else {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      var value = prefs.getString(_sessionKey);
      if (value != null && value != '') {
        _session = SrxSession.fromJson(json.decode(value));
      }
    }
  }

  Future _storeSession() async {
    if (useLocalDb) {
      var db = GetIt.I.get<SrxLocalDatabaseController>().database;
      var store = stringMapStoreFactory.store(_storeName);
      if (_session != null) {
        await store.record(_sessionKey).put(db, _session!.toJson());
      }
    } else {
      if (_session != null) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        prefs.setString(_sessionKey, json.encode(_session!.toJson()));
      }
    }
  }
}
