import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/protocol/protocol_profile.dart';
import 'package:mqttstudio/protocol/protocol_registry.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_profile.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_rules.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_writer.dart';

final _profile = Vda5050Profile();
final _start = DateTime.utc(2026, 10, 26, 8);

VdaHeader _header(int id, {DateTime? at, String serial = 'R1', String version = '3.0.0'}) =>
    VdaHeader(headerId: id, timestamp: at ?? _start, version: version, manufacturer: 'Acme', serialNumber: serial);

Map<String, Object?> _json(VdaMessage message, [VdaVersion version = VdaVersion.v3]) => Vda5050Writer(version).toJson(message);

ProtocolTopic _topic(String type, {String prefix = 'vda5050/v3/Acme/R1'}) => _profile.matchTopic('$prefix/$type')!;

VdaOrder _order(String id, int update, List<(String, bool)> nodes, {int firstSequence = 0, int header = 0}) {
  return VdaOrder(header: _header(header), orderId: id, orderUpdateId: update, nodes: [
    for (var i = 0; i < nodes.length; i++)
      VdaNode(nodeId: nodes[i].$1, sequenceId: firstSequence + 2 * i, released: nodes[i].$2)
  ], edges: [
    for (var i = 0; i < nodes.length - 1; i++)
      VdaEdge(edgeId: 'e$i', sequenceId: firstSequence + 2 * i + 1, released: nodes[i + 1].$2)
  ]);
}

class _Context implements InterpretationContext {
  final Map<String, Object?> data;

  _Context(this.data);

  @override
  Object? lastData(String deviceKey, String messageType) => data[messageType];
}

void main() {
  group('detection', () {
    test('recognizes the last five levels of VDA 5050 topics', () {
      var topic = _profile.matchTopic('plant/uagv/v2/KUKA/0001/state')!;
      expect(topic.messageType, 'state');
      expect(topic.deviceKey, 'plant/uagv/v2/KUKA/0001');
      expect(topic.parameters, {'interfaceName': 'uagv', 'majorVersion': 'v2', 'manufacturer': 'KUKA', 'serialNumber': '0001'});
      expect(_profile.matchTopic('uagv/v2/KUKA/0001/temperature'), isNull);
      expect(_profile.matchTopic('uagv/2/KUKA/0001/state'), isNull);
      expect(_profile.matchTopic('v2/KUKA/0001/state'), isNull);
      expect(ProtocolRegistry.standard().match('vda5050/v3/A/B/zoneSet')!.profile, isA<Vda5050Profile>());
    });

    test('a payload without header is not interpreted', () {
      expect(_profile.interpret(_topic('state'), {'driving': true}), isNull);
      expect(_profile.interpret(_topic('state'), 'text'), isNull);
    });
  });

  group('interpretation', () {
    test('state: summary, level, sections and chart values', () {
      var state = VdaState(
        header: _header(4),
        orderId: 'o7',
        orderUpdateId: 2,
        lastNodeId: 'N1',
        lastNodeSequenceId: 2,
        nodeStates: [VdaNodeState(nodeId: 'N2', sequenceId: 4, released: true)],
        driving: true,
        paused: false,
        powerSupply: VdaPowerSupply(stateOfCharge: 77.4, charging: true, batteryVoltage: 26.5),
        operatingMode: VdaOperatingMode.automatic,
        position: VdaPosition(x: 1, y: 2, theta: 0, mapId: 'hall'),
        velocity: VdaVelocity(vx: 1.2),
        errors: [VdaError(errorType: 'e', errorLevel: VdaErrorLevel.urgent)],
        zoneRequests: [VdaZoneRequest(requestId: 'r1', zoneId: 'z', zoneSetId: 'zs')],
      );
      var responses = _json(VdaResponses(header: _header(1), responses: [VdaResponse(requestId: 'r1', grantType: 'QUEUED')]));
      var result = _profile.interpret(_topic('state'), _json(state), context: _Context({'responses': responses}))!;
      expect(result.summary,
          'R1 | AUTOMATIC | DRIVING | 77 % charging | order o7#2 at N1, 1 node to go | 1 error | 1 open request');
      expect(result.level, InterpretationLevel.warning);
      expect(result.protocolVersion, '3.0.0');
      expect(result.sections.map((section) => section.key),
          containsAllInOrder(['header', 'errors', 'status', 'position', 'order', 'requests']));
      var requests = result.sections.whereType<TableSection>().firstWhere((section) => section.key == 'requests');
      expect(requests.rows.single.cells.last, 'QUEUED');
      expect(result.values['State of charge %'], 77.4);
      expect(result.values['Velocity m/s'], 1.2);
    });

    test('a fatal error makes the state an error; 2.x reads like 3.0', () {
      var state = VdaState(
          header: _header(1, version: '2.1.0'), errors: [VdaError(errorType: 'e', errorLevel: VdaErrorLevel.fatal)]);
      var result = _profile.interpret(_topic('state', prefix: 'uagv/v2/Acme/R1'), _json(state, VdaVersion.v2))!;
      expect(result.level, InterpretationLevel.error);
      expect(result.protocolVersion, '2.1.0');
    });

    test('order, instant actions, connection, responses and zone set summaries', () {
      var order = _order('o1', 0, [('A', true), ('B', true), ('C', false)])
        ..nodes[1].actions.add(VdaAction(actionId: 'a1', actionType: 'pick'));
      var orderResult = _profile.interpret(_topic('order'), _json(order))!;
      expect(orderResult.summary, 'order o1#0 | 3 nodes (2 base, 1 horizon) | 1 action');
      var route = orderResult.sections.whereType<TableSection>().firstWhere((section) => section.key == 'route');
      expect(route.rows.map((row) => row.muted), [false, false, false, true, true]);

      var instant = VdaInstantActions(header: _header(1), actions: [
        VdaAction(actionId: 'i1', actionType: 'startPause'),
        VdaAction(actionId: 'i2', actionType: 'cancelOrder'),
      ]);
      expect(_profile.interpret(_topic('instantActions'), _json(instant))!.summary, 'startPause, cancelOrder');

      var broken = VdaConnection(header: _header(1), connectionState: VdaConnectionState.connectionBroken);
      var connection = _profile.interpret(_topic('connection'), _json(broken))!;
      expect(connection.summary, 'CONNECTION_BROKEN');
      expect(connection.level, InterpretationLevel.error);

      var responses = VdaResponses(header: _header(1), responses: [VdaResponse(requestId: 'r1', grantType: 'REJECTED')]);
      var responsesResult = _profile.interpret(_topic('responses'), _json(responses))!;
      expect(responsesResult.summary, 'r1 REJECTED');
      expect(responsesResult.level, InterpretationLevel.warning);

      var zoneSet = VdaZoneSetMessage(
          header: _header(1),
          zoneSet: VdaZoneSet(zoneSetId: 'zs', mapId: 'hall', zones: [
            VdaZone(zoneId: 'z', zoneType: 'BLOCKED', vertices: [VdaPoint(0, 0), VdaPoint(1, 0), VdaPoint(1, 1)])
          ]));
      expect(_profile.interpret(_topic('zoneSet'), _json(zoneSet))!.summary, 'zone set zs | hall | 1 zones');
    });

    test('unknown fields are shown as other fields', () {
      var json = {..._json(VdaConnection(header: _header(1))), 'vendor': 1};
      var result = _profile.interpret(_topic('connection'), json)!;
      expect((result.sections.last as RawSection).json, {'vendor': 1});
    });
  });

  group('rules', () {
    late Vda5050Checker checker;

    setUp(() => checker = Vda5050Checker(_profile));

    List<String> check(String type, VdaMessage message,
            {DateTime? at, String prefix = 'vda5050/v3/Acme/R1', VdaVersion version = VdaVersion.v3, bool snapshot = false}) =>
        checker
            .check('$prefix/$type', _topic(type, prefix: prefix), _json(message, version), at ?? _start,
                snapshot: snapshot)
            .map((finding) => finding.rule)
            .toList();

    test('header against the topic, header ids and timestamps', () {
      expect(check('connection', VdaConnection(header: _header(0))), isEmpty);
      expect(check('connection', VdaConnection(header: _header(1))), isEmpty);
      expect(check('connection', VdaConnection(header: _header(1))), [Vda5050Rule.headerIdOutOfOrder]);
      expect(check('connection', VdaConnection(header: _header(5))), [Vda5050Rule.headerIdGap]);
      expect(check('connection', VdaConnection(header: _header(6, serial: 'R2'))), [Vda5050Rule.headerDiffers]);
      expect(check('connection', VdaConnection(header: _header(7, version: '2.1.0'))), [Vda5050Rule.headerDiffers]);
      expect(check('connection', VdaConnection(header: _header(8)), at: _start.add(Duration(seconds: 6))),
          [Vda5050Rule.timestampSkew]);
      // a retained message sent on subscribing is old
      expect(
          check('connection', VdaConnection(header: _header(9)), at: _start.add(Duration(minutes: 5)), snapshot: true),
          isEmpty);
    });

    test('order structure', () {
      expect(check('order', _order('o1', 0, [('A', true), ('B', true), ('C', false)])), isEmpty);
      var released = _order('o2', 0, [('A', true), ('B', false), ('C', true)], header: 1);
      expect(check('order', released), [Vda5050Rule.orderStructure]);
      var gap = _order('o3', 0, [('A', true), ('B', true)], header: 2)..edges.single.sequenceId = 3;
      expect(check('order', gap), [Vda5050Rule.orderStructure]);
      var duplicate = _order('o4', 0, [('A', true), ('B', true)], header: 3);
      duplicate.nodes[0].actions.add(VdaAction(actionId: 'x', actionType: 'pick'));
      duplicate.nodes[1].actions.add(VdaAction(actionId: 'x', actionType: 'drop'));
      expect(check('order', duplicate), [Vda5050Rule.duplicateActionId]);
    });

    test('order updates continue at the end of the base', () {
      expect(check('order', _order('o1', 0, [('A', true), ('B', true), ('C', false)])), isEmpty);
      expect(check('order', _order('o1', 1, [('B', true), ('C', true)], firstSequence: 2, header: 1)), isEmpty);
      expect(check('order', _order('o1', 2, [('A', true), ('D', true)], header: 2)), [Vda5050Rule.orderUpdate]);
      expect(check('order', _order('o1', 1, [('B', true), ('C', true)], firstSequence: 2, header: 3)),
          [Vda5050Rule.orderUpdate]);
      // an order the robot is already driving began before the check; a new one must start at 0
      check('state', VdaState(header: _header(0), orderId: 'o8'));
      expect(check('order', _order('o8', 3, [('A', true)], header: 4)), isEmpty);
      expect(check('order', _order('o9', 3, [('A', true)], header: 5)), [Vda5050Rule.orderUpdateContent]);
    });

    test('3.0: repeated update ids keep their content, cancelled orders are not updated', () {
      expect(check('order', _order('o1', 0, [('A', true), ('B', true)])), isEmpty);
      expect(check('order', _order('o1', 0, [('A', true), ('B', true)], header: 1)), isEmpty);
      expect(check('order', _order('o1', 0, [('A', true), ('C', true)], header: 2)), [Vda5050Rule.orderUpdateContent]);
      check('instantActions',
          VdaInstantActions(header: _header(0), actions: [VdaAction(actionId: 'c', actionType: 'cancelOrder')]));
      expect(check('order', _order('o1', 1, [('B', true), ('C', true)], firstSequence: 2, header: 3)),
          [Vda5050Rule.orderUpdateContent]);
    });

    test('3.0: requests, responses, visualization and the heartbeat', () {
      var state = VdaState(header: _header(0), zoneRequests: [VdaZoneRequest(requestId: 'r1', zoneId: 'z', zoneSetId: 'zs')]);
      expect(check('state', state), isEmpty);
      expect(
          check('responses',
              VdaResponses(header: _header(0), responses: [VdaResponse(requestId: 'r2', grantType: VdaGrantType.granted)])),
          [Vda5050Rule.responseWithoutRequest]);
      expect(check('visualization', VdaVisualization(header: _header(0), referenceStateHeaderId: 1)),
          [Vda5050Rule.visualizationAheadOfState]);
      expect(checker.tick(_start.add(Duration(seconds: 5))), isEmpty);
      var late = checker.tick(_start.add(Duration(seconds: 11))).map((entry) => entry.$2.rule);
      expect(late, [Vda5050Rule.unansweredRequest]);
      var silent = checker.tick(_start.add(Duration(seconds: 36)));
      expect(silent.map((entry) => entry.$2.rule), [Vda5050Rule.heartbeatMissing]);
      expect(silent.single.$1, 'vda5050/v3/Acme/R1/state');
      // reported once per silence, and not while the robot is offline
      expect(checker.tick(_start.add(Duration(seconds: 50))), isEmpty);
      check('connection', VdaConnection(header: _header(0), connectionState: VdaConnectionState.offline),
          at: _start.add(Duration(seconds: 51)));
      check('state', VdaState(header: _header(1, at: _start.add(Duration(seconds: 52)))),
          at: _start.add(Duration(seconds: 52)));
      expect(checker.tick(_start.add(Duration(seconds: 100))), isEmpty);
    });

    test('2.x: edges must connect their neighbours', () {
      var order = _order('o1', 0, [('A', true), ('B', true)])
        ..header = _header(0, version: '2.1.0')
        ..edges.single.startNodeId = 'X';
      expect(check('order', order, prefix: 'uagv/v2/Acme/R1', version: VdaVersion.v2), [Vda5050Rule.orderStructure]);
    });
  });
}
