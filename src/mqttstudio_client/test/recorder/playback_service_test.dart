import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/recorder/engine/playback_service.dart';
import 'package:mqttstudio/recorder/engine/recording_player.dart';
import 'package:mqttstudio/recorder/format/recording_writer.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:typed_data/typed_buffers.dart';
import '../helpers/test_setup.dart';

class _Publisher implements SimulatorPublisher {
  final List<String> topics = [];
  @override
  bool isConnected = true;
  @override
  bool supportsProperties = true;

  @override
  void publish(String topic, Uint8Buffer payload, MqttQos qos, bool retain, MqttMessageProperties? properties) =>
      topics.add(topic);
}

// Windows can't delete a file another handle has open, so these tests run on real files
void main() {
  late Directory folder;
  late RecordingLibrary library;
  late _Publisher publisher;
  late PlaybackService playback;

  setUp(() async {
    setUpServices();
    folder = await Directory.systemTemp.createTemp('mqttrec');
    library = RecordingLibrary(FolderRecordingStore(folder));
    publisher = _Publisher();
    playback = PlaybackService(library, publisher: publisher);
  });

  tearDown(() async {
    playback.dispose();
    await tearDownServices();
    await folder.delete(recursive: true);
  });

  Future<RecordingInfo> record(List<int> offsetsMs) async {
    var file = await library.create('r', DateTime(2026, 10, 24));
    var writer = await RecordingWriter.start(
        file,
        RecordingHeader(
            id: 'r',
            startedAt: DateTime.utc(2026, 10, 24),
            filters: [RecorderFilter('plant/#')],
            broker: 'b:1883',
            protocol: MqttProtocolVersion.v5,
            clientId: 'c',
            appVersion: ''));
    for (var ms in offsetsMs) {
      writer.addMessage(
          RecordedMessage(offsetMicros: ms * 1000, topic: 'plant/a', payload: Uint8List.fromList(utf8.encode('$ms'))));
    }
    await writer.finish(name: 'r', durationMicros: (offsetsMs.last + 1) * 1000);
    library.finishedWriting(file.name);
    return (await library.list()).single;
  }

  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await Future.delayed(Duration(milliseconds: 20));
    }
  }

  test('a finished playback closes the file, so the recording can be deleted', () async {
    var info = await record([0, 10]);
    await playback.play(info, PlaybackOptions());
    await waitFor(() => playback.player == null);
    expect(publisher.topics, ['plant/a', 'plant/a']);
    expect(playback.state, PlaybackState.stopped);

    await library.delete(info);
    expect(await library.list(), isEmpty);
  });

  test('releasing a paused playback lets the recording be deleted', () async {
    var info = await record([0, 60000]);
    await playback.play(info, PlaybackOptions());
    await waitFor(() => publisher.topics.isNotEmpty);
    playback.pause();
    expect(playback.state, PlaybackState.paused);

    await playback.release(info.id);
    expect(playback.player, isNull);
    await library.delete(info);
    expect(await library.list(), isEmpty);
  });

  test('a file that is no recording is closed again after listing', () async {
    await File('${folder.path}${Platform.pathSeparator}broken.mqttrec').writeAsString('not a recording');
    expect(await library.list(), isEmpty);
    await File('${folder.path}${Platform.pathSeparator}broken.mqttrec').delete();
  });
}
