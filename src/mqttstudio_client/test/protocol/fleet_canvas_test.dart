import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/protocol/vda5050/fleet_state.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_profile.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_writer.dart';
import 'package:mqttstudio/protocol/widgets/fleet_canvas.dart';

final _profile = Vda5050Profile();
final _start = DateTime.utc(2026, 11, 3, 12);

VdaHeader _header(String serial) =>
    VdaHeader(headerId: 1, timestamp: _start, version: '3.0.0', manufacturer: 'Acme', serialNumber: serial);

void _add(FleetState<String> fleet, String serial, VdaMessage message) {
  var topic = 'uagv/v3/Acme/$serial/${message.topic}';
  fleet.add(_profile.matchTopic(topic)!, Vda5050Writer(VdaVersion.v3).toJson(message), _start, topic);
}

void _robot(FleetState<String> fleet, String serial, double x, double y) => _add(
  fleet,
  serial,
  VdaState(header: _header(serial), position: VdaPosition(x: x, y: y, theta: 0, mapId: 'hall')),
);

Future<void> _pump(WidgetTester tester, FleetState<String> fleet, {String? selected}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: CustomTheme.lightTheme,
      home: Scaffold(
        body: FleetCanvas<String>(
          fleet: fleet,
          mapId: 'hall',
          selectedRobot: selected,
          showZones: true,
          showLegend: false,
          onSelect: (_) {},
        ),
      ),
    ),
  );
}

// Coordinates far out of any hall used to make the grid loop forever, and floor() threw for infinity
void main() {
  testWidgets('robots at huge coordinates neither hang nor throw', (tester) async {
    var fleet = FleetState<String>();
    _robot(fleet, 'R1', 0, 0);
    _robot(fleet, 'R2', 1e300, -1e300);
    await _pump(tester, fleet);
    expect(tester.takeException(), isNull);

    // the bounds of these are infinitely wide
    _robot(fleet, 'R3', -1.7e308, 1.7e308);
    _robot(fleet, 'R4', 1.7e308, -1.7e308);
    await _pump(tester, fleet);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a horizon edge billions of pixels long is drawn solid', (tester) async {
    var fleet = FleetState<String>();
    _robot(fleet, 'R1', 0, 0);
    _add(
      fleet,
      'R1',
      VdaOrder(
        header: _header('R1'),
        orderId: 'o1',
        orderUpdateId: 0,
        nodes: [
          VdaNode(nodeId: 'A', sequenceId: 0, released: true, position: VdaNodePosition(x: 0, y: 0, mapId: 'hall')),
          VdaNode(nodeId: 'B', sequenceId: 2, released: false, position: VdaNodePosition(x: 1e12, y: 0, mapId: 'hall')),
        ],
        edges: [VdaEdge(edgeId: 'e', sequenceId: 1, released: false)],
      ),
    );
    await _pump(tester, fleet, selected: 'uagv/v3/Acme/R1');
    // the fitted view shows the whole edge; zoomed in as far as it goes it is 2e15 pixels long
    var pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(FleetCanvas<String>)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -10000)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
