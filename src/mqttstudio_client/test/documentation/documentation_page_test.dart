import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/documentation/documentation_page.dart';
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';

void main() {
  setUpAll(loadTranslations);

  setUp(() {
    setUpServices();
    GetIt.I.registerSingleton(SrxNavigationService(Container(), Container()));
  });

  tearDown(tearDownServices);

  Future<void> pumpPage(WidgetTester tester, {bool openProject = true}) async {
    await tester.binding.setSurfaceSize(Size(1600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    if (openProject) {
      await openNewProject();
    }
    await tester.pumpWidget(testApp(DocumentationPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('without a project ADD TOPIC is disabled', (tester) async {
    await pumpPage(tester, openProject: false);
    var button =
        tester.widget<TextButton>(find.ancestor(of: find.text('ADD TOPIC'), matching: find.byType(TextButton)));
    expect(button.onPressed, isNull);
  });

  testWidgets('adds a topic through the dialog and edits it', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpPage(tester);
      expect(find.text('Documentation'), findsWidgets);

      await tester.tap(find.text('ADD TOPIC'));
      await tester.pumpAndSettle();
      var dialog = find.byType(SimpleDialog);
      await tester.enterText(find.descendant(of: dialog, matching: find.byType(TextField)).first, 'plant/+/temp');
      await tester.tap(find.descendant(of: dialog, matching: find.text('ADD')));
      await tester.pumpAndSettle();
      expect(find.textContaining('must not contain + or #'), findsOneWidget);
      expect(dialog, findsOneWidget);

      await tester.enterText(find.descendant(of: dialog, matching: find.byType(TextField)).first, 'plant/{line}/temp');
      await tester.enterText(find.descendant(of: dialog, matching: find.byType(TextField)).at(1), 'Temperature');
      await tester.tap(find.descendant(of: dialog, matching: find.text('ADD')));
      await tester.pumpAndSettle();

      var node = GetIt.I.get<DocumentationService>().nodeAt('plant/{line}/temp')!;
      expect(node.title, 'Temperature');
      expect(node.isTopic, isTrue);
      expect(find.text('Parameters'), findsOneWidget);
      expect(find.text('line'), findsOneWidget);
      expect(GetIt.I.get<ProjectManager>().hasProjectChanged(), isTrue);

      var owner = find.ancestor(of: find.text('Owner'), matching: find.byType(TextField));
      await tester.enterText(owner, 'Automation team');
      await tester.pumpAndSettle();
      expect(node.owner, 'Automation team');
      expect(node.editedFields, contains('owner'));
    });
  });

  testWidgets('a JSON topic documents its fields through the schema table', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpPage(tester);
      var service = GetIt.I.get<DocumentationService>();
      var node = DocNode(path: 'plant/status', topic: TopicSpec(payload: PayloadSpec(format: PayloadFormat.json)));
      service.addNode(node);
      await tester.pumpAndSettle();
      await tester.tap(find.text('status'));
      await tester.pumpAndSettle();
      expect(find.text('No fields documented yet'), findsOneWidget);
      expect(find.text('Delivery'), findsOneWidget);
      expect(find.text('MQTT 5'), findsOneWidget);
      expect(find.text('Access and notes'), findsOneWidget);

      await tester.ensureVisible(find.text('FIELD'));
      await tester.tap(find.text('FIELD'));
      await tester.pumpAndSettle();
      var dialog = find.byType(SimpleDialog);
      await tester.enterText(find.descendant(of: dialog, matching: find.byType(TextField)).first, r'$.temp');
      await tester.tap(find.descendant(of: dialog, matching: find.text('Save')));
      await tester.pumpAndSettle();

      expect(dialog, findsNothing);
      expect(node.topic!.payload.schema!.properties.keys, ['temp']);
      expect(find.text(r'$.temp'), findsOneWidget);
    });
  });

  testWidgets('editor rows are as high as their fields, with a 16 px gap', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpPage(tester);
      GetIt.I.get<DocumentationService>().addNode(DocNode(path: 'plant/speed', topic: TopicSpec()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('speed'));
      await tester.pumpAndSettle();
      Rect outline(String label) =>
          tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(InputDecorator)).first);
      var row = [outline('Title'), outline('Status'), outline('Owner')].map((rect) => rect.bottom).reduce(max);
      expect(outline('Tags').top - row, 16);
    });
  });

  testWidgets('DELETE ALL TOPICS asks and clears the documentation', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpPage(tester);
      var button = find.ancestor(of: find.text('DELETE ALL TOPICS'), matching: find.byType(TextButton));
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      var service = GetIt.I.get<DocumentationService>();
      service.addNode(DocNode(path: 'plant/a', topic: TopicSpec()));
      service.addNode(DocNode(path: 'plant/b', topic: TopicSpec()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('DELETE ALL TOPICS'));
      await tester.pumpAndSettle();
      // SrxDialog shows its body as Markdown, in a RichText
      expect(
          find.byWidgetPredicate(
              (widget) => widget is RichText && widget.text.toPlainText().contains('Delete all 2 documented topics')),
          findsOneWidget);
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(service.nodes, hasLength(2));

      await tester.tap(find.text('DELETE ALL TOPICS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(service.nodes, isEmpty);
      expect(find.text('a'), findsNothing);
    });
  });

  testWidgets('selecting a namespace shows the topics below it', (tester) async {
    await ignoringOverflowErrors(() async {
      await pumpPage(tester);
      var service = GetIt.I.get<DocumentationService>();
      service.addNode(DocNode(path: 'plant/line1/temp', title: 'Line 1 temperature', topic: TopicSpec()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('line1'));
      await tester.pumpAndSettle();
      expect(find.text('Line 1 temperature'), findsOneWidget);
      expect(find.text('temp'), findsWidgets);
      expect(service.nodeAt('plant/line1'), isNull);
    });
  });
}
