import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/export/asyncapi_importer.dart';
import 'package:mqttstudio/documentation/export/doc_export.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import '../helpers/cli_harness.dart';
import '../helpers/test_setup.dart';

TopicDocumentation documentation() => TopicDocumentation(title: 'Plant', nodes: [
      DocNode(
          path: 'plant/speed',
          title: 'Speed',
          topic: TopicSpec(
              qos: MqttQos.atMostOnce, payload: PayloadSpec(format: PayloadFormat.number, min: 0, max: 24000))),
      DocNode(path: 'plant/on', topic: TopicSpec(payload: PayloadSpec(format: PayloadFormat.boolean))),
    ]);

Project project() =>
    Project(MqttSettings('broker.local', 'demo-01', 1883), name: 'Demo')..documentation = documentation();

ReceivedMqttMessage incoming(String topic, String payload) =>
    ReceivedMqttMessage(1, topic, toPayload(payload), MqttQos.atMostOnce, DateTime.now(), false);

void main() {
  Cli cli() => Cli([project()]);

  group('doc check', () {
    test('reports the findings and exits with 8 on an error', () {
      var run = cli();
      var code = run.run(['-o', 'json', 'doc', 'check', '-p', 'Demo', '--duration', '5s'], during: (async) {
        expect(run.adapter.subscribed, unorderedEquals(['plant/speed', 'plant/on']));
        run.adapter.receive(incoming('plant/speed', '1200'));
        run.adapter.receive(incoming('plant/speed', '30000'));
        run.adapter.receive(incoming('plant/other', 'x'));
        run.adapter.receive(incoming('plant/on', 'maybe'));
      }, elapse: Duration(seconds: 5));
      expect(code, 8);
      var findings = run.events.where((event) => event['event'] == 'finding').toList();
      expect(findings.map((finding) => finding['rule']), containsAll(['outOfRange', 'undocumented', 'formatMismatch']));
      expect(run.events.last['event'], 'summary');
      expect(run.events.last['messages'], 4);
      expect(run.events.last['errors'], 1);
    });

    test('a clean run exits with 0, and --fail-on never ignores errors', () {
      var run = cli();
      var code = run.run(['doc', 'check', '-p', 'Demo', '--duration', '2s'], during: (async) {
        run.adapter.receive(incoming('plant/on', 'true'));
      }, elapse: Duration(seconds: 2));
      expect(code, 0);
      expect(run.out.toString(), contains('0 errors, 0 warnings'));
      run = cli();
      code = run.run(['doc', 'check', '-p', 'Demo', '--duration', '2s', '--fail-on', 'never'], during: (async) {
        run.adapter.receive(incoming('plant/on', 'maybe'));
      }, elapse: Duration(seconds: 2));
      expect(code, 0);
    });

    test('a lost connection ends with exit code 6', () {
      var run = cli();
      var code = run.run(['doc', 'check', '-p', 'Demo'], during: (async) => run.adapter.dropConnection());
      expect(code, 6);
    });
  });

  group('doc discover', () {
    test('listens for the duration and prints the comparison', () {
      var run = cli();
      var code = run.run(['-o', 'json', 'doc', 'discover', '-p', 'Demo', '-t', 'plant/#', '--duration', '3s'],
          during: (async) {
        run.adapter.receive(incoming('plant/speed', '1200'));
        run.adapter.receive(incoming('plant/temp', '21.5'));
        async.elapse(Duration(seconds: 1));
        run.adapter.receive(incoming('plant/temp', '21.6'));
      }, elapse: Duration(seconds: 3));
      expect(code, 0);
      var result = run.events.firstWhere((event) => event['event'] == 'result');
      expect(result['messages'], 3);
      expect(result['new'], 1);
      expect(result['notSeen'], 1);
    });

    test('checks its options', () {
      expect(cli().run(['doc', 'discover', '-p', 'Demo']), 2);
      expect(cli().run(['doc', 'discover', '-p', 'Demo', '-t', 'a/#/b']), 2);
      expect(cli().run(['doc', 'discover', '-p', 'Nope', '-t', 'plant/#']), 3);
    });
  });

  group('doc export and import', () {
    test('exports to stdout', () {
      var run = cli();
      expect(run.run(['doc', 'export', '-p', 'Demo', '--format', 'csv']), 0);
      expect(run.out.toString(), contains('plant/speed'));
      expect(cli().run(['doc', 'export', '-p', 'Demo']), 2);
      expect(cli().run(['doc', 'export', '-p', 'Demo', '--format', 'md', '--scope', 'nope']), 3);
    });

    test('import prints the plan and writes the merged documentation', () async {
      var folder = await Directory.systemTemp.createTemp('doc_cli');
      addTearDown(() => folder.delete(recursive: true));
      var other = documentation()
        ..nodes.first.title = 'Spindle speed'
        ..nodes.add(DocNode(path: 'plant/mode', topic: TopicSpec(payload: PayloadSpec(format: PayloadFormat.string))));
      var source = File('${folder.path}/other.asyncapi.yaml');
      await source.writeAsString(DocExport.run(other, DocExportOptions(DocExportFormat.asyncapiYaml)));
      var target = '${folder.path}/merged.asyncapi.yaml';

      var run = cli();
      var code = await run.runReal(['doc', 'import', '-p', 'Demo', source.path, '--out', target]);
      expect(code, 0, reason: run.err.toString());
      expect(run.out.toString(), contains('1 new, 1 changed, 1 unchanged, 0 conflicts'));
      var merged = AsyncApiImporter.read(await File(target).readAsString()).documentation;
      expect(merged.nodeAt('plant/speed')!.title, 'Spindle speed');
      expect(merged.nodeAt('plant/mode'), isNotNull);
      expect(await cli().runReal(['doc', 'import', '-p', 'Demo', '${folder.path}/missing.yaml']), 3);
    });
  });
}
