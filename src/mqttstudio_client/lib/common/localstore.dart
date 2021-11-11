import 'dart:async';
import 'dart:convert';

import 'package:mqttstudio/model/localstore_data.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  static String localStoreKey = "localstore";

  LocalStoreData data = LocalStoreData();

  void saveProject(Project project) async {
    await _readLocalStore();
    data.projects!.update(project.name, (_) => project, ifAbsent: () => project);

    await _saveLocalStore();
  }

  Future<List<Project>> getProjects() async {
    await _readLocalStore();
    return data.projects?.values.toList() ?? List.empty();
  }

  FutureOr<LocalStoreData> _readLocalStore() async {
    var sp = await SharedPreferences.getInstance();
    var json = sp.getString(localStoreKey);
    if (json == null) {
      data = LocalStoreData();
    } else {
      data = LocalStoreData.fromJson(jsonDecode(json));
    }

    return Future.value(data);
  }

  Future _saveLocalStore() async {
    var sp = await SharedPreferences.getInstance();
    await sp.setString(localStoreKey, jsonEncode(data.toJson()));
  }
}
