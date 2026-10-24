import 'package:json_annotation/json_annotation.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/model/recorder_config.dart';

// use 'flutter pub run build_runner build' to run the code generator
part 'localstore_data.g.dart';

@JsonSerializable(explicitToJson: true)
class LocalStoreData {
  Map<String, Project>? projects;
  bool? browserPerformanceWarningDoNotShow = false;
  bool? newsletterSignpDoNotShow = false;
  bool? coachingCompleted = false;
  // the recordings folder chosen in the recorder tab, null = the default one
  String? recordingsFolder;
  // the record dialog opens with the last used settings
  RecorderConfig? lastRecorderConfig;
  // playback options per recording id, they are not stored in the recording itself
  Map<String, PlaybackOptions>? playbackOptions;

  LocalStoreData() {
    projects = Map<String, Project>();
  }

  Map<String, dynamic> toJson() => _$LocalStoreDataToJson(this);
  factory LocalStoreData.fromJson(Map<String, dynamic> json) => _$LocalStoreDataFromJson(json);
}
