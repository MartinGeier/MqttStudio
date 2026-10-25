import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_reader.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:mqttstudio/simulator/engine/simulator_runner.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/model/vda5050_source.dart';
import 'package:mqttstudio/simulator/vda5050/fleet_layout.dart';
import 'package:mqttstudio/simulator/vda5050/robot_fault.dart';
import 'package:mqttstudio/simulator/vda5050/simulated_fleet.dart';
import 'package:typed_data/typed_buffers.dart';

import '../../protocol/vda5050_shapes.dart';

class _Message {
  final String topic;
  final Map<String, Object?> json;
  final MqttQos qos;
  final bool retain;
  final MqttMessageProperties? properties;
  final Duration at;

  _Message(this.topic, this.json, this.qos, this.retain, this.properties, this.at);

  String get type => topic.split('/').last;

  String get robot => topic.split('/')[3];
}

class _Publisher implements SimulatorPublisher {
  final FakeAsync async;
  final List<_Message> sent = [];
  @override
  bool isConnected = true;
  @override
  bool supportsProperties = true;

  _Publisher(this.async);

  @override
  void publish(String topic, Uint8Buffer payload, MqttQos qos, bool retain, MqttMessageProperties? properties) {
    var text = utf8.decode(payload);
    sent.add(_Message(topic, text.isEmpty ? {} : jsonDecode(text) as Map<String, Object?>, qos, retain, properties,
        async.elapsed));
  }

  List<_Message> of(String type, [String? robot]) =>
      sent.where((m) => m.type == type && (robot == null || m.robot == robot)).toList();
}

SimulatedDevice _device(VdaVersion version, {int robots = 3, Vda5050Source? source}) => SimulatedDevice(
      name: 'fleet',
      kind: DeviceKind.vda5050,
      instanceCount: robots,
      vda5050: (source ?? Vda5050Source(maxIdleSec: 2, actionProbability: 0.5, minActionSec: 1, maxActionSec: 3))
        ..version = version
        ..interfaceName = version.isV3 ? 'vda5050' : 'uagv'
        ..seed = 42,
    );

// runs the device on a runner for the given time and returns what was published
(SimulatorRunner, _Publisher) _run(FakeAsync async, SimulatedDevice device, Duration time) {
  var publisher = _Publisher(async);
  var runner = SimulatorRunner(publisher, seed: 1);
  runner.startDevice(device);
  async.elapse(time);
  return (runner, publisher);
}

void main() {
  for (var version in VdaVersion.values) {
    group('VDA 5050 ${version.protocolVersion}', () {
      test('every message has the shape of its schema and the right QoS and retain', () {
        fakeAsync((async) {
          var (runner, publisher) = _run(async, _device(version), const Duration(minutes: 5));
          runner.stopAll();
          expect(publisher.sent.length, greaterThan(500));
          for (var message in publisher.sent) {
            expect(shapeErrors(message.type, version, message.json), isEmpty, reason: '${message.topic} ${message.json}');
            expect(message.json['version'], version.protocolVersion);
            expect(message.properties?.contentType, 'application/json');
            var connection = message.type == VdaTopic.connection;
            expect(message.qos, connection ? MqttQos.atLeastOnce : MqttQos.atMostOnce);
            expect(message.retain, connection);
          }
          var types = publisher.sent.map((message) => message.type).toSet();
          expect(types, containsAll(['connection', 'factsheet', 'state', 'visualization', 'order']));
          expect(types.contains(VdaTopic.zoneSet), version.isV3);
          runner.dispose();
        });
      });

      test('robots start online, drive their orders and say goodbye', () {
        fakeAsync((async) {
          var device = _device(version);
          var (runner, publisher) = _run(async, device, const Duration(minutes: 3));
          var fleet = runner.fleetOf(device.id)!;
          for (var robot in fleet.robots) {
            var connections = publisher.of(VdaTopic.connection, robot.serialNumber);
            expect(connections.first.json['connectionState'], 'ONLINE');
            var states = publisher.of(VdaTopic.state, robot.serialNumber);
            expect(states.map((m) => m.json['lastNodeId']).toSet().length, greaterThan(2), reason: 'the robot moves');
            expect(states.any((m) => m.json['driving'] == true), isTrue);
          }
          runner.stopAll();
          for (var robot in fleet.robots) {
            var last = publisher.of(VdaTopic.connection, robot.serialNumber).last;
            expect(last.json['connectionState'], 'OFFLINE');
          }
          runner.dispose();
        });
      });

      test('header ids count per topic and robot, state comes at least every heartbeat', () {
        fakeAsync((async) {
          var (runner, publisher) = _run(async, _device(version, robots: 2), const Duration(minutes: 4));
          var bySender = <String, List<_Message>>{};
          for (var message in publisher.sent) {
            bySender.putIfAbsent(message.topic, () => []).add(message);
          }
          for (var messages in bySender.values) {
            var ids = messages.map((m) => m.json['headerId'] as int).toList();
            expect(ids, List.generate(ids.length, (i) => i), reason: messages.first.topic);
          }
          for (var states in bySender.entries.where((entry) => entry.key.endsWith('/state')).map((e) => e.value)) {
            for (var i = 1; i < states.length; i++) {
              expect(states[i].at - states[i - 1].at, lessThanOrEqualTo(const Duration(seconds: 30)));
            }
          }
          runner.dispose();
        });
      });

      test('orders alternate nodes and edges, and updates continue at the stitching node', () {
        fakeAsync((async) {
          var (runner, publisher) = _run(async, _device(version), const Duration(minutes: 5));
          var orders = publisher.of(VdaTopic.order);
          expect(orders.length, greaterThan(5));
          var updates = 0;
          var last = <String, Map<String, Object?>>{};
          for (var message in orders) {
            var order = Vda5050Reader.read(VdaTopic.order, message.json) as VdaOrder;
            var sequence = [
              ...order.nodes.map((node) => node.sequenceId),
              ...order.edges.map((edge) => edge.sequenceId),
            ]..sort();
            expect(sequence, List.generate(sequence.length, (i) => sequence.first + i));
            expect(order.nodes.every((node) => node.sequenceId.isEven), isTrue);
            var released = [...order.nodes, ...order.edges.map((e) => e)];
            expect(released, isNotEmpty);
            var previous = last[order.orderId];
            if (previous == null) {
              expect(order.orderUpdateId, 0);
              expect(order.nodes.first.sequenceId, 0);
            } else {
              updates++;
              var before = Vda5050Reader.read(VdaTopic.order, previous) as VdaOrder;
              expect(order.orderUpdateId, before.orderUpdateId + 1);
              var lastBase = before.nodes.where((node) => node.released).last;
              expect(order.nodes.first.nodeId, lastBase.nodeId);
              expect(order.nodes.first.sequenceId, lastBase.sequenceId);
            }
            last[order.orderId] = message.json;
          }
          expect(updates, greaterThan(0));
          runner.dispose();
        });
      });

      test('two robots never stand on or drive to the same node', () {
        fakeAsync((async) {
          var publisher = _Publisher(async);
          var runner = SimulatorRunner(publisher, seed: 1);
          var device = _device(version, robots: 6);
          runner.startDevice(device);
          var fleet = runner.fleetOf(device.id)!;
          for (var second = 0; second < 300; second++) {
            async.elapse(const Duration(seconds: 1));
            // a route may turn back through a node it passed, so the nodes of one robot are a set
            var reserved = <String>[];
            for (var robot in fleet.robots) {
              reserved.addAll({
                robot.lastNodeId,
                ...robot.remainingNodes.where((node) => node.released).map((node) => node.nodeId),
              });
            }
            expect(reserved.toSet().length, reserved.length, reason: 'at ${second}s: $reserved');
          }
          runner.dispose();
        });
      });

      test('the same seed gives the same messages', () {
        List<String> run() {
          late List<String> payloads;
          fakeAsync((async) {
            var (runner, publisher) = _run(async, _device(version), const Duration(minutes: 1));
            payloads = publisher.sent.map((m) => '${m.topic} ${jsonEncode(m.json)}').toList();
            runner.dispose();
          }, initialTime: DateTime.utc(2026, 10, 25, 8));
          return payloads;
        }

        expect(run(), run());
      });
    });
  }

  group('faults', () {
    late FakeAsync async;
    late _Publisher publisher;
    late SimulatorRunner runner;
    late SimulatedFleet fleet;

    void start(FakeAsync fake, {VdaVersion version = VdaVersion.v3, Vda5050Source? source}) {
      async = fake;
      publisher = _Publisher(async);
      runner = SimulatorRunner(publisher, seed: 1);
      var device = _device(version, robots: 2, source: source);
      runner.startDevice(device);
      fleet = runner.fleetOf(device.id)!;
      async.elapse(const Duration(seconds: 20));
    }

    Map<String, Object?> lastState(String serial) => publisher.of(VdaTopic.state, serial).last.json;

    test('a fatal error stops the robot until it is cleared', () {
      fakeAsync((fake) {
        start(fake);
        var robot = fleet.robots.first;
        fleet.inject(robot, RobotFault.fatal);
        async.elapse(const Duration(seconds: 1));
        var errors = lastState(robot.serialNumber)['errors'] as List;
        expect(errors.single, containsPair('errorLevel', 'FATAL'));
        var from = publisher.sent.length;
        async.elapse(const Duration(seconds: 30));
        var states = publisher.sent.skip(from).where((m) => m.type == VdaTopic.state && m.robot == robot.serialNumber);
        expect(states.every((m) => m.json['driving'] == false), isTrue);
        fleet.inject(robot, RobotFault.clearErrors);
        async.elapse(const Duration(seconds: 1));
        expect(lastState(robot.serialNumber)['errors'], isEmpty);
        runner.dispose();
      });
    });

    test('pause sends startPause and the robot reports paused', () {
      fakeAsync((fake) {
        start(fake);
        var robot = fleet.robots.first;
        fleet.inject(robot, RobotFault.pause);
        async.elapse(const Duration(milliseconds: 200));
        var instant = publisher.of(VdaTopic.instantActions, robot.serialNumber).single;
        expect((instant.json['actions'] as List).single, containsPair('actionType', 'startPause'));
        var state = lastState(robot.serialNumber);
        expect(state['paused'], isTrue);
        expect((state['instantActionStates'] as List).single, containsPair('actionStatus', 'FINISHED'));
        expect(fleet.isFaultActive(robot, RobotFault.pause), isTrue);
        fleet.inject(robot, RobotFault.pause);
        async.elapse(const Duration(milliseconds: 200));
        expect(lastState(robot.serialNumber)['paused'], isFalse);
        runner.dispose();
      });
    });

    test('a broken connection is published retained and the robot stays silent until it reconnects', () {
      fakeAsync((fake) {
        start(fake, version: VdaVersion.v2);
        var robot = fleet.robots.first;
        fleet.inject(robot, RobotFault.connectionBroken);
        var broken = publisher.of(VdaTopic.connection, robot.serialNumber).last;
        expect(broken.json['connectionState'], 'CONNECTIONBROKEN');
        expect(broken.retain, isTrue);
        var from = publisher.sent.length;
        async.elapse(const Duration(minutes: 1));
        expect(publisher.sent.skip(from).where((m) => m.robot == robot.serialNumber && m.type != VdaTopic.order), isEmpty);
        expect(fleet.isFaultAvailable(robot, RobotFault.reconnect), isTrue);
        fleet.inject(robot, RobotFault.reconnect);
        async.elapse(const Duration(seconds: 1));
        expect(publisher.of(VdaTopic.connection, robot.serialNumber).last.json['connectionState'], 'ONLINE');
        expect(publisher.of(VdaTopic.state, robot.serialNumber).last.at, greaterThan(const Duration(minutes: 1)));
        runner.dispose();
      });
    });

    test('protocol faults break exactly what they say', () {
      fakeAsync((fake) {
        start(fake);
        var robot = fleet.robots.first;
        var serial = robot.serialNumber;
        var before = lastState(serial)['headerId'] as int;
        fleet.inject(robot, RobotFault.skipHeaderIds);
        expect(lastState(serial)['headerId'], before + 1 + SimulatedFleet.skippedHeaderIds);

        fleet.inject(robot, RobotFault.wrongSerialNumber);
        expect(lastState(serial)['serialNumber'], '$serial-X');
        fleet.inject(robot, RobotFault.wrongSerialNumber);
        expect(lastState(serial)['serialNumber'], serial);

        fleet.inject(robot, RobotFault.clockSkew);
        var skewed = publisher.of(VdaTopic.state, serial).last;
        var time = DateTime.parse(skewed.json['timestamp'] as String);
        var connection = DateTime.parse(publisher.of(VdaTopic.connection, serial).first.json['timestamp'] as String);
        expect(time.difference(connection), greaterThan(skewed.at + const Duration(seconds: 9)));
        fleet.inject(robot, RobotFault.clockSkew);

        fleet.inject(robot, RobotFault.responseWithoutRequest);
        var response = publisher.of(VdaTopic.responses, serial).last;
        expect(((response.json['responses'] as List).single as Map)['requestId'], contains('unknown'));

        fleet.inject(robot, RobotFault.brokenOrder);
        async.elapse(const Duration(minutes: 2));
        var broken = publisher.of(VdaTopic.order, serial).where((m) {
          var order = Vda5050Reader.read(VdaTopic.order, m.json) as VdaOrder;
          var ids = [...order.nodes.map((n) => n.sequenceId), ...order.edges.map((e) => e.sequenceId)]..sort();
          return ids.length > 1 && ids.last - ids.first != ids.length - 1;
        });
        expect(broken.length, 1);
        runner.dispose();
      });
    });

    test('low battery sends the robot to a charging station', () {
      fakeAsync((fake) {
        start(fake, source: Vda5050Source(maxIdleSec: 1, chargePerHour: 3600));
        var robot = fleet.robots.first;
        fleet.inject(robot, RobotFault.cancelOrder);
        fleet.inject(robot, RobotFault.lowBattery);
        async.elapse(const Duration(minutes: 3));
        var states = publisher.of(VdaTopic.state, robot.serialNumber);
        expect(states.any((m) => (m.json['powerSupply'] as Map)['charging'] == true), isTrue);
        var chargers = fleet.layout.nodes.values.where((node) => node.charging).map((node) => node.id);
        expect(states.any((m) => chargers.contains(m.json['lastNodeId'])), isTrue);
        runner.dispose();
      });
    });

    test('zone requests are answered and robots enter the release zone only when granted', () {
      fakeAsync((fake) {
        var source = Vda5050Source(columns: 4, rows: 3, maxIdleSec: 1, minOrderNodes: 2, maxOrderNodes: 6);
        start(fake, source: source);
        async.elapse(const Duration(minutes: 20));
        var zone = fleet.layout.zonesOfType(VdaZoneType.release).single;
        var requested = <String>{};
        var entered = 0;
        for (var message in publisher.of(VdaTopic.state)) {
          var state = Vda5050Reader.read(VdaTopic.state, message.json) as VdaState;
          requested.addAll(state.zoneRequests.map((request) => request.requestId));
          var position = state.position!;
          if (zone.contains(position.x, position.y) && !state.driving) {
            entered++;
            expect(state.zoneRequests.any((r) => r.zoneId == zone.zoneId && r.requestStatus == 'GRANTED'), isTrue,
                reason: 'in the zone without a grant: ${message.json}');
          }
        }
        expect(requested, isNotEmpty);
        expect(entered, greaterThan(0));
        var granted = publisher
            .of(VdaTopic.responses)
            .expand((m) => (m.json['responses'] as List).cast<Map>())
            .where((r) => r['grantType'] == 'GRANTED')
            .map((r) => r['requestId']);
        expect(granted.toSet().intersection(requested), isNotEmpty);
        runner.dispose();
      });
    });
  });

  group('rules', () {
    test('a VDA 5050 device needs {n}, valid names and room on the layout', () {
      var device = _device(VdaVersion.v3, robots: 2)..vda5050!.serialNumber = 'R1';
      expect(SimulationRules.validateVda5050(device).map((i) => i.kind), [SimulationIssueKind.vdaSerialNeedsInstance]);
      device.vda5050!
        ..serialNumber = 'R{n}'
        ..manufacturer = 'a/b';
      expect(SimulationRules.validateVda5050(device).map((i) => i.kind), [SimulationIssueKind.vdaNameInvalid]);
      device.vda5050!
        ..manufacturer = 'Acme'
        ..columns = 2
        ..rows = 1;
      expect(SimulationRules.validateVda5050(device).map((i) => i.kind), [SimulationIssueKind.vdaLayoutTooSmall]);
      device.instanceCount = 201;
      device.vda5050!
        ..columns = 50
        ..rows = 50;
      expect(SimulationRules.validateVda5050(device).map((i) => i.kind), [SimulationIssueKind.vdaTooManyRobots]);
    });

    test('the zones keep the grid connected and the blocked node out', () {
      var layout = FleetLayout.grid(Vda5050Source());
      expect(layout.nodes.containsKey('N3-2'), isFalse);
      for (var node in layout.nodes.keys) {
        expect(layout.route('N1-1', node), isNotNull);
      }
      expect(FleetLayout.grid(Vda5050Source(version: VdaVersion.v2)).zoneSet, isNull);
    });

    test('the rate counts visualization and events per robot', () {
      expect(SimulatedFleet.rateOf(_device(VdaVersion.v3, robots: 4)), 4 * (2 + SimulatedFleet.eventRate));
    });

    test('a VDA 5050 device survives a JSON round trip', () {
      var device = _device(VdaVersion.v2, robots: 7);
      var copy = SimulatedDevice.fromJson(jsonDecode(jsonEncode(device.toJson())) as Map<String, dynamic>);
      expect(copy.kind, DeviceKind.vda5050);
      expect(copy.instanceCount, 7);
      expect(copy.vda5050!.version, VdaVersion.v2);
      expect(copy.vda5050!.toJson(), device.vda5050!.toJson());
    });
  });
}
