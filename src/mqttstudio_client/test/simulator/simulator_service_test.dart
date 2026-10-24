import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/simulator.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_setup.dart';

void main() {
  late FakeMqttAdapter adapter;
  late Simulator simulator;
  late Project project;

  // opens a project inside fakeAsync, where futures only complete when the microtasks are flushed
  void openProject(FakeAsync async) {
    openNewProject().then((p) => project = p);
    async.flushMicrotasks();
    adapter.connect(project.mqttSettings);
    async.flushMicrotasks();
  }

  SimulatedTopic addTopic(String topic, {int intervalMs = 1000, SimulatedDevice? device}) {
    var target = device ?? project.simulation.devices.first;
    var simulated = SimulatedTopic(topic: topic, generator: const CounterGenerator(), interval: PublishInterval(minMs: intervalMs));
    simulator.addTopic(target, simulated);
    return simulated;
  }

  setUp(() {
    adapter = setUpServices();
    simulator = GetIt.I.get<Simulator>();
  });
  tearDown(() async {
    simulator.dispose();
    await tearDownServices();
  });

  test('a new project has a Default device', () {
    fakeAsync((async) {
      openProject(async);
      expect(simulator.devices.single.name, SimulatedDevice.defaultName);
    });
  });

  test('starting publishes through the MQTT adapter as binary payloads', () {
    fakeAsync((async) {
      openProject(async);
      addTopic('sim/a');
      simulator.startAll();
      async.elapse(const Duration(seconds: 3));
      var published = adapter.published.where((m) => m.topic == 'sim/a').toList();
      expect(published.length, inInclusiveRange(2, 3));
      expect(utf8.decode(published.first.payload.toList()), '1');
      simulator.stopAll();
    });
  });

  test('a disconnect stops the simulation and is reported', () {
    fakeAsync((async) {
      openProject(async);
      addTopic('sim/a');
      var stopped = 0;
      simulator.stoppedByDisconnectEvent.subscribe((_) => stopped++);
      simulator.startAll();
      async.elapse(const Duration(seconds: 2));

      adapter.dropConnection();
      expect(simulator.runner.isAnyRunning, isFalse);
      expect(stopped, 1);
    });
  });

  test('closing the project stops and resets', () {
    fakeAsync((async) {
      openProject(async);
      var topic = addTopic('sim/a');
      simulator.startAll();
      async.elapse(const Duration(seconds: 2));
      GetIt.I.get<ProjectManager>().closeProject(true);
      async.flushMicrotasks();
      expect(simulator.runner.isAnyRunning, isFalse);
      expect(simulator.runner.statsOf(topic.id).sent, 0);
    });
  });

  test('starting above the rate limit is refused', () {
    fakeAsync((async) {
      openProject(async);
      var device = SimulatedDevice(name: 'Many', instanceCount: 200);
      simulator.addDevice(device);
      addTopic('a/{n}', intervalMs: 100, device: device);
      expect(() => simulator.startDevice(device), throwsA(isA<SimulationRateException>()));
      expect(simulator.runner.isAnyRunning, isFalse);
    });
  });

  test('running does not mark the project as changed, editing does', () {
    fakeAsync((async) {
      openProject(async);
      var manager = GetIt.I.get<ProjectManager>();
      addTopic('sim/a');
      manager.lastSavedProjectHash = project.getHash();
      simulator.startAll();
      async.elapse(const Duration(seconds: 5));
      expect(manager.hasProjectChanged(), isFalse);

      addTopic('sim/b');
      expect(manager.hasProjectChanged(), isTrue);
      simulator.stopAll();
    });
  });

  test('updating a running topic restarts it with the new configuration', () {
    fakeAsync((async) {
      openProject(async);
      var topic = addTopic('sim/a');
      var device = project.simulation.devices.first;
      simulator.startAll();
      async.elapse(const Duration(seconds: 3));

      var edited = topic.copy()..generator = const CounterGenerator(start: 50);
      simulator.updateTopic(device, edited);
      expect(simulator.runner.isRunning(topic.id), isTrue);
      adapter.published.clear();
      async.elapse(const Duration(seconds: 2));
      expect(utf8.decode(adapter.published.first.payload.toList()), '50');
      simulator.stopAll();
    });
  });

  test('deleting stops first, duplicating gives unique names and new ids', () {
    fakeAsync((async) {
      openProject(async);
      var topic = addTopic('sim/a');
      var device = project.simulation.devices.first;
      simulator.startAll();
      simulator.deleteTopic(device, topic);
      expect(simulator.runner.isAnyRunning, isFalse);
      expect(device.topics, isEmpty);

      var copy = simulator.duplicateDevice(device);
      var second = simulator.duplicateDevice(device);
      expect(copy.name, 'Default (copy)');
      expect(second.name, 'Default (copy 2)');
      expect(copy.id, isNot(device.id));
    });
  });

  test('new topics go to the selected device, else the first one, else a new Default device', () {
    fakeAsync((async) {
      openProject(async);
      var second = simulator.addDevice(SimulatedDevice(name: 'Second'));
      expect(simulator.deviceForNewTopic(second.id), same(second));
      expect(simulator.deviceForNewTopic(null), same(project.simulation.devices.first));
      project.simulation.devices.clear();
      expect(simulator.deviceForNewTopic(null).name, SimulatedDevice.defaultName);
    });
  });

  test('subscribe in the Topic Viewer uses + for the instance level', () {
    fakeAsync((async) {
      openProject(async);
      var device = simulator.addDevice(SimulatedDevice(name: 'Weather', instanceCount: 3));
      var topic = addTopic('weather/{n}/temp', device: device);
      expect(simulator.isSubscribedInViewer(device, topic), isFalse);
      simulator.subscribeInViewer(device, topic);
      simulator.subscribeInViewer(device, topic);
      expect(project.topicSubscriptions.map((s) => s.topic), ['weather/+/temp']);
      expect(simulator.isSubscribedInViewer(device, topic), isTrue);
      expect(simulator.viewerColorOf(device, topic), isNotNull);
    });
  });

  test('clear retained publishes to every instance of retained topics', () {
    fakeAsync((async) {
      openProject(async);
      var device = simulator.addDevice(SimulatedDevice(name: 'Weather', instanceCount: 2));
      addTopic('w/{n}', device: device).retain = true;
      expect(simulator.clearRetained(), 2);
      expect(adapter.published.map((m) => (m.topic, m.retain)), [('w/1', true), ('w/2', true)]);
    });
  });
}
