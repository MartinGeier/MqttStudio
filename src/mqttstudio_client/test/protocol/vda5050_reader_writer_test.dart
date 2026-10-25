import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_reader.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_writer.dart';

import 'vda5050_shapes.dart';

final _time = DateTime.utc(2026, 10, 25, 9, 30, 15, 123);

VdaHeader _header(VdaVersion version) =>
    VdaHeader(headerId: 7, timestamp: _time, version: version.protocolVersion, manufacturer: 'Acme', serialNumber: 'R1');

VdaState _state(VdaVersion version) => VdaState(
      header: _header(version),
      maps: [VdaMapInfo(mapId: 'hall', mapVersion: '1')],
      zoneSets: [VdaZoneSetInfo(zoneSetId: 'zs', mapId: 'hall')],
      orderId: 'o1',
      orderUpdateId: 2,
      lastNodeId: 'n1',
      lastNodeSequenceId: 2,
      nodeStates: [VdaNodeState(nodeId: 'n2', sequenceId: 4, released: true)],
      edgeStates: [VdaEdgeState(edgeId: 'e1', sequenceId: 3, released: true)],
      position: VdaPosition(x: 1.5, y: 2, theta: 0.5, mapId: 'hall', localized: true, localizationScore: 0.9),
      velocity: VdaVelocity(vx: 1, vy: 0, omega: 0),
      driving: true,
      paused: false,
      actionStates: [VdaActionState(actionId: 'a1', actionType: 'pick', status: VdaActionStatus.retriable, result: 'r')],
      instantActionStates: [VdaActionState(actionId: 'i1', actionType: 'startPause', status: VdaActionStatus.finished)],
      powerSupply: VdaPowerSupply(stateOfCharge: 77, charging: false, batteryVoltage: 26, batteryCurrent: -3, range: 500),
      operatingMode: VdaOperatingMode.teachIn,
      errors: [
        VdaError(errorType: 'e1', errorLevel: VdaErrorLevel.urgent, description: 'd'),
        VdaError(errorType: 'e2', errorLevel: VdaErrorLevel.critical),
      ],
      safetyState: VdaSafetyState(activeEmergencyStop: VdaEmergencyStop.remote, fieldViolation: true),
      zoneRequests: [VdaZoneRequest(requestId: 'r1', zoneId: 'z', zoneSetId: 'zs')],
      plannedPath: VdaPlannedPath(controlPoints: [VdaPoint(0, 0), VdaPoint(5, 0)]),
    );

VdaOrder _order(VdaVersion version) => VdaOrder(
      header: _header(version),
      orderId: 'o1',
      orderUpdateId: 0,
      nodes: [
        VdaNode(nodeId: 'n0', sequenceId: 0, released: true, position: VdaNodePosition(x: 0, y: 0, mapId: 'hall')),
        VdaNode(nodeId: 'n1', sequenceId: 2, released: true, position: VdaNodePosition(x: 5, y: 0, mapId: 'hall'), actions: [
          VdaAction(
              actionId: 'a1',
              actionType: 'pick',
              blockingType: VdaBlockingType.single,
              descriptor: 'take it',
              parameters: [VdaActionParameter('loadType', 'EPAL')])
        ]),
      ],
      edges: [VdaEdge(edgeId: 'e0', sequenceId: 1, released: true, maximumSpeed: 1.2)],
    );

void main() {
  group('writer', () {
    test('every message of both versions has the shape of its schema', () {
      for (var version in VdaVersion.values) {
        var writer = Vda5050Writer(version);
        var messages = <VdaMessage>[
          _state(version),
          _order(version),
          VdaInstantActions(header: _header(version), actions: [VdaAction(actionId: 'i1', actionType: 'startPause')]),
          VdaVisualization(header: _header(version), referenceStateHeaderId: 6, position: _state(version).position),
          VdaConnection(header: _header(version), connectionState: VdaConnectionState.hibernating),
          VdaFactsheet(
              header: _header(version),
              seriesName: 's',
              navigationTypes: ['FREELY_NAVIGATING'],
              actions: [VdaFactsheetAction('pick', ['NODE', 'ZONE'])]),
          if (version.isV3) ...[
            VdaZoneSetMessage(
                header: _header(version),
                zoneSet: VdaZoneSet(zoneSetId: 'zs', mapId: 'hall', zones: [
                  VdaZone(
                      zoneId: 'z',
                      zoneType: VdaZoneType.speedLimit,
                      vertices: [VdaPoint(0, 0), VdaPoint(1, 0), VdaPoint(1, 1)],
                      parameters: {'maximumSpeed': 0.5})
                ])),
            VdaResponses(header: _header(version), responses: [VdaResponse(requestId: 'r1', grantType: VdaGrantType.queued)]),
          ],
        ];
        for (var message in messages) {
          expect(shapeErrors(message.topic, version, writer.toJson(message)), isEmpty,
              reason: '${version.name} ${message.topic}');
        }
      }
    });

    test('writes the 2.x names and the closest 2.x values', () {
      var writer = const Vda5050Writer(VdaVersion.v2);
      var state = writer.toJson(_state(VdaVersion.v2));
      expect(state['agvPosition'], containsPair('positionInitialized', true));
      expect(state['batteryState'], {'batteryCharge': 77.0, 'batteryVoltage': 26.0, 'charging': false, 'reach': 500.0});
      expect(state['safetyState'], {'eStop': 'REMOTE', 'fieldViolation': true});
      expect(state['operatingMode'], 'TEACHIN');
      expect((state['errors'] as List).map((error) => error['errorLevel']), ['WARNING', 'FATAL']);
      // 2.x keeps the instant actions in actionStates
      expect((state['actionStates'] as List).map((action) => action['actionId']), ['a1', 'i1']);
      expect((state['actionStates'] as List).first, containsPair('actionStatus', 'FAILED'));
      expect((state['actionStates'] as List).first, containsPair('resultDescription', 'r'));
      expect(state.containsKey('zoneRequests'), isFalse);

      var order = writer.toJson(_order(VdaVersion.v2));
      var edge = (order['edges'] as List).single as Map;
      expect(edge, containsPair('startNodeId', 'n0'));
      expect(edge, containsPair('endNodeId', 'n1'));
      expect(edge, containsPair('maxSpeed', 1.2));
      var action = ((order['nodes'] as List)[1]['actions'] as List).single as Map;
      expect(action, containsPair('blockingType', 'SOFT'));
      expect(action, containsPair('actionDescription', 'take it'));

      expect(
          writer.toJson(VdaConnection(connectionState: VdaConnectionState.connectionBroken))['connectionState'],
          'CONNECTIONBROKEN');
    });

    test('writes the 3.0 names', () {
      var writer = const Vda5050Writer(VdaVersion.v3);
      var state = writer.toJson(_state(VdaVersion.v3));
      expect(state['mobileRobotPosition'], containsPair('localized', true));
      expect(state['powerSupply'], containsPair('stateOfCharge', 77.0));
      expect(state['powerSupply'], containsPair('batteryCurrent', -3.0));
      expect(state['safetyState'], containsPair('activeEmergencyStop', 'REMOTE'));
      expect(state['operatingMode'], 'TEACH_IN');
      expect((state['instantActionStates'] as List).single, containsPair('actionId', 'i1'));
      expect((state['actionStates'] as List).single, containsPair('actionResult', 'r'));
      expect((state['zoneRequests'] as List).single, containsPair('requestStatus', 'REQUESTED'));
      var edge = (writer.toJson(_order(VdaVersion.v3))['edges'] as List).single as Map;
      expect(edge.containsKey('startNodeId'), isFalse);
      expect(edge, containsPair('maximumSpeed', 1.2));
    });

    test('timestamps have milliseconds in 3.0 and hundredths in 2.x', () {
      expect(const Vda5050Writer(VdaVersion.v3).timestamp(_time), '2026-10-25T09:30:15.123Z');
      expect(const Vda5050Writer(VdaVersion.v2).timestamp(_time), '2026-10-25T09:30:15.12Z');
    });
  });

  group('reader', () {
    test('a written message reads back as the same model in both versions', () {
      for (var version in VdaVersion.values) {
        var json = Vda5050Writer(version).toJson(_state(version));
        var state = Vda5050Reader.read(VdaTopic.state, json) as VdaState;
        expect(state.header.headerId, 7);
        expect(state.header.timestamp, version.isV3 ? _time : DateTime.utc(2026, 10, 25, 9, 30, 15, 120));
        expect(state.position!.x, 1.5);
        expect(state.position!.localized, isTrue);
        expect(state.powerSupply.stateOfCharge, 77);
        expect(state.powerSupply.range, 500);
        expect(state.safetyState.activeEmergencyStop, 'REMOTE');
        expect(state.operatingMode, VdaOperatingMode.teachIn);
        expect(state.nodeStates.single.nodeId, 'n2');
        expect(state.extra, isEmpty);
        if (version.isV3) {
          expect(state.instantActionStates.single.actionId, 'i1');
          expect(state.zoneRequests.single.requestId, 'r1');
          expect(state.plannedPath!.controlPoints.length, 2);
        }
      }
      var order = Vda5050Reader.read(VdaTopic.order, const Vda5050Writer(VdaVersion.v2).toJson(_order(VdaVersion.v2)))
          as VdaOrder;
      expect(order.edges.single.startNodeId, 'n0');
      expect(order.edges.single.maximumSpeed, 1.2);
      expect(order.nodes[1].actions.single.descriptor, 'take it');
      expect(order.nodes[1].actions.single.parameters.single.value, 'EPAL');
    });

    test('reads 2.x enum values in their 3.0 spelling and 1.1 instant actions', () {
      var connection =
          Vda5050Reader.read(VdaTopic.connection, {'version': '2.0.0', 'connectionState': 'CONNECTIONBROKEN'}) as VdaConnection;
      expect(connection.connectionState, VdaConnectionState.connectionBroken);
      var instant = Vda5050Reader.read(VdaTopic.instantActions, {
        'version': '1.1.0',
        'instantActions': [
          {'actionId': 'x', 'actionType': 'startPause', 'blockingType': 'HARD'}
        ],
      }) as VdaInstantActions;
      expect(instant.actions.single.actionType, 'startPause');
      var factsheet = Vda5050Reader.read(VdaTopic.factsheet, {
        'typeSpecification': {'agvKinematic': 'OMNI', 'navigationTypes': ['AUTONOMOUS']},
        'agvGeometry': {'wheelDefinitions': []},
      }) as VdaFactsheet;
      expect(factsheet.kinematics, 'OMNIDIRECTIONAL');
      expect(factsheet.navigationTypes, ['FREELY_NAVIGATING']);
      expect(factsheet.extra.keys, contains('mobileRobotGeometry'));
    });

    test('keeps unknown fields and writes them back', () {
      var json = {...Vda5050Writer(VdaVersion.v3).toJson(_state(VdaVersion.v3)), 'vendorTemperature': 41};
      var state = Vda5050Reader.read(VdaTopic.state, json)!;
      expect(state.extra, {'vendorTemperature': 41});
      expect(const Vda5050Writer(VdaVersion.v3).toJson(state), containsPair('vendorTemperature', 41));
    });

    test('reads broken payloads without throwing', () {
      var state = Vda5050Reader.read(VdaTopic.state, {
        'headerId': 'x',
        'timestamp': 'yesterday',
        'driving': 'yes',
        'nodeStates': 'none',
        'errors': [42, {'errorType': 'e'}],
        'batteryState': {'batteryCharge': '55.5'},
      }) as VdaState;
      expect(state.header.headerId, 0);
      expect(state.driving, isFalse);
      expect(state.nodeStates, isEmpty);
      expect(state.errors.single.errorType, 'e');
      expect(state.powerSupply.stateOfCharge, 55.5);
      expect(Vda5050Reader.read('unknown', {}), isNull);
    });

    test('the version comes from the header, else the topic', () {
      expect(Vda5050Reader.versionOf({'version': '2.0.0'}), VdaVersion.v2);
      expect(Vda5050Reader.versionOf({'version': '3.1.0'}), VdaVersion.v3);
      expect(Vda5050Reader.versionOf({}, topicVersion: VdaVersion.v2), VdaVersion.v2);
      expect(Vda5050Reader.versionOf({'version': 'x'}), VdaVersion.v3);
    });
  });
}
