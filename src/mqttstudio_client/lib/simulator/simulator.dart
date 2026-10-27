import 'package:event/event.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/message_viewer/message_viewer.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/recorder/engine/recording_player.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/recorder/storage/recording_storage.dart';
import 'package:mqttstudio/simulator/engine/placeholders.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:mqttstudio/simulator/engine/simulator_runner.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/model/sparkplug_source.dart';
import 'package:mqttstudio/simulator/model/vda5050_source.dart';
import 'package:mqttstudio/simulator/sparkplug/simulated_edge_node.dart';
import 'package:mqttstudio/simulator/sparkplug/simulated_sparkplug_device.dart';
import 'package:mqttstudio/simulator/sparkplug/sparkplug_fault.dart';
import 'package:mqttstudio/simulator/vda5050/robot_fault.dart';
import 'package:mqttstudio/simulator/vda5050/simulated_fleet.dart';
import 'package:mqttstudio/simulator/vda5050/simulated_robot.dart';

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

  // the recordings of the recorded devices, by device id; null while it is missing
  final Map<String, RecordingInfo?> _recordings = {};

  // connectionFactory: the connections of Sparkplug edge nodes; tests pass fake ones
  Simulator({SimulatorRunner? runner, MqttAdapter Function()? connectionFactory}) {
    this.runner = runner ??
        SimulatorRunner(MqttAdapterPublisher(_mqttAdapter),
            openRecording: _openRecording,
            // Sparkplug edge nodes connect with the project's broker settings, each on its own connection
            connections: SimulatorConnections(
                settings: () => _projectManager.currentProject!.mqttSettings,
                factory: connectionFactory ?? MqttAdapter.new));
    _projectManager.projectClosedEvent.subscribe(_onProjectClosed);
    _projectManager.projectOpenedEvent.subscribe(_onProjectOpened);
    _mqttAdapter.onDisconnectedEvent.subscribe(_onDisconnected);
    this.runner.connectionLostEvent.subscribe(_onDisconnected);
    _library?.changedEvent.subscribe(_onLibraryChanged);
  }

  void dispose() {
    _projectManager.projectClosedEvent.unsubscribe(_onProjectClosed);
    _projectManager.projectOpenedEvent.unsubscribe(_onProjectOpened);
    _mqttAdapter.onDisconnectedEvent.unsubscribe(_onDisconnected);
    _library?.changedEvent.unsubscribe(_onLibraryChanged);
    runner.dispose();
  }

  RecordingLibrary? get _library => GetIt.I.isRegistered<RecordingLibrary>() ? GetIt.I.get<RecordingLibrary>() : null;

  // the recording a recorded device plays, null while it is not in the library (D23)
  RecordingInfo? recordingOf(SimulatedDevice device) => _recordings[device.id];

  // the recorded topics a recorded device plays: from its recording, else from its last run
  List<String> recordedTopicsOf(SimulatedDevice device) {
    var info = recordingOf(device);
    var playback = device.recorded?.playback;
    if (info != null && playback != null) {
      return info.footer.topics.where(playback.plays).toList()..sort();
    }
    return runner.recordedTopicsOf(device.id) ?? [];
  }

  // finds the recordings of the recorded devices again, e.g. after the library changed
  Future<void> refreshRecordings() async {
    var library = _library;
    _recordings.clear();
    if (library != null) {
      for (var device in devices.where((device) => device.isRecorded && device.recorded != null)) {
        _recordings[device.id] = await library.findSource(device.recorded!.recordingId, device.recorded!.fileName);
      }
    }
    simulationChangedEvent.broadcast();
  }

  Future<RecordingFile> _openRecording(RecordedSource source) async {
    var library = _library;
    var info = await library?.findSource(source.recordingId, source.fileName);
    if (library == null || info == null) {
      throw StateError('Recording ${source.recordingName} not found');
    }
    return library.store.open(info.fileName);
  }

  double _recordedRate(SimulatedDevice device) {
    var info = recordingOf(device);
    if (info == null || device.recorded == null) {
      return 0;
    }
    return RecordingPlayer.estimate(info, device.recorded!.playback).rate * device.instanceCount;
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
    _checkRate(all,
        recorded: devices
            .where((device) => !runner.isDeviceRunning(device.id))
            .fold(0.0, (sum, device) => sum + _deviceRate(device)));
    runner.startAll(simulation!);
  }

  void startDevice(SimulatedDevice device) {
    _checkRate(device.topics.map((topic) => (device, topic)),
        recorded: runner.isDeviceRunning(device.id) ? 0 : _deviceRate(device));
    runner.startDevice(device);
  }

  // msg/s of a recorded or VDA 5050 device; generated devices are estimated per topic
  double _deviceRate(SimulatedDevice device) => switch (device.kind) {
        DeviceKind.recorded => _recordedRate(device),
        DeviceKind.vda5050 => SimulatedFleet.rateOf(device),
        DeviceKind.sparkplug => SimulatedSparkplugDevice.rateOf(device),
        DeviceKind.generated => 0,
      };

  void startTopic(SimulatedDevice device, SimulatedTopic topic) {
    _checkRate([(device, topic)]);
    runner.start(device, [topic]);
  }

  void stopAll() => runner.stopAll();

  void stopDevice(SimulatedDevice device) => runner.stopDevice(device);

  void stopTopic(SimulatedTopic topic) => runner.stopTopic(topic.id);

  int clearRetained() =>
      runner.clearRetained([for (var device in devices) for (var topic in device.topics) (device, topic)]) +
      runner.clearRetainedConnections(devices);

  void _checkRate(Iterable<(SimulatedDevice, SimulatedTopic)> topics, {double recorded = 0}) {
    var rate = rateWith(topics) + recorded;
    if (rate > SimulationRules.maxRate) {
      throw SimulationRateException(rate);
    }
  }

  SimulatedDevice addDevice(SimulatedDevice device) {
    simulation!.devices.add(device);
    _changed();
    if (device.isRecorded) {
      refreshRecordings();
    }
    return device;
  }

  // replaces the device with the same id. Its running topics restart, so a new instance count applies at once.
  void updateDevice(SimulatedDevice edited) {
    var devices = simulation!.devices;
    var index = devices.indexWhere((device) => device.id == edited.id);
    var running = devices[index].topics.where((topic) => runner.isRunning(topic.id)).map((topic) => topic.id).toSet();
    devices[index] = edited;
    if (edited.isRecorded) {
      // D19: a playing recorded device restarts with its new settings
      if (runner.isDeviceRunning(edited.id)) {
        runner.startRecorded(edited);
      }
      refreshRecordings();
    } else if (edited.isVda5050 || edited.isSparkplug) {
      // D19: running robots and edge nodes start again with the new settings
      if (runner.isDeviceRunning(edited.id)) {
        runner.startDevice(edited);
      }
    } else {
      runner.restart(edited, edited.topics.where((topic) => running.contains(topic.id)));
    }
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

  // the device a new topic goes to: the given one, else the first generated one, else a new Default device.
  // Recorded devices have no topics of their own.
  SimulatedDevice deviceForNewTopic(String? deviceId) {
    var device = deviceId == null ? null : simulation!.deviceById(deviceId);
    if (device != null && device.isGenerated) {
      return device;
    }
    var generated = devices.where((device) => device.isGenerated);
    if (generated.isNotEmpty) {
      return generated.first;
    }
    return addDevice(SimulatedDevice(name: uniqueNewDeviceName(SimulatedDevice.defaultName)));
  }

  // the name itself if it is free, else with a number
  String uniqueNewDeviceName(String name) {
    var candidate = name;
    var number = 2;
    while (SimulationRules.isDuplicateDeviceName(candidate, simulation!)) {
      candidate = '$name $number';
      number++;
    }
    return candidate;
  }

  // a recorded device that plays the recording with the given options (the recorder tab's ADD TO SIMULATION)
  SimulatedDevice addRecordedDevice(RecordingInfo info, PlaybackOptions options) {
    var playback = options.copy();
    if (playback.isMaxSpeed) {
      playback.speed = 1;
    }
    return addDevice(SimulatedDevice(
      name: uniqueNewDeviceName(info.name),
      kind: DeviceKind.recorded,
      recorded: RecordedSource(
          recordingId: info.id, fileName: info.fileName, recordingName: info.name, playback: playback),
    ));
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

  // a device that simulates VDA 5050 robots, named uniquely
  SimulatedDevice newVda5050Device() => SimulatedDevice(
      name: uniqueNewDeviceName('VDA 5050 robots'), kind: DeviceKind.vda5050, instanceCount: 5, vda5050: Vda5050Source());

  SimulatedFleet? fleetOf(SimulatedDevice device) => runner.fleetOf(device.id);

  // a device of Sparkplug B edge nodes, named uniquely, from the example (doc/sparkplug-design.md §10.3)
  SimulatedDevice newSparkplugDevice() => SimulatedDevice(
      name: uniqueNewDeviceName('Sparkplug edge nodes'),
      kind: DeviceKind.sparkplug,
      instanceCount: 2,
      sparkplug: SparkplugSource.example());

  SimulatedSparkplugDevice? sparkplugOf(SimulatedDevice device) => runner.sparkplugOf(device.id);

  void injectSparkplugFault(SimulatedDevice device, SimulatedEdgeNode node, SparkplugFault fault) {
    var run = runner.sparkplugOf(device.id);
    if (run != null && run.isRunning) {
      run.inject(node, fault);
    }
  }

  void injectFault(SimulatedDevice device, SimulatedRobot robot, RobotFault fault) {
    var fleet = runner.fleetOf(device.id);
    if (fleet != null && fleet.isRunning && fleet.robots.contains(robot)) {
      fleet.inject(robot, fault);
    }
  }

  // the Topic Viewer subscription that receives every topic of the robots of a VDA 5050 device or of the edge nodes
  // of a Sparkplug device; null for the other kinds
  String? viewerSubscriptionOf(SimulatedDevice device) {
    var vda5050 = device.vda5050;
    if (device.isVda5050 && vda5050 != null) {
      return '${vda5050.interfaceName}/${vda5050.version.topicLevel}/${vda5050.manufacturer}/+/#';
    }
    var sparkplug = device.sparkplug;
    if (device.isSparkplug && sparkplug != null) {
      return 'spBv1.0/${sparkplug.groupId}/#';
    }
    return null;
  }

  bool isDeviceSubscribedInViewer(SimulatedDevice device) {
    var subscription = viewerSubscriptionOf(device);
    return (_projectManager.currentProject?.topicSubscriptions ?? <TopicSubscription>[])
        .any((sub) => sub.topic == subscription);
  }

  void subscribeDeviceInViewer(SimulatedDevice device) {
    var subscription = viewerSubscriptionOf(device);
    if (subscription != null && !isDeviceSubscribedInViewer(device)) {
      GetIt.I.get<MessageViewer>().addTopicSubscription(TopicSubscription(subscription, MqttQos.atLeastOnce));
    }
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

  // the Topic Viewer subscription that receives a recorded topic of all instances
  String recordedSubscriptionOf(SimulatedDevice device, String recordedTopic) =>
      Placeholders.toSubscription(SimulationRules.recordedTarget(device, recordedTopic), deviceName: device.name);

  bool isRecordedSubscribedInViewer(SimulatedDevice device, String recordedTopic) {
    var subscription = recordedSubscriptionOf(device, recordedTopic);
    return (_projectManager.currentProject?.topicSubscriptions ?? <TopicSubscription>[])
        .any((sub) => sub.topic == subscription);
  }

  void subscribeRecordedInViewer(SimulatedDevice device, String recordedTopic) {
    if (!isRecordedSubscribedInViewer(device, recordedTopic)) {
      GetIt.I
          .get<MessageViewer>()
          .addTopicSubscription(TopicSubscription(recordedSubscriptionOf(device, recordedTopic), MqttQos.atMostOnce));
    }
  }

  TopicColor? viewerColorOf(SimulatedDevice device, SimulatedTopic topic) => _viewerSubscription(device, topic)?.color;

  void subscribeInViewer(SimulatedDevice device, SimulatedTopic topic) {
    if (isSubscribedInViewer(device, topic)) {
      return;
    }
    GetIt.I.get<MessageViewer>().addTopicSubscription(TopicSubscription(subscriptionOf(device, topic), topic.qos));
  }

  void _changed() => simulationChangedEvent.broadcast();

  void _onProjectClosed(EventArgs _) => runner.reset();

  void _onProjectOpened(EventArgs _) => refreshRecordings();

  void _onLibraryChanged(EventArgs? _) => refreshRecordings();

  void _onDisconnected(EventArgs _) {
    if (runner.isAnyRunning) {
      runner.stopAll();
      stoppedByDisconnectEvent.broadcast();
    }
  }
}
