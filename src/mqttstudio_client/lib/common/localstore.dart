import 'dart:async';
import 'dart:convert';

import 'package:mqttstudio/model/localstore_data.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  static String localStoreKey = "localstore";

  LocalStoreData data = LocalStoreData();

  Future saveProject(Project project) async {
    await _readLocalStore();
    data.projects!.update(project.name, (_) => project, ifAbsent: () => project);

    await _saveLocalStore();
  }

  Future<List<Project>> getProjects() async {
    await _readLocalStore();
    return data.projects?.values.toList() ?? List.empty();
  }

  Future<List<Project>> deleteProject(Project project) async {
    await _readLocalStore();
    data.projects?.remove(project.name);
    await _saveLocalStore();
    return data.projects?.values.toList() ?? List.empty();
  }

  Future<bool> getBrowserPerformanceWarningDoNotShow() async {
    await _readLocalStore();
    return data.browserPerformanceWarningDoNotShow ?? false;
  }

  Future saveBrowserPerformanceWarningDoNotShow(bool value) async {
    await _readLocalStore();
    data.browserPerformanceWarningDoNotShow = value;

    await _saveLocalStore();
  }

  Future<bool> getNewsletterSignupDoNotShow() async {
    await _readLocalStore();
    return data.newsletterSignpDoNotShow ?? false;
  }

  Future saveNewsletterSignupDoNotShow(bool value) async {
    await _readLocalStore();
    data.newsletterSignpDoNotShow = value;

    await _saveLocalStore();
  }

  Future<bool> getCoachingCompleted() async {
    await _readLocalStore();
    return data.coachingCompleted ?? false;
  }

  Future saveCoachingCompleted(bool value) async {
    await _readLocalStore();
    data.coachingCompleted = value;

    await _saveLocalStore();
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
