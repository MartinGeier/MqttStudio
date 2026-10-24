import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/engine/recorder_service.dart';
import 'package:mqttstudio/recorder/format/recording_reader.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recorder_config.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_setup.dart';

class _Harness {
  final FakeMqttAdapter main;
  final RecordingLibrary library = RecordingLibrary(MemoryRecordingStore());
  final List<FakeMqttAdapter> connections = [];
  late final RecorderService recorder;
  final List<RecordingFinishedEventArgs> finished = [];

  _Harness(this.main) {
    recorder = RecorderService(library, connectionFactory: () {
      var connection = FakeMqttAdapter();
      connections.add(connection);
      return connection;
    }, appVersion: () async => '1.0.3');
    recorder.finishedEvent.subscribe((args) => finished.add(args));
  }

  FakeMqttAdapter get connection => connections.last;
}

RecorderConfig config({List<RecorderFilter>? filters, int? durationSeconds, int? maxMessages, int? maxPayloadBytes, bool snapshot = true}) =>
    RecorderConfig(
      name: 'Night shift',
      filters: filters ?? [RecorderFilter('plant/#'), RecorderFilter('plant/debug/#', exclude: true)],
      durationSeconds: durationSeconds,
      maxMessages: maxMessages,
      maxPayloadBytes: maxPayloadBytes,
      recordRetainedSnapshot: snapshot,
    );

ReceivedMqttMessage incoming(String topic, String payload, {bool retain = false}) =>
    ReceivedMqttMessage(1, topic, toPayload(payload), MqttQos.atLeastOnce, DateTime.now(), retain);

Future<List<RecordedMessage>> messagesOf(RecordingLibrary library) async {
  var info = (await library.list()).single;
  var reader = await library.open(info);
  var entries = await reader.entries().toList();
  await reader.close();
  return entries.whereType<MessageEntry>().map((e) => e.message).toList();
}

Future<List<String>> markersOf(RecordingLibrary library) async {
  var reader = await library.open((await library.list()).single);
  var entries = await reader.entries().toList();
  await reader.close();
  return entries.whereType<MarkerEntry>().map((e) => e.marker.kind).toList();
}

void main() {
  late _Harness harness;

  setUp(() async {
    var main = setUpServices();
    var project = await openNewProject();
    project.mqttSettings.protocolVersion = MqttProtocolVersion.v5;
    project.topicSubscriptions.add(TopicSubscription('plant/#', MqttQos.atMostOnce));
    harness = _Harness(main);
  });

  tearDown(() async {
    harness.recorder.dispose();
    await tearDownServices();
  });

  T run<T>(T Function(FakeAsync async) body) => fakeAsync((async) => body(async));

  test('records on its own connection and writes a finished recording', () {
    run((async) {
      harness.recorder.start(config());
      async.flushMicrotasks();
      expect(harness.recorder.state, RecorderState.recording);
      var connection = harness.connection;
      expect(connection, isNot(same(harness.main)));
      expect(connection.connectedWith!.clientId, startsWith('client-1-rec-'));
      expect(connection.subscriptions.map((s) => s.topic), ['plant/#']);
      expect(connection.subscriptions.single.retainAsPublished, isTrue);
      expect(harness.main.subscribed, isEmpty);

      connection.receive(incoming('plant/state', '{"status":"ok"}', retain: true));
      async.elapse(const Duration(milliseconds: 500));
      connection.receive(incoming('plant/temp', '21.5'));
      connection.receive(incoming('plant/debug/trace', 'x'));
      async.elapse(const Duration(seconds: 3));
      // retained, but no longer right after subscribing: a live retained publish
      connection.receive(incoming('plant/mode', 'auto', retain: true));
      expect(harness.recorder.received, 4);
      expect(harness.recorder.excluded, 1);

      harness.recorder.stop();
      async.flushMicrotasks();
      expect(harness.recorder.state, RecorderState.idle);
      expect(connection.connected, isFalse);
      var info = harness.finished.single.info!;
      expect(info.name, 'Night shift');
      expect(info.header.projectName, 'Test project');
      expect(info.header.appVersion, '1.0.3');
      expect(info.header.filters.first.color!.color, isNotNull);
      expect(info.footer.summary.messages, 3);

      List<RecordedMessage>? messages;
      messagesOf(harness.library).then((value) => messages = value);
      async.flushMicrotasks();
      expect(messages!.map((m) => m.topic), ['plant/state', 'plant/temp', 'plant/mode']);
      expect(messages![0].snapshot, isTrue);
      expect(messages![1].offset, const Duration(milliseconds: 500));
      expect(messages![2].retain && !messages![2].snapshot, isTrue);
    });
  });

  test('with MQTT 3.1.1 only the first retained message of a topic is the snapshot', () {
    run((async) {
      GetIt.I.get<ProjectManager>().currentProject!.mqttSettings.protocolVersion = MqttProtocolVersion.v311;
      harness.recorder.start(config());
      async.flushMicrotasks();
      expect(harness.connection.subscriptions.single.retainAsPublished, isFalse);
      async.elapse(const Duration(seconds: 10));
      harness.connection.receive(incoming('plant/state', 'a', retain: true));
      harness.connection.receive(incoming('plant/state', 'b', retain: true));
      harness.recorder.stop();
      async.flushMicrotasks();

      List<RecordedMessage>? messages;
      messagesOf(harness.library).then((value) => messages = value);
      async.flushMicrotasks();
      expect(messages!.map((m) => m.snapshot), [true, false]);
    });
  });

  test('without the retained snapshot it asks the broker not to send it and drops what comes anyway', () {
    run((async) {
      harness.recorder.start(config(snapshot: false));
      async.flushMicrotasks();
      expect(harness.connection.subscriptions.single.retainHandling, SubscriptionRetainHandling.doNotSend);
      harness.connection.receive(incoming('plant/state', 'a', retain: true));
      harness.connection.receive(incoming('plant/temp', '1'));
      harness.recorder.stop();
      async.flushMicrotasks();
      expect(harness.finished.single.info!.footer.summary.messages, 1);
    });
  });

  test('cuts payloads above the max payload size and keeps their size', () {
    run((async) {
      harness.recorder.start(config(maxPayloadBytes: 4));
      async.flushMicrotasks();
      harness.connection.receive(incoming('plant/log', 'a long text'));
      harness.recorder.stop();
      async.flushMicrotasks();
      List<RecordedMessage>? messages;
      messagesOf(harness.library).then((value) => messages = value);
      async.flushMicrotasks();
      var message = messages!.single;
      expect(utf8.decode(message.payload), 'a lo');
      expect(message.payloadLength, 11);
      expect(message.truncated, isTrue);
    });
  });

  test('stops after the duration and after the number of messages', () {
    run((async) {
      harness.recorder.start(config(durationSeconds: 60));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 59));
      expect(harness.recorder.isRecording, isTrue);
      async.elapse(const Duration(seconds: 2));
      expect(harness.recorder.isRecording, isFalse);
      expect(harness.finished.single.reason, RecordingStopReason.duration);
      expect(harness.finished.single.info!.footer.duration.inSeconds, 60);

      harness.recorder.start(config(maxMessages: 2));
      async.flushMicrotasks();
      harness.connection.receive(incoming('plant/a', '1'));
      harness.connection.receive(incoming('plant/a', '2'));
      harness.connection.receive(incoming('plant/a', '3'));
      async.flushMicrotasks();
      expect(harness.finished.last.reason, RecordingStopReason.maxMessages);
      expect(harness.finished.last.info!.footer.summary.messages, 2);
    });
  });

  test('reconnects after a lost connection and marks the gap', () {
    run((async) {
      harness.recorder.start(config());
      async.flushMicrotasks();
      var connection = harness.connection;
      connection.dropConnection();
      expect(harness.recorder.state, RecorderState.reconnecting);
      async.elapse(const Duration(milliseconds: 1100));
      expect(harness.recorder.state, RecorderState.recording);
      expect(connection.subscriptions.length, 2);
      connection.receive(incoming('plant/a', '1'));
      harness.recorder.stop();
      async.flushMicrotasks();

      List<String>? markers;
      markersOf(harness.library).then((value) => markers = value);
      async.flushMicrotasks();
      expect(markers, [RecordingMarker.connectionLost, RecordingMarker.reconnected]);
    });
  });

  test('closing the project asks first and stops the recording only on yes', () {
    run((async) {
      var answer = false;
      var asked = 0;
      harness.recorder.confirmStopOnClose = () async {
        asked++;
        return answer;
      };
      harness.recorder.start(config());
      async.flushMicrotasks();
      var projectManager = GetIt.I.get<ProjectManager>();

      bool? closed;
      projectManager.closeProject(true).then((value) => closed = value);
      async.flushMicrotasks();
      expect(closed, isFalse);
      expect(asked, 1);
      expect(projectManager.isProjectOpen, isTrue);
      expect(harness.recorder.isRecording, isTrue);

      answer = true;
      projectManager.closeProject(true).then((value) => closed = value);
      async.flushMicrotasks();
      expect(closed, isTrue);
      expect(harness.recorder.isRecording, isFalse);
      expect(harness.finished.single.reason, RecordingStopReason.projectClosed);
      expect(harness.finished.single.info, isNotNull);
    });
  });

  test('closing a project without a recording asks nothing', () {
    run((async) {
      var asked = 0;
      harness.recorder.confirmStopOnClose = () async {
        asked++;
        return false;
      };
      bool? closed;
      GetIt.I.get<ProjectManager>().closeProject(true).then((value) => closed = value);
      async.flushMicrotasks();
      expect(closed, isTrue);
      expect(asked, 0);
    });
  });

  test('a recording cannot start twice or without a project', () async {
    await harness.recorder.start(config());
    expect(() => harness.recorder.start(config()), throwsStateError);
    await harness.recorder.stop();
    await GetIt.I.get<ProjectManager>().closeProject(true);
    expect(() => harness.recorder.start(config()), throwsStateError);
  });

  group('RecorderRules', () {
    test('validates filters', () {
      expect(RecorderRules.validateFilter('plant/#'), isNull);
      expect(RecorderRules.validateFilter('plant/+/temp'), isNull);
      expect(RecorderRules.validateFilter(''), FilterIssue.empty);
      expect(RecorderRules.validateFilter(r'$share/g/plant/#'), FilterIssue.shared);
      expect(RecorderRules.validateFilter('plant/#/temp'), FilterIssue.wildcardPosition);
      expect(RecorderRules.validateFilter('plant/a+'), FilterIssue.wildcardPosition);
    });

    test('knows which filters cover others', () {
      expect(RecorderRules.covers('a/#', 'a/b/+'), isTrue);
      expect(RecorderRules.covers('a/#', 'a'), isTrue);
      expect(RecorderRules.covers('a/+', 'a/b'), isTrue);
      expect(RecorderRules.covers('a/b', 'a/+'), isFalse);
      expect(RecorderRules.covers('a/+', 'a/#'), isFalse);
      expect(RecorderRules.covers('#', r'$SYS/#'), isFalse);
    });

    test('drops covered filters and keeps one of two equal ones', () {
      var result = RecorderRules.normalize([
        RecorderFilter('plant/line1/temp'),
        RecorderFilter('plant/#'),
        RecorderFilter('plant/#'),
        RecorderFilter('plant/debug/#', exclude: true),
      ]);
      expect(result.filters.map((f) => f.filter), ['plant/#', 'plant/debug/#']);
      expect(result.covered.map((c) => '${c.filter.filter}<${c.coveredBy.filter}'),
          ['plant/line1/temp<plant/#', 'plant/#<plant/#']);
    });

    test('matches includes and excludes', () {
      var filters = [RecorderFilter('plant/#'), RecorderFilter('plant/debug/#', exclude: true)];
      expect(RecorderRules.isRecorded('plant/temp', filters), isTrue);
      expect(RecorderRules.isRecorded('plant', filters), isTrue);
      expect(RecorderRules.isRecorded('plant/debug/x', filters), isFalse);
      expect(RecorderRules.isRecorded('other', filters), isFalse);
      expect(RecorderRules.matches(r'$SYS/load', '#'), isFalse);
    });
  });
}
