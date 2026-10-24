import 'package:event/event.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/message_viewer/message_viewer.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/simulator/engine/placeholders.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:mqttstudio/simulator/engine/simulator_runner.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';

// thrown when starting would publish more messages per second than the app allows
class SimulationRateException implements Exception {
  final double rate;
  SimulationRateException(this.rate);
}

// Domain service of the simulator tab: edits the simulation of the current project and runs it. Stops the simulation
// when the broker disconnects or the project is closed.
class Simulator {
  final _mqttAdapter = GetIt.I.get<MqttAdapter>();
  final _projectManager = GetIt.I.get<ProjectManager>();
  late final SimulatorRunner runner;

  // the devices or topics of the simulation changed
  final simulationChangedEvent = Event();
  // the simulation was running and stopped because the broker disconnected
  final stoppedByDisconnectEvent = Event();

  Simulator({SimulatorRunner? runner}) {
    this.runner = runner ?? SimulatorRunner(MqttAdapterPublisher(_mqttAdapter));
    _projectManager.projectClosedEvent.subscribe(_onProjectClosed);
    _projectManager.projectOpenedEvent.subscribe(_onProjectOpened);
    _mqttAdapter.onDisconnectedEvent.subscribe(_onDisconnected);
    this.runner.connectionLostEvent.subscribe(_onDisconnected);
  }

  void dispose() {
    _projectManager.projectClosedEvent.unsubscribe(_onProjectClosed);
    _projectManager.projectOpenedEvent.unsubscribe(_onProjectOpened);
    _mqttAdapter.onDisconnectedEvent.unsubscribe(_onDisconnected);
    runner.dispose();
  }

  Simulation? get simulation => _projectManager.currentProject?.simulation;

  bool get isConnected => _mqttAdapter.isConnected();

  List<SimulatedDevice> get devices => simulation?.devices ?? [];

  // msg/s once the given topics run in addition to the running ones
  double rateWith(Iterable<(SimulatedDevice, SimulatedTopic)> topics) =>
      runner.runningRate +
      SimulationRules.estimateRate(topics.where((entry) => !runner.isRunning(entry.$2.id)));

  void startAll() {
    var all = [for (var device in devices) for (var topic in device.topics) (device, topic)];
    _checkRate(all);
    runner.startAll(simulation!);
  }

  void startDevice(SimulatedDevice device) {
    _checkRate(device.topics.map((topic) => (device, topic)));
    runner.startDevice(device);
  }

  void startTopic(SimulatedDevice device, SimulatedTopic topic) {
    _checkRate([(device, topic)]);
    runner.start(device, [topic]);
  }

  void stopAll() => runner.stopAll();

  void stopDevice(SimulatedDevice device) => runner.stopDevice(device);

  void stopTopic(SimulatedTopic topic) => runner.stopTopic(topic.id);

  int clearRetained() => runner.clearRetained([for (var device in devices) for (var topic in device.topics) (device, topic)]);

  void _checkRate(Iterable<(SimulatedDevice, SimulatedTopic)> topics) {
    var rate = rateWith(topics);
    if (rate > SimulationRules.maxRate) {
      throw SimulationRateException(rate);
    }
  }

  SimulatedDevice addDevice(SimulatedDevice device) {
    simulation!.devices.add(device);
    _changed();
    return device;
  }

  // replaces the device with the same id. Its running topics restart, so a new instance count applies at once.
  void updateDevice(SimulatedDevice edited) {
    var devices = simulation!.devices;
    var index = devices.indexWhere((device) => device.id == edited.id);
    var running = devices[index].topics.where((topic) => runner.isRunning(topic.id)).map((topic) => topic.id).toSet();
    devices[index] = edited;
    runner.restart(edited, edited.topics.where((topic) => running.contains(topic.id)));
    _changed();
  }

  void deleteDevice(SimulatedDevice device) {
    runner.stopDevice(device);
    simulation!.devices.removeWhere((d) => d.id == device.id);
    _changed();
  }

  SimulatedDevice duplicateDevice(SimulatedDevice device) {
    var copy = device.copy(newIds: true)..name = uniqueDeviceName(device.name);
    var devices = simulation!.devices;
    devices.insert(devices.indexWhere((d) => d.id == device.id) + 1, copy);
    _changed();
    return copy;
  }

  // the device a new topic goes to: the given one, else the first one, else a new Default device
  SimulatedDevice deviceForNewTopic(String? deviceId) {
    var device = deviceId == null ? null : simulation!.deviceById(deviceId);
    if (device != null) {
      return device;
    }
    if (devices.isNotEmpty) {
      return devices.first;
    }
    return addDevice(SimulatedDevice(name: SimulatedDevice.defaultName));
  }

  void addTopic(SimulatedDevice device, SimulatedTopic topic) {
    device.topics.add(topic);
    _changed();
  }

  // replaces the topic with the same id and restarts it if it was running
  void updateTopic(SimulatedDevice device, SimulatedTopic edited) {
    var index = device.topics.indexWhere((topic) => topic.id == edited.id);
    device.topics[index] = edited;
    runner.restart(device, [edited]);
    _changed();
  }

  void deleteTopic(SimulatedDevice device, SimulatedTopic topic) {
    runner.stopTopic(topic.id);
    device.topics.removeWhere((t) => t.id == topic.id);
    _changed();
  }

  SimulatedTopic duplicateTopic(SimulatedDevice device, SimulatedTopic topic) {
    var copy = topic.copy(newId: true);
    device.topics.insert(device.topics.indexWhere((t) => t.id == topic.id) + 1, copy);
    _changed();
    return copy;
  }

  String uniqueDeviceName(String name) {
    var candidate = '$name (copy)';
    var number = 2;
    while (SimulationRules.isDuplicateDeviceName(candidate, simulation!)) {
      candidate = '$name (copy $number)';
      number++;
    }
    return candidate;
  }

  // the Topic Viewer subscription that receives all instances of the topic
  String subscriptionOf(SimulatedDevice device, SimulatedTopic topic) =>
      Placeholders.toSubscription(topic.topic, deviceName: device.name);

  TopicSubscription? _viewerSubscription(SimulatedDevice device, SimulatedTopic topic) {
    var subscription = subscriptionOf(device, topic);
    for (var sub in _projectManager.currentProject?.topicSubscriptions ?? <TopicSubscription>[]) {
      if (sub.topic == subscription) {
        return sub;
      }
    }
    return null;
  }

  bool isSubscribedInViewer(SimulatedDevice device, SimulatedTopic topic) => _viewerSubscription(device, topic) != null;

  TopicColor? viewerColorOf(SimulatedDevice device, SimulatedTopic topic) => _viewerSubscription(device, topic)?.color;

  void subscribeInViewer(SimulatedDevice device, SimulatedTopic topic) {
    if (isSubscribedInViewer(device, topic)) {
      return;
    }
    GetIt.I.get<MessageViewer>().addTopicSubscription(TopicSubscription(subscriptionOf(device, topic), topic.qos));
  }

  void _changed() => simulationChangedEvent.broadcast();

  void _onProjectClosed(EventArgs _) => runner.reset();

  void _onProjectOpened(EventArgs _) => simulationChangedEvent.broadcast();

  void _onDisconnected(EventArgs _) {
    if (runner.isAnyRunning) {
      runner.stopAll();
      stoppedByDisconnectEvent.broadcast();
    }
  }
}
