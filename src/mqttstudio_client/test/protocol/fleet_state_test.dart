import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:mqttstudio/simulator/engine/simulator_runner.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/model/vda5050_source.dart';
import 'package:typed_data/typed_buffers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/protocol/vda5050/fleet_state.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_profile.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_writer.dart';

// folds every message a simulated fleet publishes, as the topic viewer would receive it
class _FleetPublisher implements SimulatorPublisher {
  final FleetState<String> fleet;
  final profile = Vda5050Profile();
  @override
  bool isConnected = true;
  @override
  bool supportsProperties = true;
  DateTime now = DateTime(2026, 10, 26, 12);

  _FleetPublisher(this.fleet);

  @override
  void publish(String topic, Uint8Buffer payload, MqttQos qos, bool retain, MqttMessageProperties? properties) {
    var match = profile.matchTopic(topic);
    if (match != null) {
      fleet.add(match, jsonDecode(utf8.decode(payload)), now, topic);
    }
  }
}

void main() {
  var profile = Vda5050Profile();
  var start = DateTime(2026, 10, 26, 12);
  late FleetState<String> fleet;

  VdaHeader header(String serial, VdaVersion version, [int id = 1]) => VdaHeader(
    headerId: id,
    timestamp: start,
    version: version.protocolVersion,
    manufacturer: 'Acme',
    serialNumber: serial,
  );

  String topicOf(String serial, VdaVersion version, String type) => 'uagv/${version.topicLevel}/Acme/$serial/$type';

  bool add(String serial, VdaVersion version, VdaMessage message, {int second = 0}) {
    var topic = topicOf(serial, version, message.topic);
    return fleet.add(
      profile.matchTopic(topic)!,
      Vda5050Writer(version).toJson(message),
      start.add(Duration(seconds: second)),
      topic,
    );
  }

  VdaState state(
    String serial,
    VdaVersion version, {
    double x = 0,
    String mapId = 'hall',
    bool driving = false,
    List<VdaError>? errors,
    int id = 1,
  }) => VdaState(
    header: header(serial, version, id),
    driving: driving,
    position: VdaPosition(x: x, y: 0, theta: 0, mapId: mapId),
    powerSupply: VdaPowerSupply(stateOfCharge: 50),
    errors: errors,
  );

  setUp(() => fleet = FleetState<String>());

  test('robots of both versions are one fleet', () {
    expect(add('R1', VdaVersion.v2, state('R1', VdaVersion.v2)), isTrue);
    expect(add('R2', VdaVersion.v3, state('R2', VdaVersion.v3, x: 4)), isTrue);
    expect(fleet.vehicles.map((vehicle) => vehicle.name), ['Acme R1', 'Acme R2']);
    var r1 = fleet.vehicle('uagv/v2/Acme/R1')!;
    expect(r1.version, '2.1.0');
    expect(r1.stateMessage, 'uagv/v2/Acme/R1/state');
    expect(fleet.vehicle('uagv/v3/Acme/R2')!.position!.x, 4);
  });

  test('the status follows connection, errors and driving', () {
    add('R1', VdaVersion.v3, state('R1', VdaVersion.v3));
    var r1 = fleet.vehicle('uagv/v3/Acme/R1')!;
    expect(r1.status, VehicleStatus.idle);
    add('R1', VdaVersion.v3, state('R1', VdaVersion.v3, driving: true));
    expect(r1.status, VehicleStatus.driving);
    add(
      'R1',
      VdaVersion.v3,
      state(
        'R1',
        VdaVersion.v3,
        errors: [VdaError(errorType: 'battery', errorLevel: VdaErrorLevel.warning)],
      ),
    );
    expect(r1.status, VehicleStatus.warning);
    add(
      'R1',
      VdaVersion.v3,
      state(
        'R1',
        VdaVersion.v3,
        errors: [
          VdaError(errorType: 'battery', errorLevel: VdaErrorLevel.warning),
          VdaError(errorType: 'drive', errorLevel: VdaErrorLevel.critical),
        ],
      ),
    );
    expect(r1.highestErrorLevel, VdaErrorLevel.critical);
    expect(r1.status, VehicleStatus.error);
    add(
      'R1',
      VdaVersion.v3,
      VdaConnection(header: header('R1', VdaVersion.v3), connectionState: VdaConnectionState.connectionBroken),
    );
    expect(r1.status, VehicleStatus.connectionBroken);
    expect(r1.connectionMessage, 'uagv/v3/Acme/R1/connection');
  });

  test('2.x CONNECTIONBROKEN is read as the 3.0 term', () {
    add(
      'R1',
      VdaVersion.v2,
      VdaConnection(header: header('R1', VdaVersion.v2), connectionState: VdaConnectionState.connectionBroken),
    );
    expect(fleet.vehicle('uagv/v2/Acme/R1')!.status, VehicleStatus.connectionBroken);
  });

  test('the newer of state and visualization gives the position, the trail keeps the last 200', () {
    add('R1', VdaVersion.v3, state('R1', VdaVersion.v3, x: 1), second: 0);
    add(
      'R1',
      VdaVersion.v3,
      VdaVisualization(
        header: header('R1', VdaVersion.v3),
        position: VdaPosition(x: 2, y: 0, theta: 0, mapId: 'hall'),
      ),
      second: 1,
    );
    var r1 = fleet.vehicle('uagv/v3/Acme/R1')!;
    expect(r1.position!.x, 2);
    add('R1', VdaVersion.v3, state('R1', VdaVersion.v3, x: 3), second: 2);
    expect(r1.position!.x, 3);
    for (var i = 0; i < 300; i++) {
      add('R1', VdaVersion.v3, state('R1', VdaVersion.v3, x: 10.0 + i), second: 3 + i);
    }
    expect(r1.trail.length, VehicleState.maxTrail);
    expect(r1.trail.last.x, 309);
  });

  test('an order alone makes no robot, zone sets are kept per map', () {
    var order = VdaOrder(
      header: header('R9', VdaVersion.v3),
      orderId: 'o1',
      nodes: [
        VdaNode(
          nodeId: 'N1',
          sequenceId: 0,
          released: true,
          position: VdaNodePosition(x: 20, y: 20, mapId: 'yard'),
        ),
      ],
    );
    expect(add('R9', VdaVersion.v3, order), isFalse);
    expect(fleet.isEmpty, isTrue);

    add('R1', VdaVersion.v3, state('R1', VdaVersion.v3));
    add('R1', VdaVersion.v3, VdaOrder(header: header('R1', VdaVersion.v3), orderId: 'o1', nodes: order.nodes));
    add(
      'R1',
      VdaVersion.v3,
      VdaZoneSetMessage(
        header: header('R1', VdaVersion.v3),
        zoneSet: VdaZoneSet(
          zoneSetId: 'z1',
          mapId: 'dock',
          zones: [
            VdaZone(
              zoneId: 'blocked',
              zoneType: VdaZoneType.blocked,
              vertices: [VdaPoint(-10, -10), VdaPoint(-8, -10), VdaPoint(-8, -8)],
            ),
          ],
        ),
      ),
    );
    expect(fleet.vehicle('uagv/v3/Acme/R1')!.order!.orderId, 'o1');
    expect(fleet.zoneSetsOf('dock').single.zones.single.zoneId, 'blocked');
    // the map with the robot first, then the others by name
    expect(fleet.maps, ['hall', 'dock', 'yard']);
    var bounds = fleet.boundsOf('hall')!;
    expect([bounds.left, bounds.width], [0, 0]);
    expect(fleet.boundsOf('yard')!.left, 20);
    expect(fleet.boundsOf('nowhere'), isNull);
  });

  test('messages that are not VDA 5050 or can not be read are skipped', () {
    var topic = 'uagv/v3/Acme/R1/state';
    expect(fleet.add(profile.matchTopic(topic)!, {'temp': 21}, start, topic), isFalse);
    expect(fleet.add(profile.matchTopic(topic)!, 'text', start, topic), isFalse);
    var factsheet = 'uagv/v3/Acme/R1/factsheet';
    expect(
      fleet.add(
        profile.matchTopic(factsheet)!,
        {'headerId': 1, 'manufacturer': 'Acme', 'serialNumber': 'R1'},
        start,
        factsheet,
      ),
      isFalse,
    );
    expect(fleet.isEmpty, isTrue);
  });

  test('requests that wait and a stale state', () {
    var robot = state('R1', VdaVersion.v3)
      ..zoneRequests = [
        VdaZoneRequest(requestId: 'q1', zoneId: 'z', zoneSetId: 's'),
        VdaZoneRequest(requestId: 'q2', zoneId: 'z', zoneSetId: 's', requestStatus: VdaRequestStatus.granted),
      ];
    add('R1', VdaVersion.v3, robot);
    var r1 = fleet.vehicle('uagv/v3/Acme/R1')!;
    expect(r1.openRequests, 1);
    expect(r1.isStale(start.add(Duration(seconds: 30))), isFalse);
    expect(r1.isStale(start.add(Duration(seconds: 36))), isTrue);
  });

  test('a simulated fleet of both versions shows every robot with position, order and zones', () {
    fakeAsync((async) {
      var publisher = _FleetPublisher(fleet);
      var runner = SimulatorRunner(publisher, seed: 1);
      for (var version in VdaVersion.values) {
        runner.startDevice(
          SimulatedDevice(
            name: 'fleet ${version.name}',
            kind: DeviceKind.vda5050,
            instanceCount: 3,
            vda5050: Vda5050Source(
              version: version,
              interfaceName: 'uagv',
              columns: 4,
              rows: 3,
              maxIdleSec: 1,
              seed: 5,
            ),
          ),
        );
      }
      async.elapse(const Duration(seconds: 30));
      runner.stopAll();
      runner.dispose();
    });
    expect(fleet.vehicles.length, 6);
    expect(fleet.vehicles.map((vehicle) => vehicle.version).toSet(), {'2.1.0', '3.0.0'});
    for (var vehicle in fleet.vehicles) {
      expect(vehicle.position, isNotNull, reason: vehicle.name);
      expect(vehicle.order, isNotNull, reason: vehicle.name);
      expect(vehicle.trail, isNotEmpty, reason: vehicle.name);
    }
    var mapId = fleet.maps.first;
    expect(fleet.zoneSetsOf(mapId), isNotEmpty);
    expect(
      fleet.vehicles.where((vehicle) => vehicle.version == '3.0.0').every((vehicle) => vehicle.plannedPath != null),
      isTrue,
    );
    // stopping publishes OFFLINE
    expect(fleet.vehicles.every((vehicle) => vehicle.status == VehicleStatus.offline), isTrue);
  });
}
