import 'dart:convert';
import 'dart:typed_data';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/recorder/engine/recording_player.dart';
import 'package:mqttstudio/recorder/format/recording_reader.dart';
import 'package:mqttstudio/recorder/format/recording_writer.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:typed_data/typed_buffers.dart';

class Sent {
  final String topic;
  final String payload;
  final MqttQos qos;
  final bool retain;
  final MqttMessageProperties? properties;
  final Duration at;

  Sent(this.topic, this.payload, this.qos, this.retain, this.properties, this.at);

  @override
  String toString() => '$topic=$payload@${at.inMilliseconds}';
}

class FakePublisher implements SimulatorPublisher {
  final FakeAsync async;
  final List<Sent> sent = [];
  @override
  bool isConnected = true;
  @override
  bool supportsProperties = true;

  FakePublisher(this.async);

  @override
  void publish(String topic, Uint8Buffer payload, MqttQos qos, bool retain, MqttMessageProperties? properties) =>
      sent.add(Sent(topic, utf8.decode(payload), qos, retain, properties, async.elapsed));

  List<int> get times => sent.map((s) => s.at.inMilliseconds).toList();

  List<String> get payloads => sent.map((s) => s.payload).toList();
}

RecordedMessage msg(int ms, String topic, String payload, {bool retain = false, bool snapshot = false, bool truncated = false}) =>
    RecordedMessage(
        offsetMicros: ms * 1000,
        topic: topic,
        payload: Uint8List.fromList(utf8.encode(payload)),
        qos: MqttQos.atLeastOnce,
        retain: retain,
        snapshot: snapshot,
        truncated: truncated,
        properties: MqttMessageProperties(contentType: 'text/plain'));

void main() {
  // writes a recording and opens a player on it, all inside fake time
  (RecordingPlayer, FakePublisher, RecordingInfo) playerFor(FakeAsync async, List<RecordedMessage> messages, PlaybackOptions options,
      {int? durationMs}) {
    // a library of its own, so one test can play several recordings
    var library = RecordingLibrary(MemoryRecordingStore());
    RecordingInfo? info;
    RecordingReader? reader;
    () async {
      var file = await library.create('r', DateTime(2026, 10, 23));
      var writer = await RecordingWriter.start(
          file,
          RecordingHeader(
              id: 'r',
              startedAt: DateTime.utc(2026, 10, 23),
              filters: [RecorderFilter('plant/#')],
              broker: 'b:1883',
              protocol: MqttProtocolVersion.v5,
              clientId: 'c',
              appVersion: '1'));
      messages.forEach(writer.addMessage);
      await writer.finish(name: 'r', durationMicros: (durationMs ?? 0) * 1000);
      library.finishedWriting(file.name);
      info = (await library.list()).single;
      reader = await library.open(info!);
    }();
    async.flushMicrotasks();
    var publisher = FakePublisher(async);
    return (RecordingPlayer(reader!, options, publisher), publisher, info!);
  }

  test('plays at the recorded times at 1x and ten times faster at 10x', () {
    fakeAsync((async) {
      var messages = [msg(0, 'plant/a', '1'), msg(1000, 'plant/a', '2'), msg(2500, 'plant/b', '3')];
      var (player, publisher, _) = playerFor(async, messages, PlaybackOptions());
      player.play();
      async.elapse(const Duration(seconds: 5));
      expect(publisher.times, [0, 1000, 2500]);
      expect(player.state, PlaybackState.stopped);
      expect(publisher.sent.first.properties!.contentType, 'text/plain');
      expect(publisher.sent.first.qos, MqttQos.atLeastOnce);

      var (fast, fastPublisher, _) = playerFor(async, messages, PlaybackOptions(speed: 10));
      var start = async.elapsed.inMilliseconds;
      fast.play();
      async.elapse(const Duration(seconds: 1));
      expect(fastPublisher.times.map((t) => t - start), [0, 100, 250]);
    });
  });

  test('plays only the selected topics, remaps them and overrides QoS and retain', () {
    fakeAsync((async) {
      var (player, publisher, _) = playerFor(
          async,
          [msg(0, 'plant/a', '1', retain: true), msg(10, 'plant/b', '2'), msg(20, 'plant/a', '3')],
          PlaybackOptions(
              topics: ['plant/a'],
              remaps: [TopicRemap('plant/', 'test/plant/')],
              qos: MqttQos.exactlyOnce,
              retain: RetainOverride.never,
              republishProperties: false));
      player.play();
      async.elapse(const Duration(seconds: 1));
      expect(publisher.sent.map((s) => s.topic), ['test/plant/a', 'test/plant/a']);
      expect(publisher.sent.every((s) => s.qos == MqttQos.exactlyOnce && !s.retain && s.properties == null), isTrue);
    });
  });

  test('a range starts with the retained state before it', () {
    fakeAsync((async) {
      var (player, publisher, _) = playerFor(
          async,
          [
            msg(0, 'plant/state', 'starting', retain: true, snapshot: true),
            msg(100, 'plant/temp', '1'),
            msg(200, 'plant/state', 'running', retain: true),
            msg(1000, 'plant/temp', '2'),
            msg(1500, 'plant/temp', '3'),
            msg(3000, 'plant/temp', '4'),
          ],
          PlaybackOptions(rangeStartMicros: 1000 * 1000, rangeEndMicros: 2000 * 1000));
      player.play();
      async.elapse(const Duration(seconds: 3));
      expect(publisher.payloads, ['running', '2', '3']);
      expect(publisher.sent.first.retain, isTrue);
      expect(publisher.times, [0, 0, 500]);
    });
  });

  test('shortens long gaps', () {
    fakeAsync((async) {
      var (player, publisher, _) = playerFor(
          async, [msg(0, 'plant/a', '1'), msg(60000, 'plant/a', '2'), msg(60500, 'plant/a', '3')],
          PlaybackOptions(compressGapsOverMicros: 2 * 1000 * 1000));
      player.play();
      async.elapse(const Duration(seconds: 5));
      expect(publisher.times, [0, 2000, 2500]);
    });
  });

  test('loops without sending the retained snapshot again', () {
    fakeAsync((async) {
      var (player, publisher, _) = playerFor(
          async, [msg(0, 'plant/state', 's', retain: true, snapshot: true), msg(1000, 'plant/a', '1')],
          PlaybackOptions(loop: true), durationMs: 1000);
      player.play();
      async.elapse(const Duration(milliseconds: 3500));
      expect(publisher.payloads, ['s', '1', '1', '1']);
      expect(publisher.times, [0, 1000, 2000, 3000]);
      expect(player.loopCount, 3);
      expect(player.state, PlaybackState.playing);
      player.stop();
      async.flushMicrotasks();
    });
  });

  test('skips the snapshot when asked and payloads that were cut', () {
    fakeAsync((async) {
      var (player, publisher, _) = playerFor(
          async,
          [msg(0, 'plant/state', 's', retain: true, snapshot: true), msg(10, 'plant/img', 'cut', truncated: true), msg(20, 'plant/a', '1')],
          PlaybackOptions(snapshot: RetainedSnapshotMode.skip));
      player.play();
      async.elapse(const Duration(seconds: 1));
      expect(publisher.payloads, ['1']);
      expect(player.skipped, 1);
    });
  });

  test('pause keeps the position, resume continues the schedule, step sends one message', () {
    fakeAsync((async) {
      var (player, publisher, _) =
          playerFor(async, [msg(0, 'plant/a', '1'), msg(1000, 'plant/a', '2'), msg(2000, 'plant/a', '3'), msg(3000, 'plant/a', '4')], PlaybackOptions());
      player.play();
      async.elapse(const Duration(milliseconds: 1200));
      player.pause();
      async.elapse(const Duration(seconds: 10));
      expect(publisher.payloads, ['1', '2']);

      player.step();
      async.flushMicrotasks();
      expect(publisher.payloads, ['1', '2', '3']);
      expect(player.state, PlaybackState.paused);

      var resumedAt = async.elapsed.inMilliseconds;
      player.play();
      async.elapse(const Duration(seconds: 2));
      expect(publisher.payloads, ['1', '2', '3', '4']);
      expect(publisher.times.last - resumedAt, 1000);
    });
  });

  test('a speed change applies from the current position', () {
    fakeAsync((async) {
      var (player, publisher, _) =
          playerFor(async, [msg(0, 'plant/a', '1'), msg(1000, 'plant/a', '2'), msg(3000, 'plant/a', '3')], PlaybackOptions());
      player.play();
      async.elapse(const Duration(milliseconds: 1000));
      player.setSpeed(2);
      async.elapse(const Duration(seconds: 2));
      expect(publisher.times, [0, 1000, 2000]);
    });
  });

  test('Max sends as fast as the rate limit allows', () {
    fakeAsync((async) {
      var (player, publisher, _) = playerFor(async, [for (var i = 0; i < 5; i++) msg(i * 10000, 'plant/a', '$i')],
          PlaybackOptions(speed: PlaybackOptions.maxSpeed));
      player.maxRate = 100;
      player.play();
      async.elapse(const Duration(seconds: 1));
      expect(publisher.times, [0, 10, 20, 30, 40]);
    });
  });

  test('stops when the publisher is no longer connected', () {
    fakeAsync((async) {
      var (player, publisher, _) = playerFor(async, [msg(0, 'plant/a', '1'), msg(1000, 'plant/a', '2')], PlaybackOptions());
      var lost = 0;
      player.connectionLostEvent.subscribe((_) => lost++);
      player.play();
      async.elapse(const Duration(milliseconds: 500));
      publisher.isConnected = false;
      async.elapse(const Duration(seconds: 2));
      expect(publisher.payloads, ['1']);
      expect(lost, 1);
      expect(player.state, PlaybackState.stopped);
    });
  });

  test('estimates the rate of the selected topics', () {
    fakeAsync((async) {
      var (_, _, info) = playerFor(async, [for (var i = 0; i < 10; i++) msg(i * 1000, i.isEven ? 'plant/a' : 'plant/b', '$i')],
          PlaybackOptions(), durationMs: 10000);
      var all = RecordingPlayer.estimate(info, PlaybackOptions(speed: 2));
      expect(all.rate, closeTo(2, 0.01));
      var one = RecordingPlayer.estimate(info, PlaybackOptions(topics: ['plant/a']));
      expect(one.rate, closeTo(0.5, 0.01));
      expect(RecordingPlayer.estimate(info, PlaybackOptions(speed: PlaybackOptions.maxSpeed), maxRate: 500).rate, 500);
    });
  });
}
