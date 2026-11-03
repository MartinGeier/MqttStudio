import 'dart:async';
import 'dart:math';
import 'package:clock/clock.dart';
import 'package:event/event.dart';
import 'package:mqttstudio/mqtt/side_connection.dart';
import 'package:mqttstudio/simulator/engine/placeholders.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/sparkplug/simulated_edge_node.dart';
import 'package:mqttstudio/simulator/sparkplug/simulated_host.dart';
import 'package:mqttstudio/simulator/sparkplug/sparkplug_fault.dart';

// The running edge nodes of one Sparkplug device, one per instance, and the primary host when the simulator plays it
// (doc/sparkplug-design.md §10.4). Each has a connection of its own.
class SimulatedSparkplugDevice {
  final SimulatedDevice device;
  final List<SimulatedEdgeNode> nodes;
  final SimulatedHost? host;
  final changedEvent = Event();
  bool _running = false;

  SimulatedSparkplugDevice._(this.device, this.nodes, this.host);

  factory SimulatedSparkplugDevice(
    SimulatedDevice device,
    SimulatorConnections connections,
    Random random, {
    void Function()? onPublished,
  }) {
    var source = device.sparkplug!;
    var settings = connections.settings();
    var startedAt = clock.now();
    var nodes = [
      for (var n in device.instanceNumbers)
        SimulatedEdgeNode(
          source,
          instance: n,
          settings: SideConnection.settingsFor(
            settings,
            'spb-${Placeholders.resolve(source.edgeNodeId, instance: n, deviceName: device.name)}',
          ),
          connectionFactory: connections.factory,
          random: Random(random.nextInt(0x7fffffff)),
          startedAt: startedAt,
          deviceName: device.name,
        )..onPublished = onPublished,
    ];
    var hostId = source.primaryHostId;
    var host = hostId != null && hostId.isNotEmpty && source.simulateHost
        ? SimulatedHost(
            hostId,
            settings: SideConnection.settingsFor(settings, 'spb-host'),
            connectionFactory: connections.factory,
          )
        : null;
    var simulated = SimulatedSparkplugDevice._(device, nodes, host);
    for (var node in nodes) {
      node.changedEvent.subscribe((_) => simulated.changedEvent.broadcast());
    }
    return simulated;
  }

  bool get isRunning => _running;

  int get sent => nodes.fold(0, (sum, node) => sum + node.messages);

  // the most messages per second: every scan an NDATA and a DDATA per device, when all of them change
  static double rateOf(SimulatedDevice device) {
    var source = device.sparkplug;
    if (source == null || source.scanMs <= 0) {
      return 0;
    }
    var devices = source.devices.fold(0, (sum, spec) => sum + spec.count);
    return device.instanceCount * (1 + devices) * 1000 / source.scanMs;
  }

  // metric changes per second at most, for the limit of Q9
  static double changesOf(SimulatedDevice device) {
    var source = device.sparkplug;
    if (source == null || source.scanMs <= 0) {
      return 0;
    }
    var metrics =
        source.nodeMetrics.length + source.devices.fold(0, (sum, spec) => sum + spec.count * spec.metrics.length);
    return device.instanceCount * metrics * 1000 / source.scanMs;
  }

  // throws when the simulated host can't connect; the edge nodes keep trying on their own
  Future<void> start() async {
    _running = true;
    changedEvent.broadcast();
    await host?.start();
    if (!_running) {
      host?.stop();
      return;
    }
    for (var node in nodes) {
      unawaited(node.start());
    }
  }

  Future<void> stop() async {
    _running = false;
    for (var node in nodes) {
      await node.stop();
    }
    host?.stop();
    changedEvent.broadcast();
  }

  void inject(SimulatedEdgeNode node, SparkplugFault fault) {
    if (_running && nodes.contains(node)) {
      node.inject(fault);
    }
  }
}
