import 'dart:async';
import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/cli/cli_app.dart';
import 'package:mqttstudio/cli/cli_context.dart';
import 'package:mqttstudio/cli/duration_parser.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/fake_mqtt_adapter.dart';

class FakeProjects implements ProjectSource {
  final List<Project> list;
  FakeProjects(this.list);

  @override
  Future<List<Project>> projects() async => list;
}

class UnreachableBroker extends FakeMqttAdapter {
  @override
  Future connect(MqttSettings mqttSettings) async =>
      throw SrxServiceException('Connection refused', ServiceError.MqttCannotConnect);
}

class Cli {
  final out = StringBuffer();
  final err = StringBuffer();
  // created inside fakeAsync, a stream of the real zone would complete its futures outside the fake time
  late StreamController<void> interrupts;
  final List<FakeMqttAdapter> adapters = [];
  final List<int> forcedExits = [];
  late final CliContext context;
  FakeMqttAdapter Function() newAdapter = () => FakeMqttAdapter();

  Cli(List<Project> projects, {Map<String, String> environment = const {}}) {
    context = CliContext(
      version: '9.9.9',
      stdout: out,
      stderr: err,
      projects: FakeProjects(projects),
      createAdapter: () {
        var adapter = newAdapter();
        adapters.add(adapter);
        return adapter;
      },
      interrupts: () => interrupts.stream,
      environment: environment,
      forceExit: forcedExits.add,
    );
  }

  FakeMqttAdapter get adapter => adapters.single;

  List<Map<String, dynamic>> get events =>
      out.toString().trim().split('\n').map((line) => jsonDecode(line) as Map<String, dynamic>).toList();

  // runs the command inside fakeAsync, elapsing the given time
  int run(List<String> args, {Duration elapse = Duration.zero, void Function(FakeAsync async)? during}) {
    int? exitCode;
    fakeAsync((async) {
      interrupts = StreamController<void>.broadcast();
      CliApp(context).run(args).then((code) => exitCode = code);
      async.flushMicrotasks();
      during?.call(async);
      async.elapse(elapse);
      async.flushMicrotasks();
    });
    expect(exitCode, isNotNull, reason: 'the command did not finish');
    return exitCode!;
  }
}

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
