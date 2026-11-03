import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:mqttstudio/project/project_edit_dialog.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';

void main() {
  late ProjectManager manager;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTranslations();
  });

  setUp(() {
    setUpServices();
    GetIt.I.registerSingleton(SrxNavigationService(Container(), Container()));
    manager = GetIt.I.get<ProjectManager>();
  });
  tearDown(tearDownServices);

  Future openDialog(WidgetTester tester) async {
    await tester.pumpWidget(testApp(Builder(
        builder: (context) =>
            TextButton(onPressed: () async => await editAndOpenProject(context), child: Text('edit')))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();
  }

  Future enterName(WidgetTester tester, String name) async {
    await tester.enterText(find.widgetWithText(TextField, 'Project name'), name);
    var ok = find.widgetWithText(ElevatedButton, 'Ok');
    await tester.ensureVisible(ok);
    await tester.tap(ok);
    await tester.pumpAndSettle();
  }

  group('ProjectEditDialog', () {
    testWidgets('rejects the name of another saved project', (tester) => ignoringOverflowErrors(() async {
          await tester.runAsync(() => LocalStore().saveProject(createProject('Taken')));
          await openDialog(tester);
          await tester.enterText(find.widgetWithText(TextField, 'MQTT Broker'), 'broker.local');

          await enterName(tester, 'Taken');

          expect(find.text('Another project has this name'), findsOneWidget);
          expect(manager.isProjectOpen, isFalse);

          await enterName(tester, 'Free name');

          expect(manager.currentProject?.name, 'Free name');
        }));

    testWidgets('renaming the open project keeps one saved project', (tester) => ignoringOverflowErrors(() async {
          await tester.runAsync(() => openNewProject('Old name'));
          await openDialog(tester);

          expect(find.text('Old name'), findsOneWidget, reason: 'the open project may keep its own name');
          await enterName(tester, 'New name');

          var names = await tester.runAsync(() async => (await LocalStore().getProjects()).map((x) => x.name).toList());
          expect(names, ['New name']);
        }));
  });
}
