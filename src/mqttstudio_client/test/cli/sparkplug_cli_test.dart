import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/model/sparkplug_source.dart';
import '../helpers/cli_harness.dart';

Project sparkplugProject() {
  var project = Project(MqttSettings('broker.local', 'plant-01', 1883), name: 'Plant');
  project.simulation = Simulation(
    devices: [
      SimulatedDevice(
        name: 'Line 1',
        kind: DeviceKind.sparkplug,
        instanceCount: 2,
        sparkplug: SparkplugSource.example()
          ..seed = 1
          ..primaryHostId = 'scada',
      ),
    ],
  );
  return project;
}

void main() {
  test('the plan names the edge nodes and their group', () {
    var cli = Cli([sparkplugProject()]);
    expect(cli.run(['-o', 'json', 'simulate', '-p', 'Plant', '--dry-run']), 0);
    var plan = cli.events.firstWhere((event) => event['event'] == 'plan');
    expect(plan['devices'][0]['sparkplug'], 'Plant1');
    // an NDATA and a DDATA per edge node and second at most
    expect(plan['estimatedRate'], 4);
    var topic = cli.events.firstWhere((event) => event['event'] == 'topic');
    expect(topic['edgeNodes'], ['Edge1', 'Edge2']);
    expect(cli.adapters, isEmpty);
  });

  test('simulate runs each edge node and the host on a connection of its own', () {
    var cli = Cli([sparkplugProject()]);
    expect(cli.run(['-o', 'json', 'simulate', '-p', 'Plant', '--duration', '10s'], elapse: Duration(seconds: 11)), 0);
    // the main connection, the simulated host and two edge nodes
    expect(cli.adapters, hasLength(4));
    var edgeNodes = cli.adapters.where((adapter) => adapter.will?.topic.contains('/NDEATH/') ?? false).toList();
    expect(edgeNodes.map((adapter) => adapter.will!.topic), [
      'spBv1.0/Plant1/NDEATH/Edge1',
      'spBv1.0/Plant1/NDEATH/Edge2',
    ]);
    expect(edgeNodes.every((adapter) => adapter.connectedWith!.clientId.startsWith('plant-01-cli-')), isTrue);
    var host = cli.adapters.singleWhere((adapter) => adapter.will?.topic == 'spBv1.0/STATE/scada');
    expect(host.will!.retain, isTrue);
    // births after the host's STATE (the fake broker doesn't deliver it, so the edge nodes keep waiting)
    expect(edgeNodes.first.subscribed, contains('spBv1.0/STATE/scada'));
    expect(cli.adapters.every((adapter) => !adapter.isConnected()), isTrue);
    var stopped = cli.events.last;
    expect(stopped['reason'], 'duration');
  });

  test('without a primary host the edge nodes are born at once and say goodbye with NDEATH', () {
    var project = sparkplugProject();
    project.simulation.devices.single.sparkplug!.primaryHostId = null;
    var cli = Cli([project]);
    expect(cli.run(['-o', 'json', 'simulate', '-p', 'Plant', '--duration', '5s'], elapse: Duration(seconds: 6)), 0);
    var edge1 = cli.adapters.singleWhere((adapter) => adapter.will?.topic == 'spBv1.0/Plant1/NDEATH/Edge1');
    var topics = edge1.published.map((message) => message.topic).toList();
    expect(topics.first, 'spBv1.0/Plant1/NBIRTH/Edge1');
    expect(topics[1], 'spBv1.0/Plant1/DBIRTH/Edge1/Pump');
    expect(topics.last, 'spBv1.0/Plant1/NDEATH/Edge1');
    expect(topics.where((topic) => topic.contains('DATA')), isNotEmpty);
    expect(cli.events.last['sent'], greaterThan(topics.length));
  });
}
