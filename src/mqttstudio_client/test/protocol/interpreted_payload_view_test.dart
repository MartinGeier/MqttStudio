import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/protocol/protocol_profile.dart';
import 'package:mqttstudio/protocol/widgets/interpreted_payload_view.dart';

void main() {
  testWidgets('a table without columns shows its title, no DataTable', (tester) async {
    var interpretation = Interpretation(
      protocolVersion: 'B',
      summary: '',
      sections: [
        TableSection('empty', 'Empty table', const [], const [InterpretedRow(['x'])]),
        TableSection('full', 'Full table', const ['Name'], const [InterpretedRow(['x'])]),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: CustomTheme.lightTheme,
        home: Scaffold(
          body: InterpretedPayloadView(interpretation: interpretation, isCollapsed: (_) => false, onToggle: (_) {}),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Empty table'), findsOneWidget);
    expect(find.byType(DataTable), findsOneWidget);
  });
}
