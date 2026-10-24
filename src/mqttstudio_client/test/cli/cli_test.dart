import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/cli/duration_parser.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/recorder/format/recording_writer.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';
import 'dart:typed_data';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import '../helpers/cli_harness.dart';

Project demoProject() {
  var project = Project(MqttSettings('broker.local', 'demo-01', 1883), name: 'Demo factory');
  project.simulation = Simulation(devices: [
    SimulatedDevice(name: 'Weather station', instanceCount: 3, topics: [
      SimulatedTopic(topic: 'weather/{n}/temp', generator: const RandomNumberGenerator()),
    ]),
    SimulatedDevice(name: 'Line', topics: [
      SimulatedTopic(topic: 'line/count', generator: const CounterGenerator(), interval: PublishInterval(minMs: 500)),
    ]),
  ]);
  return project;
}

void main() {
  group('recorded devices', recordedDeviceTests);

  group('DurationParser', () {
    test('parses units and plain seconds', () {
      expect(DurationParser.parse('90s'), Duration(seconds: 90));
      expect(DurationParser.parse('1h30m'), Duration(minutes: 90));
      expect(DurationParser.parse('500ms'), Duration(milliseconds: 500));
      expect(DurationParser.parse('2d'), Duration(days: 2));
      expect(DurationParser.parse('15'), Duration(seconds: 15));
      expect(() => DurationParser.parse('10 minutes'), throwsFormatException);
      expect(DurationParser.format(Duration(minutes: 10)), '10m 00s');
      expect(DurationParser.format(Duration(hours: 1, minutes: 2, seconds: 3)), '1h 02m 03s');
    });
  });

  test('--version prints the version', () {
    var cli = Cli([]);
    expect(cli.run(['--version']), 0);
    expect(cli.out.toString().trim(), 'MQTT Studio 9.9.9');
  });

  test('unknown commands and options are usage errors', () {
    expect(Cli([]).run(['nope']), 2);
    expect(Cli([]).run(['simulate']), 2);
    expect(Cli([demoProject()]).run(['simulate', '-p', 'Demo factory', '--max-rate', '50000']), 2);
    expect(Cli([demoProject()]).run(['simulate', '-p', 'Demo factory', '--duration', 'soon']), 2);
  });

  test('projects list and show', () {
    var cli = Cli([demoProject()]);
    expect(cli.run(['projects', 'list']), 0);
    expect(cli.out.toString(), contains('Demo factory'));
    expect(cli.out.toString(), contains('broker.local:1883'));
    expect(cli.out.toString(), contains('2 devices, 2 topics'));

    var show = Cli([demoProject()]);
    expect(show.run(['projects', 'show', 'demo factory']), 0);
    expect(show.out.toString(), contains('weather/{n}/temp'));
    expect(show.out.toString(), contains('weather/1/temp … weather/3/temp'));

    expect(Cli([demoProject()]).run(['projects', 'show', 'Other']), 3);
  });

  test('json output: one event per line with event and time', () {
    var cli = Cli([demoProject()]);
    expect(cli.run(['-o', 'json', 'projects', 'list']), 0);
    var events = cli.events;
    expect(events.first['event'], 'project');
    expect(events.first['devices'], 2);
    expect(events.last, containsPair('exitCode', 0));
    expect(events.every((e) => e.containsKey('time')), isTrue);
  });

  test('a dry run prints the plan and the resolved topics without connecting', () {
    var cli = Cli([demoProject()]);
    expect(cli.run(['simulate', '-p', 'Demo factory', '--dry-run']), 0);
    var text = cli.out.toString();
    expect(text, contains('Weather station: 3 instances'));
    expect(text, contains('weather/1/temp … weather/3/temp'));
    expect(text, contains('≈ 5.0 msg/s'));
    expect(cli.adapters, isEmpty);
  });

  test('devices are selected by name or id, unknown and ambiguous names are not found', () {
    var project = demoProject();
    var cli = Cli([project]);
    expect(cli.run(['-o', 'json', 'simulate', '-p', 'Demo factory', '-d', 'line', '--dry-run']), 0);
    var plan = cli.events.firstWhere((e) => e['event'] == 'plan');
    expect((plan['devices'] as List).single['name'], 'Line');

    expect(Cli([project]).run(['simulate', '-p', 'Demo factory', '-d', project.simulation.devices.first.id, '--dry-run']), 0);
    expect(Cli([project]).run(['simulate', '-p', 'Demo factory', '-d', 'Nope', '--dry-run']), 3);

    project.simulation.devices.add(SimulatedDevice(name: 'Line', topics: [SimulatedTopic(topic: 'x', generator: const BoolGenerator())]));
    var ambiguous = Cli([project]);
    expect(ambiguous.run(['simulate', '-p', 'Demo factory', '-d', 'Line', '--dry-run']), 3);
    expect(ambiguous.err.toString(), contains(project.simulation.devices.last.id));
  });

  test('an invalid simulation is exit code 4, a high rate exit code 7', () {
    var invalid = demoProject();
    invalid.simulation.devices.first.topics.first.topic = 'weather/temp';
    var cli = Cli([invalid]);
    expect(cli.run(['simulate', '-p', 'Demo factory']), 4);
    expect(cli.err.toString(), contains('{n}'));

    var busy = demoProject();
    busy.simulation.devices.first
      ..instanceCount = 600
      ..topics.first.interval = PublishInterval(minMs: 100);
    expect(Cli([busy]).run(['simulate', '-p', 'Demo factory']), 7);
    expect(Cli([busy]).run(['simulate', '-p', 'Demo factory', '--max-rate', '10000', '--dry-run']), 0);
  });

  test('a broker that cannot be reached is exit code 5', () {
    var cli = Cli([demoProject()]);
    cli.newAdapter = () => UnreachableBroker();
    expect(cli.run(['simulate', '-p', 'Demo factory']), 5);
    expect(cli.err.toString(), contains('Connection refused'));
  });

  test('runs for the duration, prints progress and a summary', () {
    var cli = Cli([demoProject()], environment: {'MQTTSTUDIO_PASSWORD': 'secret'});
    expect(cli.run(['-o', 'json', 'simulate', '-p', 'Demo factory', '--duration', '11s', '--stats-every', '5s'],
        elapse: Duration(seconds: 12)), 0);

    var settings = cli.adapter.connectedWith!;
    expect(settings.password, 'secret');
    expect(settings.clientId, startsWith('demo-01-cli-'));
    expect(cli.adapter.isConnected(), isFalse);
    expect(cli.adapter.published.where((m) => m.topic == 'weather/2/temp'), isNotEmpty);

    var events = cli.events;
    expect(events.map((e) => e['event']), containsAllInOrder(['plan', 'started', 'stats', 'stats', 'stopped']));
    var stopped = events.last;
    expect(stopped['reason'], 'duration');
    expect(stopped['exitCode'], 0);
    expect(stopped['sent'], cli.adapter.published.length);
  });

  test('broker overrides', () {
    var cli = Cli([demoProject()]);
    expect(
        cli.run([
          'simulate', '-p', 'Demo factory', '--host', 'wss://test.local/mqtt', '--port', '8884', '--client-id', 'ci-1',
          '--username', 'bob', '--duration', '1s'
        ], elapse: Duration(seconds: 2)),
        0);
    var settings = cli.adapter.connectedWith!;
    expect(settings.hostname, 'test.local/mqtt');
    expect(settings.useWebSockets, isTrue);
    expect(settings.useSsl, isTrue);
    expect(settings.port, 8884);
    expect(settings.clientId, 'ci-1');
    expect(settings.username, 'bob');
  });

  test('certificate overrides', () {
    var cli = Cli([demoProject()], environment: {'MQTTSTUDIO_KEY_PASSWORD': 'secret'});
    expect(
        cli.run([
          'simulate', '-p', 'Demo factory', '--tls', '--ca-cert', 'ca.crt', '--cert', 'client.crt', '--key',
          'client.key', '--duration', '1s'
        ], elapse: Duration(seconds: 2)),
        0);
    var settings = cli.adapter.connectedWith!;
    expect(settings.caCertificatePath, 'ca.crt');
    expect(settings.clientCertificatePath, 'client.crt');
    expect(settings.clientKeyPath, 'client.key');
    expect(settings.clientKeyPassword, 'secret');
    expect(cli.out.toString(), contains('client certificate'));
  });

  test('--cert replaces the key of the project', () {
    var project = demoProject()
      ..mqttSettings.clientCertificatePath = 'project.crt'
      ..mqttSettings.clientKeyPath = 'project.key';
    var cli = Cli([project]);
    expect(cli.run(['simulate', '-p', 'Demo factory', '--cert', 'client.pem', '--duration', '1s'],
        elapse: Duration(seconds: 2)), 0);
    expect(cli.adapter.connectedWith!.clientKeyPath, isNull);
  });

  test('--key without a certificate is a usage error', () {
    expect(Cli([demoProject()]).run(['simulate', '-p', 'Demo factory', '--key', 'client.key', '--dry-run']), 2);
  });

  test('a lost connection ends the run with exit code 6', () {
    var cli = Cli([demoProject()]);
    var code = cli.run(['simulate', '-p', 'Demo factory'], during: (async) {
      async.elapse(Duration(seconds: 3));
      cli.adapter.dropConnection();
    });
    expect(code, 6);
    expect(cli.out.toString(), contains('connection lost'));
  });

  test('with --reconnect the run continues after the connection is back', () {
    var cli = Cli([demoProject()]);
    var code = cli.run(['-o', 'json', 'simulate', '-p', 'Demo factory', '--reconnect', '--duration', '20s'], during: (async) {
      async.elapse(Duration(seconds: 3));
      cli.adapter.dropConnection();
      async.elapse(Duration(seconds: 2));
    }, elapse: Duration(seconds: 16));
    expect(code, 0);
    var events = cli.events.map((e) => e['event']).toList();
    expect(events, containsAllInOrder(['reconnecting', 'reconnected', 'stopped']));
  });

  test('Ctrl+C stops the run with exit code 0', () {
    var cli = Cli([demoProject()]);
    var code = cli.run(['simulate', '-p', 'Demo factory', '--clear-retained'], during: (async) {
      async.elapse(Duration(seconds: 2));
      cli.interrupts.add(null);
    });
    expect(code, 0);
    expect(cli.out.toString(), contains('(interrupted)'));
  });

  test('the same seed publishes the same payloads', () {
    List<String> payloads() {
      var project = demoProject();
      for (var device in project.simulation.devices) {
        device.id = device.name;
        for (var topic in device.topics) {
          topic.id = topic.topic;
        }
      }
      var cli = Cli([project]);
      cli.run(['-q', 'simulate', '-p', 'Demo factory', '--seed', '7', '--duration', '5s'], elapse: Duration(seconds: 6));
      return cli.adapter.published.map((m) => '${m.topic}=${utf8.decode(m.payload.toList())}').toList()..sort();
    }

    expect(payloads(), payloads());
  });
}

// a recording of plant/temp at 0 s, 1 s and 2 s
Future<RecordingInfo> recordLine(RecordingLibrary library) async {
  var file = await library.create('Line', DateTime(2026, 10, 24));
  var writer = await RecordingWriter.start(
      file,
      RecordingHeader(
          id: 'line',
          startedAt: DateTime.utc(2026, 10, 24),
          filters: [RecorderFilter('plant/#')],
          broker: 'broker.local:1883',
          protocol: MqttProtocolVersion.v5,
          clientId: 'c',
          appVersion: ''));
  for (var s = 0; s < 3; s++) {
    writer.addMessage(RecordedMessage(
        offsetMicros: s * 1000000, topic: 'plant/temp', payload: Uint8List.fromList(utf8.encode('2$s'))));
  }
  await writer.finish(name: 'Line', durationMicros: 3000000);
  library.finishedWriting(file.name);
  return (await library.list()).single;
}

Project replayProject(String recordingId, String fileName) {
  var project = Project(MqttSettings('broker.local', 'demo-01', 1883), name: 'Replay');
  project.simulation = Simulation(devices: [
    SimulatedDevice(
        name: 'Line replay',
        instanceCount: 2,
        kind: DeviceKind.recorded,
        recorded: RecordedSource(
            recordingId: recordingId,
            fileName: fileName,
            recordingName: 'Line',
            playback: PlaybackOptions(remaps: [TopicRemap('plant/', 'test/{n}/')]),
            instanceStart: InstanceStart.aligned)),
  ]);
  return project;
}

void recordedDeviceTests() {
  test('simulate plays recorded devices and ends once they are finished', () async {
    var library = RecordingLibrary(MemoryRecordingStore());
    var info = await recordLine(library);
    var project = replayProject(info.id, info.fileName);

    var dryRun = Cli([project], library: library);
    expect(dryRun.run(['-o', 'json', 'simulate', '-p', 'Replay', '--dry-run']), 0);
    var plan = dryRun.events.firstWhere((event) => event['event'] == 'plan');
    expect(plan['devices'][0]['recording'], 'Line');
    expect(plan['estimatedRate'], closeTo(2, 0.01));
    expect(dryRun.events.where((event) => event['event'] == 'topic').single['target'], 'test/{n}/temp');

    var cli = Cli([project], library: library);
    expect(cli.run(['-o', 'json', 'simulate', '-p', 'Replay'], elapse: Duration(seconds: 5)), 0);
    expect(cli.adapter.published.map((m) => m.topic).toSet(), {'test/1/temp', 'test/2/temp'});
    expect(cli.adapter.published.length, 6);
    var stopped = cli.events.last;
    expect(stopped['reason'], 'finished');
    expect(stopped['sent'], 6);
  });

  test('simulate stops before connecting when a recording is missing', () {
    var cli = Cli([replayProject('nope', 'nope.mqttrec')]);
    expect(cli.run(['simulate', '-p', 'Replay']), 3);
    expect(cli.adapters, isEmpty);
    expect(cli.err.toString(), contains('The recording "Line" of device "Line replay"'));
  });
}
