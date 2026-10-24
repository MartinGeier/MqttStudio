import 'package:easy_localization/easy_localization.dart';
import 'package:event/event.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/message_viewer/message_viewer.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/engine/simulator_runner.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/simulator.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the simulator tab
class SimulatorViewmodel extends SrxChangeNotifier {
  final _simulator = GetIt.I.get<Simulator>();
  final _mqttAdapter = GetIt.I.get<MqttAdapter>();
  final _projectManager = GetIt.I.get<ProjectManager>();
  final _messageViewer = GetIt.I.get<MessageViewer>();

  // collapsed devices, all devices are expanded by default
  final Set<String> _collapsed = {};
  String? selectedDeviceId;

  void Function(String message)? onError;
  void Function()? onStoppedByDisconnect;

  SimulatorViewmodel() {
    _simulator.simulationChangedEvent.subscribe(_onChanged);
    _simulator.stoppedByDisconnectEvent.subscribe(_onStoppedByDisconnect);
    _simulator.runner.runStateChangedEvent.subscribe(_onChanged);
    _simulator.runner.statsChangedEvent.subscribe(_onChanged);
    _mqttAdapter.onConnectedEvent.subscribe(_onChanged);
    _mqttAdapter.onDisconnectedEvent.subscribe(_onChanged);
    _projectManager.projectOpenedEvent.subscribe(_onChanged);
    _projectManager.projectClosedEvent.subscribe(_onChanged);
    _messageViewer.topicSubscriptionsChangedEvent.subscribe(_onChanged);
  }

  @override
  void dispose() {
    _simulator.simulationChangedEvent.unsubscribe(_onChanged);
    _simulator.stoppedByDisconnectEvent.unsubscribe(_onStoppedByDisconnect);
    _simulator.runner.runStateChangedEvent.unsubscribe(_onChanged);
    _simulator.runner.statsChangedEvent.unsubscribe(_onChanged);
    _mqttAdapter.onConnectedEvent.unsubscribe(_onChanged);
    _mqttAdapter.onDisconnectedEvent.unsubscribe(_onChanged);
    _projectManager.projectOpenedEvent.unsubscribe(_onChanged);
    _projectManager.projectClosedEvent.unsubscribe(_onChanged);
    _messageViewer.topicSubscriptionsChangedEvent.unsubscribe(_onChanged);
    super.dispose();
  }

  bool get isProjectOpen => _projectManager.isProjectOpen;

  bool get isConnected => _mqttAdapter.isConnected();

  bool get canStart => isProjectOpen && isConnected;

  List<SimulatedDevice> get devices => _simulator.devices;

  int get topicCount => devices.fold(0, (sum, device) => sum + device.topics.length);

  int get runningCount => _simulator.runner.runningTopicIds.length;

  double get runningRate => _simulator.runner.runningRate;

  bool get isRateHigh => runningRate > (kIsWeb ? SimulationRules.webWarningRate : SimulationRules.warningRate);

  bool get isAnyRunning => _simulator.runner.isAnyRunning;

  bool get hasRetainedTopics => devices.any((device) => device.topics.any((topic) => topic.retain));

  TopicRunState stateOf(SimulatedTopic topic) => _simulator.runner.stateOf(topic.id);

  TopicStats statsOf(SimulatedTopic topic) => _simulator.runner.statsOf(topic.id);

  int runningCountOf(SimulatedDevice device) =>
      device.topics.where((topic) => stateOf(topic) == TopicRunState.running).length;

  int errorCountOf(SimulatedDevice device) => device.topics.where((topic) => stateOf(topic) == TopicRunState.error).length;

  bool isExpanded(SimulatedDevice device) => !_collapsed.contains(device.id);

  void toggleExpanded(SimulatedDevice device) {
    if (!_collapsed.remove(device.id)) {
      _collapsed.add(device.id);
    }
    notifyListeners();
  }

  void selectDevice(SimulatedDevice device) {
    selectedDeviceId = device.id;
    notifyListeners();
  }

  bool isSubscribedInViewer(SimulatedDevice device, SimulatedTopic topic) =>
      _simulator.isSubscribedInViewer(device, topic);

  TopicColor? viewerColorOf(SimulatedDevice device, SimulatedTopic topic) => _simulator.viewerColorOf(device, topic);

  String subscriptionOf(SimulatedDevice device, SimulatedTopic topic) => _simulator.subscriptionOf(device, topic);

  void startAll() => _guard(_simulator.startAll);

  void stopAll() => _simulator.stopAll();

  void startDevice(SimulatedDevice device) => _guard(() => _simulator.startDevice(device));

  void stopDevice(SimulatedDevice device) => _simulator.stopDevice(device);

  void startTopic(SimulatedDevice device, SimulatedTopic topic) => _guard(() => _simulator.startTopic(device, topic));

  void stopTopic(SimulatedTopic topic) => _simulator.stopTopic(topic);

  int clearRetained() => _simulator.clearRetained();

  void subscribeInViewer(SimulatedDevice device, SimulatedTopic topic) => _simulator.subscribeInViewer(device, topic);

  void addDevice(SimulatedDevice device) {
    _simulator.addDevice(device);
    selectedDeviceId = device.id;
  }

  void updateDevice(SimulatedDevice device) => _simulator.updateDevice(device);

  void deleteDevice(SimulatedDevice device) => _simulator.deleteDevice(device);

  void duplicateDevice(SimulatedDevice device) => _simulator.duplicateDevice(device);

  SimulatedDevice deviceForNewTopic() => _simulator.deviceForNewTopic(selectedDeviceId);

  void addTopic(SimulatedDevice device, SimulatedTopic topic) {
    _simulator.addTopic(device, topic);
    _collapsed.remove(device.id);
  }

  void updateTopic(SimulatedDevice device, SimulatedTopic topic) => _simulator.updateTopic(device, topic);

  void deleteTopic(SimulatedDevice device, SimulatedTopic topic) => _simulator.deleteTopic(device, topic);

  void duplicateTopic(SimulatedDevice device, SimulatedTopic topic) => _simulator.duplicateTopic(device, topic);

  void _guard(void Function() start) {
    try {
      start();
    } on SimulationRateException catch (exc) {
      onError?.call('simulator.ratelimit.error'
          .tr(args: [exc.rate.round().toString(), SimulationRules.maxRate.round().toString()]));
    }
  }

  void _onChanged(EventArgs? _) => notifyListeners();

  void _onStoppedByDisconnect(EventArgs? _) {
    onStoppedByDisconnect?.call();
    notifyListeners();
  }
}
