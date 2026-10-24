import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/recorder/model/anonymize_rule.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';
import '../helpers/cli_harness.dart';
import '../helpers/test_setup.dart';

Project project() => Project(MqttSettings('broker.local', 'demo-01', 1883), name: 'Demo');

ReceivedMqttMessage incoming(String topic, String payload) =>
    ReceivedMqttMessage(1, topic, toPayload(payload), MqttQos.atLeastOnce, DateTime.now(), false);

void main() {
  late RecordingLibrary library;

  setUp(() => library = RecordingLibrary(MemoryRecordingStore()));

  Cli cli() => Cli([project()], library: library);

  group('record', () {
    test('records the filters into the library until the duration is over', () async {
      var run = cli();
      var code = run.run(['-o', 'json', 'record', '-p', 'Demo', '-t', 'plant/#', '-x', 'plant/debug/#', '--duration', '3s'],
          during: (async) {
        var broker = run.adapter;
        expect(broker.subscribed, ['plant/#']);
        broker.receive(incoming('plant/temp', '21.5'));
        broker.receive(incoming('plant/debug/x', 'no'));
        async.elapse(Duration(seconds: 1));
        broker.receive(incoming('plant/temp', '21.6'));
      }, elapse: Duration(seconds: 3));
      expect(code, 0);
      var stopped = run.events.last;
      expect(stopped['event'], 'stopped');
      expect(stopped['reason'], 'duration');
      expect(stopped['messages'], 2);
      var info = (await library.list()).single;
      expect(info.name, 'plant/#');
      expect(info.header.projectName, 'Demo');
      expect(info.header.clientId, startsWith('demo-01-cli-'));
      expect(run.events.first['event'], 'plan');
    });

    test('waits for the start trigger and keeps the pre-roll', () async {
      var run = cli();
      var code = run.run([
        '-o', 'json', 'record', '-p', 'Demo', '-t', 'plant/#', '--name', 'Alarm', //
        '--start-when', 'plant/alarm', '--pre-roll', '2s', '--stop-when', r'plant/state $.s == "ok"',
      ], during: (async) {
        var broker = run.adapter;
        for (var i = 0; i < 5; i++) {
          broker.receive(incoming('plant/temp', '$i'));
          async.elapse(Duration(seconds: 1));
        }
        broker.receive(incoming('plant/alarm', 'on'));
        async.elapse(Duration(seconds: 1));
        broker.receive(incoming('plant/state', '{"s": "ok"}'));
      });
      expect(code, 0);
      var names = run.events.map((event) => event['event']).toList();
      expect(names, containsAllInOrder(['plan', 'started', 'waitingForTrigger', 'triggerFired', 'stopped']));
      expect(run.events.last['reason'], 'stopCondition');
      // 3 and 4 from the pre-roll, the alarm and the state
      expect(run.events.last['messages'], 4);
      expect((await library.list()).single.name, 'Alarm');
    });

    test('Ctrl+C saves the flight recorder window and stops', () async {
      var run = cli();
      var code = run.run(['-o', 'json', 'record', '-p', 'Demo', '-t', 'plant/#', '--flight', '2s'], during: (async) {
        for (var i = 0; i < 5; i++) {
          run.adapter.receive(incoming('plant/temp', '$i'));
          async.elapse(Duration(seconds: 1));
        }
        run.interrupts.add(null);
        async.flushMicrotasks();
      });
      expect(code, 0);
      var saved = run.events.firstWhere((event) => event['event'] == 'saved');
      expect(saved['messages'], 2);
      expect(run.events.last['reason'], 'interrupted');
      expect(run.events.last['saves'], 1);
      expect((await library.list()).single.header.origin, RecordingOrigin.flightRecorder);
    });

    test('a lost connection ends with exit code 6 without --reconnect', () {
      var run = cli();
      var code = run.run(['record', '-p', 'Demo', '-t', 'plant/#'], during: (async) {
        run.adapter.receive(incoming('plant/temp', '1'));
        run.adapter.dropConnection();
      });
      expect(code, 6);
      expect(run.out.toString(), contains('connection lost'));
    });

    test('checks its options', () {
      expect(cli().run(['record', '-p', 'Demo']), 2);
      expect(cli().run(['record', '-p', 'Demo', '-t', r'$share/g/plant/#']), 2);
      expect(cli().run(['record', '-p', 'Demo', '-t', 'plant/#@3']), 2);
      expect(cli().run(['record', '-p', 'Demo', '-t', 'plant/#', '--start-when', 'a ?? b']), 2);
      expect(cli().run(['record', '-p', 'Demo', '-t', 'plant/#', '--pre-roll', '11m', '--start-when', 'a']), 2);
      expect(cli().run(['record', '-p', 'Nope', '-t', 'plant/#']), 3);
    });
  });

  group('replay', () {
    Future<RecordingInfo> line() => writeRecording(library, 'Line', [
          for (var s = 0; s < 4; s++) recorded(s.toDouble(), 'plant/temp', '$s'),
        ], durationMicros: 4000000);

    test('plays a recording with a remap and ends at its end', () async {
      await line();
      var run = cli();
      var code = run.run(['-o', 'json', 'replay', 'Line', '-p', 'Demo', '--speed', '2', '--remap', 'plant/=test/plant/'],
          elapse: Duration(seconds: 3));
      expect(code, 0);
      expect(run.adapter.published.map((m) => m.topic).toSet(), {'test/plant/temp'});
      expect(run.adapter.published, hasLength(4));
      expect(run.events.last['reason'], 'finished');
      expect(run.events.last['sent'], 4);
      expect(run.events.first['messages'], 4);
    });

    test('runs several instances with {n}', () async {
      await line();
      var run = cli();
      var code = run.run(
          ['replay', 'line', '--host', 'test.local', '--instances', '3', '--instance-start', 'aligned', '--remap', 'plant/=site{n}/'],
          elapse: Duration(seconds: 5));
      expect(code, 0);
      expect(run.adapter.published.map((m) => m.topic).toSet(), {'site1/temp', 'site2/temp', 'site3/temp'});
      expect(run.adapter.published, hasLength(12));
    });

    test('checks its arguments', () async {
      await line();
      expect(cli().run(['replay', 'Line']), 2);
      expect(cli().run(['replay', 'Nope', '-p', 'Demo']), 3);
      expect(cli().run(['replay', 'Line', '-p', 'Demo', '--instances', '2']), 4);
      expect(cli().run(['replay', 'Line', '-p', 'Demo', '--speed', '1000']), 2);
      expect(cli().run(['replay', 'Line', '-p', 'Demo', '-t', 'other/topic']), 3);
      var dry = cli();
      expect(dry.run(['replay', 'Line', '-p', 'Demo', '--dry-run']), 0);
      expect(dry.adapters, isEmpty);
    });
  });

  group('recordings', () {
    late Directory folder;

    setUp(() async => folder = await Directory.systemTemp.createTemp('mqttstudio-cli-test'));

    tearDown(() async => folder.delete(recursive: true));

    String file(String name) => '${folder.path}${Platform.pathSeparator}$name';

    test('lists and shows recordings with gaps', () async {
      await writeRecording(library, 'Gappy', [
        for (var s = 0; s < 30; s++)
          if (s < 10 || s > 20) recorded(s.toDouble(), 'a/temp', '$s'),
      ], durationMicros: 30000000);
      await writeRecording(library, 'Elsewhere', [recorded(0, 'b', '1')], projectName: 'Other');
      var list = cli();
      expect(await list.runReal(['-o', 'json', 'recordings', 'list', '-p', 'test project']), 0);
      expect(list.events.first['name'], 'Gappy');
      expect(list.events.first['project'], 'Test project');
      expect(list.events.where((event) => event['event'] == 'recording'), hasLength(1));
      var show = cli();
      expect(await show.runReal(['-o', 'json', 'recordings', 'show', 'gappy', '--gaps']), 0);
      var gap = show.events.firstWhere((event) => event['event'] == 'gap');
      expect(gap['startMicros'], 9000000);
      expect(show.events.firstWhere((event) => event['event'] == 'topic')['messages'], 19);
    });

    test('exports, imports, edits and compares', () async {
      var info = await writeRecording(library, 'Source', [
        for (var s = 0; s < 10; s++) recorded(s.toDouble(), 'a/state', '{"user": "anna", "v": $s}'),
        recorded(9.5, 'b/other', 'x'),
      ]);
      var jsonl = file('source.jsonl');
      var export = cli();
      expect(await export.runReal(['-o', 'json', 'recordings', 'export', info.id, '--format', 'jsonl', '--out', jsonl]), 0);
      expect(export.events.last['messages'], 11);
      expect(File(jsonl).readAsLinesSync(), hasLength(12));

      var copy = file('source.mqttrec');
      expect(await cli().runReal(['recordings', 'export', 'Source', '--format', 'mqttrec', '--out', copy]), 0);
      var csv = file('source.csv');
      expect(await cli().runReal(['recordings', 'export', 'Source', '--format', 'csv', '--out', csv, '-t', 'a/state', '--column', r'$.v']),
          0);
      expect(File(csv).readAsLinesSync().first, endsWith(r',$.v'));

      var import = cli();
      expect(await import.runReal(['-o', 'json', 'recordings', 'import', jsonl, '--name', 'Back']), 0);
      expect(import.events.last['messages'], 11);

      var rules = file('rules.json');
      File(rules).writeAsStringSync(AnonymizeRule.encodeList(
          [AnonymizeRule('a/#', AnonymizeTarget.jsonPath, AnonymizeAction.hash, jsonPath: r'$.user')]));
      var edit = cli();
      expect(
          await edit.runReal([
            '-o', 'json', 'recordings', 'edit', 'Source', '--from', '2s', '--to', '8s', '--exclude-topic', 'b/other', //
            '--anonymize', rules, '--name', 'Shared',
          ]),
          0);
      var shared = (await library.list()).firstWhere((i) => i.name == 'Shared');
      expect(shared.footer.topics, ['a/state']);
      expect(shared.footer.summary.messages, 7);
      // the intermediate recordings are gone
      expect((await library.list()).map((i) => i.name).toSet(), {'Source', 'Back', 'Shared'});

      // a file compared with its own copy is equal; the anonymized one differs
      var equal = cli();
      expect(await equal.runReal(['-o', 'json', 'recordings', 'compare', copy, 'Source']), 0);
      expect(equal.events.last['equal'], isTrue);
      var report = file('report.json');
      var different = cli();
      expect(await different.runReal(['-o', 'json', 'recordings', 'compare', 'Source', 'Shared', '--payloads', '--report', report]),
          8);
      expect(different.events.last['onlyInA'], 1);
      var json = jsonDecode(File(report).readAsStringSync()) as Map<String, dynamic>;
      expect((json['topics'] as List).length, 2);
    });

    test('import guesses mosquitto_sub output and reports bad files', () async {
      var text = file('dump.txt');
      File(text).writeAsStringSync('1729760000.5 plant/a 1\n1729760001.5 plant/a 2\n');
      var import = cli();
      expect(await import.runReal(['-o', 'json', 'recordings', 'import', text]), 0);
      expect(import.events.last['name'], 'dump');
      expect(import.events.last['durationMicros'], 1000000);
      expect(await cli().runReal(['recordings', 'import', file('missing.csv')]), 3);
      var empty = file('empty.csv');
      File(empty).writeAsStringSync('nothing,here\n');
      expect(await cli().runReal(['recordings', 'import', empty]), 4);
      expect(await cli().runReal(['recordings', 'edit', 'dump']), 2);
    });
  });
}
