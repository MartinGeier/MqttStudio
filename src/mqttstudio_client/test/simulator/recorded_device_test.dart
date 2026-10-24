import 'dart:convert';
import 'dart:typed_data';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/recorder/format/recording_writer.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:mqttstudio/simulator/engine/simulator_runner.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:typed_data/typed_buffers.dart';

class _Sent {
  final String topic;
  final String payload;
  final Duration at;

  _Sent(this.topic, this.payload, this.at);
}

class _Publisher implements SimulatorPublisher {
  final FakeAsync async;
  final List<_Sent> sent = [];
  @override
  bool isConnected = true;
  @override
  bool supportsProperties = true;

  _Publisher(this.async);

  @override
  void publish(String topic, Uint8Buffer payload, MqttQos qos, bool retain, MqttMessageProperties? properties) =>
      sent.add(_Sent(topic, utf8.decode(payload, allowMalformed: true), async.elapsed));

  List<String> topics() => sent.map((s) => s.topic).toSet().toList()..sort();
}

void main() {
  late MemoryRecordingStore store;

  setUp(() => store = MemoryRecordingStore());

  // a recording of plant/a every second for 3 s and plant/b once
  void record(FakeAsync async) {
    () async {
      var writer = await RecordingWriter.start(
          await store.create('line.mqttrec'),
          RecordingHeader(
              id: 'line',
              startedAt: DateTime.utc(2026, 10, 24),
              filters: [RecorderFilter('plant/#')],
              broker: 'b',
              protocol: MqttProtocolVersion.v5,
              clientId: 'c',
              appVersion: ''));
      for (var s = 0; s < 3; s++) {
        writer.addMessage(
            RecordedMessage(offsetMicros: s * 1000000, topic: 'plant/a', payload: Uint8List.fromList(utf8.encode('$s'))));
      }
      writer.addMessage(RecordedMessage(offsetMicros: 1500000, topic: 'plant/b', payload: Uint8List.fromList([0xff, 0xfe])));
      await writer.finish(name: 'Line', durationMicros: 3000000);
    }();
    async.flushMicrotasks();
  }

  SimulatedDevice device({int instances = 1, InstanceStart start = InstanceStart.aligned, PlaybackOptions? playback}) =>
      SimulatedDevice(
          name: 'Line',
          instanceCount: instances,
          kind: DeviceKind.recorded,
          recorded: RecordedSource(
              recordingId: 'line',
              fileName: 'line.mqttrec',
              recordingName: 'Line',
              playback: playback ?? PlaybackOptions(remaps: [TopicRemap('plant/', 'test/{n}/')]),
              instanceStart: start));

  SimulatorRunner runnerFor(_Publisher publisher) =>
      SimulatorRunner(publisher, seed: 1, openRecording: (source) => store.open(source.fileName));

  test('plays the recording once per instance with {n} resolved and counts per recorded topic', () {
    fakeAsync((async) {
      record(async);
      var publisher = _Publisher(async);
      var runner = runnerFor(publisher);
      var line = device(instances: 3);

      runner.startDevice(line);
      async.flushMicrotasks();
      expect(runner.isDeviceRunning(line.id), isTrue);
      expect(runner.isAnyRunning, isTrue);
      expect(runner.runningRate, closeTo(3 * 4 / 3, 0.01));
      async.elapse(const Duration(seconds: 5));

      expect(publisher.topics(), ['test/1/a', 'test/1/b', 'test/2/a', 'test/2/b', 'test/3/a', 'test/3/b']);
      expect(publisher.sent.where((s) => s.topic == 'test/2/a').map((s) => s.at.inSeconds), [0, 1, 2]);
      var stats = runner.recordedStatsOf(line.id, 'plant/a');
      expect(stats.sent, 9);
      expect(stats.lastPayload, '2');
      expect(runner.recordedStatsOf(line.id, 'plant/b').lastPayload, '<binary 0.0 KB>');
      expect(runner.recordedTopicsOf(line.id), ['plant/a', 'plant/b']);
      expect(runner.deviceStatsOf(line.id).sent, 12);
      // all instances reached the end
      expect(runner.isDeviceRunning(line.id), isFalse);
      expect(runner.totalSent, greaterThanOrEqualTo(12));
      runner.dispose();
    });
  });

  test('staggered instances start within one interval of a topic, loop keeps them running until stopped', () {
    fakeAsync((async) {
      record(async);
      var publisher = _Publisher(async);
      var runner = runnerFor(publisher);
      var line = device(
          instances: 2,
          start: InstanceStart.staggered,
          playback: PlaybackOptions(loop: true, remaps: [TopicRemap('plant/', 'test/{n}/')]));
      runner.startDevice(line);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));
      expect(runner.isDeviceRunning(line.id), isTrue);
      var firsts = [for (var n = 1; n <= 2; n++) publisher.sent.firstWhere((s) => s.topic == 'test/$n/a').at];
      expect(firsts.every((at) => at <= const Duration(milliseconds: 1500)), isTrue);

      runner.stopDevice(line);
      var count = publisher.sent.length;
      async.elapse(const Duration(seconds: 5));
      expect(publisher.sent.length, count);
      expect(runner.isDeviceRunning(line.id), isFalse);
      runner.dispose();
    });
  });

  test('a missing recording is an error of the device', () {
    fakeAsync((async) {
      var runner = runnerFor(_Publisher(async));
      var line = device();
      runner.startDevice(line);
      async.flushMicrotasks();
      expect(runner.isDeviceRunning(line.id), isFalse);
      var stats = runner.deviceStatsOf(line.id);
      expect(stats.issue, SimulationIssueKind.recordingMissing);
      expect(stats.errorDetail, 'Line');
      expect(runner.errorCount, 1);
      runner.dispose();
    });
  });

  test('recorded devices are validated', () {
    var noN = device(instances: 2, playback: PlaybackOptions());
    expect(SimulationRules.validateRecorded(noN).map((i) => i.kind), [SimulationIssueKind.recordedNeedsInstance]);
    var max = device(playback: PlaybackOptions(speed: PlaybackOptions.maxSpeed));
    expect(SimulationRules.validateRecorded(max).map((i) => i.kind), [SimulationIssueKind.recordedMaxSpeed]);
    var random = device(start: InstanceStart.randomPosition);
    expect(SimulationRules.validateRecorded(random).map((i) => i.kind), [SimulationIssueKind.recordedRandomNeedsLoop]);
    var none = SimulatedDevice(name: 'x', kind: DeviceKind.recorded);
    expect(SimulationRules.validateRecorded(none).map((i) => i.kind), [SimulationIssueKind.recordingNotChosen]);
    expect(SimulationRules.validateRecorded(device(instances: 3)), isEmpty);
  });

  test('a recorded device survives JSON and old devices load as generated', () {
    var line = device(instances: 3);
    var copy = SimulatedDevice.fromJson(jsonDecode(jsonEncode(line.toJson())) as Map<String, dynamic>);
    expect(copy.isRecorded, isTrue);
    expect(copy.recorded!.recordingName, 'Line');
    expect(copy.recorded!.playback.remaps.single.to, 'test/{n}/');
    var old = line.toJson()
      ..remove('kind')
      ..remove('recorded');
    expect(SimulatedDevice.fromJson(old).isRecorded, isFalse);
    expect(line.copy(newIds: true).recorded!.recordingId, 'line');
  });
}
