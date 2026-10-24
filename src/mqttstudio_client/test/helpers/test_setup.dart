import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/message_viewer/message_viewer.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/simulator/simulator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed_data/typed_buffers.dart';
import 'package:mqttstudio/recorder/engine/playback_service.dart';
import 'package:mqttstudio/recorder/engine/recorder_service.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';
import 'fake_mqtt_adapter.dart';

// Answer of the "project has not been saved" dialog: null = cancel, false = don't save, true = save
bool? closingNotSavedAnswer;
int closingNotSavedCount = 0;

// Registers the app services the way main.dart does, but with a fake MQTT adapter and in-memory shared preferences
FakeMqttAdapter setUpServices([FakeMqttAdapter? fakeAdapter]) {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  closingNotSavedAnswer = null;
  closingNotSavedCount = 0;

  var adapter = fakeAdapter ?? FakeMqttAdapter();
  GetIt.I.registerSingleton<MqttAdapter>(adapter);
  GetIt.I.registerSingleton(ProjectManager(() async {
    closingNotSavedCount++;
    return closingNotSavedAnswer;
  }));
  GetIt.I.registerSingleton(MessageViewer());
  GetIt.I.registerSingleton(Simulator());
  var library = RecordingLibrary(MemoryRecordingStore());
  GetIt.I.registerSingleton(library);
  GetIt.I.registerSingleton(RecorderService(library, connectionFactory: FakeMqttAdapter.new));
  GetIt.I.registerSingleton(PlaybackService(library));
  return adapter;
}

Future tearDownServices() => GetIt.I.reset();

Project createProject([String name = 'Test project']) =>
    Project(MqttSettings('test.mosquitto.org', 'client-1', 1883), name: name);

// Opens a new project in the ProjectManager, as the "New project" dialog does
Future<Project> openNewProject([String name = 'Test project']) async {
  var project = createProject(name);
  await GetIt.I.get<ProjectManager>().openProject(project);
  return project;
}

Uint8Buffer toPayload(String value) => Uint8Buffer()..addAll(utf8.encode(value));

ReceivedMqttMessage message(String topic, String payload, {DateTime? receivedOn, bool retain = false}) =>
    ReceivedMqttMessage(1, topic, toPayload(payload), MqttQos.atLeastOnce, receivedOn ?? DateTime.now(), retain);
