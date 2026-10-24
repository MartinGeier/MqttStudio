import 'dart:convert';
import 'dart:typed_data';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/recorder/format/recording_writer.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/documentation/discovery_service.dart';
import 'package:mqttstudio/documentation/documentation_service.dart';
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
import 'package:mqttstudio/recorder/analysis/recording_analysis_service.dart';
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
  var library = RecordingLibrary(MemoryRecordingStore());
  GetIt.I.registerSingleton(library);
  GetIt.I.registerSingleton(Simulator());
  GetIt.I.registerSingleton(RecorderService(library, connectionFactory: FakeMqttAdapter.new));
  GetIt.I.registerSingleton(PlaybackService(library));
  GetIt.I.registerSingleton(RecordingAnalysisService(library));
  GetIt.I.registerSingleton(DocumentationService());
  GetIt.I.registerSingleton(DiscoveryService(connectionFactory: FakeMqttAdapter.new));
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

// Writes a finished recording with one message per topic, a second apart, into the library of setUpServices
Future<RecordingInfo> recordInLibrary(String name, List<String> topics) async {
  var library = GetIt.I.get<RecordingLibrary>();
  var file = await library.create(name, DateTime(2026, 10, 24));
  var writer = await RecordingWriter.start(
      file,
      RecordingHeader(
          id: name,
          startedAt: DateTime.utc(2026, 10, 24),
          filters: [RecorderFilter('plant/#')],
          broker: 'test.mosquitto.org:1883',
          protocol: MqttProtocolVersion.v5,
          clientId: 'client-1-rec-0001',
          appVersion: ''));
  for (var i = 0; i < topics.length; i++) {
    writer.addMessage(RecordedMessage(
        offsetMicros: i * 1000000, topic: topics[i], payload: Uint8List.fromList(utf8.encode('$i'))));
  }
  await writer.finish(name: name, durationMicros: topics.length * 1000000);
  library.finishedWriting(file.name);
  return (await library.list()).firstWhere((info) => info.id == name);
}

// Writes a finished recording with the given messages and markers (in offset order) into a library. It belongs to
// the project openNewProject() opens, so the recordings list shows it.
Future<RecordingInfo> writeRecording(RecordingLibrary library, String name, List<Object> entries,
    {int durationMicros = 0,
    List<RecorderFilter>? filters,
    List<Bookmark>? bookmarks,
    DateTime? startedAt,
    String? projectName = 'Test project'}) async {
  var file = await library.create(name, DateTime(2026, 10, 24));
  var writer = await RecordingWriter.start(
      file,
      RecordingHeader(
          id: name,
          startedAt: startedAt ?? DateTime.utc(2026, 10, 24, 8),
          filters: filters ?? [RecorderFilter('#')],
          broker: 'test.mosquitto.org:1883',
          protocol: MqttProtocolVersion.v5,
          clientId: 'client-1-rec-0001',
          projectName: projectName,
          appVersion: ''));
  for (var entry in entries) {
    if (entry is RecordedMessage) {
      writer.addMessage(entry);
    } else if (entry is RecordingMarker) {
      writer.addMarker(entry);
    }
  }
  await writer.finish(name: name, durationMicros: durationMicros, bookmarks: bookmarks);
  library.finishedWriting(file.name);
  return (await library.list()).firstWhere((info) => info.id == name);
}

RecordedMessage recorded(double seconds, String topic, String payload) => RecordedMessage(
    offsetMicros: (seconds * Duration.microsecondsPerSecond).round(),
    topic: topic,
    payload: Uint8List.fromList(utf8.encode(payload)));
