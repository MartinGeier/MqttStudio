import 'dart:convert';
import 'dart:typed_data';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/recorder/engine/recorder_service.dart';
import 'package:mqttstudio/recorder/format/recording_reader.dart';
import 'package:mqttstudio/recorder/model/message_condition.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recorder_config.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_setup.dart';

ReceivedMqttMessage incoming(String topic, String payload) =>
    ReceivedMqttMessage(1, topic, toPayload(payload), MqttQos.atLeastOnce, DateTime.now(), false);

Future<List<RecordingEntry>> entriesOf(RecordingLibrary library, RecordingInfo info) async {
  var reader = await library.open(info);
  var entries = await reader.entries().toList();
  await reader.close();
  return entries;
}

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  group('MessageCondition', () {
    test('parses the text form and prints it again', () {
      var any = MessageCondition.parse('plant/line1/alarm');
      expect(any.op, isNull);
      expect(any.toText(), 'plant/line1/alarm');

      var number = MessageCondition.parse('plant/+/temp > 80');
      expect(number.op, ConditionOp.greater);
      expect(number.value, '80');
      expect(number.toText(), 'plant/+/temp > 80');

      var json = MessageCondition.parse(r'plant/line1/state $.status == "error"');
      expect(json.jsonPath, r'$.status');
      expect(json.value, 'error');
      expect(json.toText(), r'plant/line1/state $.status == "error"');

      var regex = MessageCondition.parse('plant/line1/log ~ /timeout|refused/');
      expect(regex.op, ConditionOp.regex);
      expect(regex.value, 'timeout|refused');

      var quoted = MessageCondition.parse(r"plant/x $['a b'] >= 3");
      expect(quoted.jsonPath, r"$['a b']");
      expect(MessageCondition.fromJson(quoted.toJson()).toText(), quoted.toText());
    });

    test('rejects invalid conditions', () {
      for (var text in ['', r'$share/g/a', 'a/#/b', r'a $.x ?? 3', 'a > ', r'a $..x', 'a ~ /(/']) {
        expect(() => MessageCondition.parse(text), throwsFormatException, reason: text);
      }
    });

    test('matches topics, numbers, JSON fields, text and patterns', () {
      expect(MessageCondition.parse('plant/+/temp > 80').matches('plant/l1/temp', bytes('80.5')), isTrue);
      expect(MessageCondition.parse('plant/+/temp > 80').matches('plant/l1/temp', bytes('9')), isFalse);
      expect(MessageCondition.parse('plant/+/temp > 80').matches('plant/l1/hum', bytes('99')), isFalse);
      // as numbers 10 > 9, as text "10" < "9"
      expect(MessageCondition.parse('a > 9').matches('a', bytes('10')), isTrue);
      expect(MessageCondition.parse('a == 1.0').matches('a', bytes('1')), isTrue);
      expect(MessageCondition.parse(r'a $.status == "error"').matches('a', bytes('{"status":"error"}')), isTrue);
      expect(MessageCondition.parse(r'a $.status == "error"').matches('a', bytes('{"status":"ok"}')), isFalse);
      expect(MessageCondition.parse(r'a $.status').matches('a', bytes('{"other":1}')), isFalse);
      expect(MessageCondition.parse(r'a $.v[1] < 0').matches('a', bytes('{"v":[1,-2]}')), isTrue);
      expect(MessageCondition.parse(r'a $.status == "x"').matches('a', bytes('not json')), isFalse);
      expect(MessageCondition.parse('a contains fail').matches('a', bytes('it failed')), isTrue);
      expect(MessageCondition.parse('a ~ /time(out)?/').matches('a', bytes('timeout')), isTrue);
      expect(MessageCondition.parse('a/#').matches('a/b/c', bytes('')), isTrue);
    });
  });

  group('RecorderService', () {
    late RecordingLibrary library;
    late RecorderService recorder;
    late List<FakeMqttAdapter> connections;
    late List<RecordingFinishedEventArgs> finished;
    late List<RecordingFinishedEventArgs> saved;

    setUp(() async {
      setUpServices();
      var project = await openNewProject();
      project.mqttSettings.protocolVersion = MqttProtocolVersion.v5;
      library = RecordingLibrary(MemoryRecordingStore());
      connections = [];
      finished = [];
      saved = [];
      recorder = RecorderService(library, connectionFactory: () {
        var connection = FakeMqttAdapter();
        connections.add(connection);
        return connection;
      });
      recorder.finishedEvent.subscribe((args) => finished.add(args));
      recorder.savedEvent.subscribe((args) => saved.add(args));
    });

    tearDown(() async {
      recorder.dispose();
      await tearDownServices();
    });

    T run<T>(T Function(FakeAsync async) body) => fakeAsync((async) => body(async));

    // one message per second from second `from` up to `to`, after the one before
    void temps(FakeAsync async, int from, int to) {
      for (var s = from; s <= to; s++) {
        connections.last.receive(incoming('plant/temp', '$s'));
        async.elapse(Duration(seconds: 1));
      }
    }

    test('waits for the start trigger and keeps the pre-roll', () {
      run((async) {
        recorder.start(RecorderConfig(
            name: 'Alarm',
            filters: [RecorderFilter('plant/#')],
            startWhen: MessageCondition.parse('plant/alarm'),
            preRollSeconds: 5));
        async.flushMicrotasks();
        expect(recorder.state, RecorderState.waiting);
        expect(recorder.isWaitingForTrigger, isTrue);

        temps(async, 0, 9);
        expect(library.list(), completion(isEmpty));
        async.flushMicrotasks();
        connections.last.receive(incoming('plant/alarm', 'on'));
        async.flushMicrotasks();
        expect(recorder.state, RecorderState.recording);
        async.elapse(Duration(seconds: 1));
        temps(async, 11, 12);
        recorder.stop();
        async.flushMicrotasks();

        var info = finished.single.info!;
        expect(info.header.origin, RecordingOrigin.live);
        late List<RecordingEntry> entries;
        entriesOf(library, info).then((value) => entries = value);
        async.flushMicrotasks();
        var messages = entries.whereType<MessageEntry>().map((e) => e.message).toList();
        expect(messages.map((m) => utf8.decode(m.payload)), ['5', '6', '7', '8', '9', 'on', '11', '12']);
        expect(messages.first.offsetMicros, 0);
        expect(messages[5].offsetMicros, 5000000);
        var marker = entries.whereType<MarkerEntry>().single.marker;
        expect(marker.kind, RecordingMarker.triggerFired);
        expect(marker.offsetMicros, 5000000);
      });
    });

    test('a stop condition stops after its post-roll', () {
      run((async) {
        recorder.start(RecorderConfig(
            name: 'Batch',
            filters: [RecorderFilter('plant/#')],
            stopWhen: MessageCondition.parse(r'plant/state $.phase == "done"'),
            postRollSeconds: 2));
        async.flushMicrotasks();
        temps(async, 0, 2);
        connections.last.receive(incoming('plant/state', '{"phase": "done"}'));
        expect(recorder.isInPostRoll, isTrue);
        async.elapse(Duration(milliseconds: 500));
        connections.last.receive(incoming('plant/temp', 'after'));
        async.elapse(Duration(seconds: 2));
        expect(finished.single.reason, RecordingStopReason.stopCondition);
        expect(finished.single.info!.footer.summary.messages, 5);
      });
    });

    test('stopping before the trigger saves nothing', () {
      run((async) {
        recorder.start(RecorderConfig(
            name: 'Never', filters: [RecorderFilter('plant/#')], startWhen: MessageCondition.parse('plant/alarm')));
        async.flushMicrotasks();
        temps(async, 0, 2);
        recorder.stop();
        async.flushMicrotasks();
        expect(finished.single.info, isNull);
        expect(recorder.state, RecorderState.idle);
        expect(library.list(), completion(isEmpty));
        async.flushMicrotasks();
      });
    });

    test('the flight recorder saves its window plus the post-roll and goes on', () {
      run((async) {
        recorder.start(RecorderConfig(
          name: 'Flight',
          filters: [RecorderFilter('plant/#')],
          mode: RecorderMode.flightRecorder,
          flight: FlightRecorderOptions(
              windowSeconds: 5, postRollSeconds: 1, saveWhen: MessageCondition.parse('plant/alarm'), maxSaves: 2),
        ));
        async.flushMicrotasks();
        expect(recorder.state, RecorderState.recording);
        expect(recorder.isFlightRecorder, isTrue);
        temps(async, 0, 9);
        expect(recorder.flightSpan.inSeconds, inInclusiveRange(4, 5));

        connections.last.receive(incoming('plant/alarm', 'on'));
        expect(recorder.isSaveScheduled, isTrue);
        // during the post-roll another alarm belongs to the same save
        connections.last.receive(incoming('plant/alarm', 'again'));
        async.elapse(Duration(milliseconds: 500));
        connections.last.receive(incoming('plant/temp', 'post'));
        async.elapse(Duration(seconds: 1));
        async.flushMicrotasks();
        expect(saved, hasLength(1));
        var first = saved.single.info!;
        expect(first.header.origin, RecordingOrigin.flightRecorder);
        expect(first.name, startsWith('Flight '));
        late List<RecordingEntry> entries;
        entriesOf(library, first).then((value) => entries = value);
        async.flushMicrotasks();
        var payloads = entries.whereType<MessageEntry>().map((e) => utf8.decode(e.message.payload)).toList();
        // the window ends at the save, 5 s back from 11 s
        expect(payloads.first, '6');
        expect(payloads.sublist(payloads.length - 3), ['on', 'again', 'post']);
        expect(recorder.isRecording, isTrue);

        // the second save reaches maxSaves and ends the flight recorder
        recorder.saveFlightRecording();
        async.elapse(Duration(seconds: 2));
        async.flushMicrotasks();
        expect(saved, hasLength(2));
        expect(finished.single.reason, RecordingStopReason.maxSaves);
        expect(recorder.state, RecorderState.idle);
      });
    });

    test('saves the topic viewer buffer with offsets from the receive times', () async {
      var start = DateTime.utc(2026, 10, 24, 9);
      var messages = [
        ReceivedMqttMessage(1, 'a/b', toPayload('2'), MqttQos.atMostOnce, start.add(Duration(milliseconds: 1500)), true),
        ReceivedMqttMessage(2, 'a/b', toPayload('1'), MqttQos.atLeastOnce, start, false),
      ];
      var info = await recorder.saveMessages('Viewer', messages,
          filters: [RecorderFilter('a/#')], settings: MqttSettings('broker', 'client', 1883), projectName: 'P');
      expect(info.header.origin, RecordingOrigin.viewerBuffer);
      expect(info.header.startedAt, start);
      expect(info.footer.durationMicros, 1500000);
      var entries = await entriesOf(library, info);
      var recorded = entries.whereType<MessageEntry>().map((e) => e.message).toList();
      expect(recorded.map((m) => utf8.decode(m.payload)), ['1', '2']);
      expect(recorded.last.offsetMicros, 1500000);
      expect(recorded.last.retain, isTrue);
    });
  });
}
