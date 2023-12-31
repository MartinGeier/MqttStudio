import 'package:json_annotation/json_annotation.dart';
import 'package:mqttstudio/model/project.dart';

// use 'flutter pub run build_runner build' to run the code generator
part 'localstore_data.g.dart';

@JsonSerializable(explicitToJson: true)
class LocalStoreData {
  Map<String, Project>? projects;
  bool? browserPerformanceWarningDoNotShow = false;
  bool? newsletterSignpDoNotShow = false;
  bool? coachingCompleted = false;

  LocalStoreData() {
    projects = Map<String, Project>();
  }

  Map<String, dynamic> toJson() => _$LocalStoreDataToJson(this);
  factory LocalStoreData.fromJson(Map<String, dynamic> json) => _$LocalStoreDataFromJson(json);
}
