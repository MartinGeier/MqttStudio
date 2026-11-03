import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:mqttstudio/common/widgets/no_project_view.dart';
import 'package:mqttstudio/common/widgets/sarix_banner.dart';
import 'package:mqttstudio/project/open_project_viewmodel.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/project/recent_projects_panel.dart';
import 'package:mqttstudio/project/recent_projects_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    manager = GetIt.I.get<ProjectManager>();
  });
  tearDown(tearDownServices);

  // saves projects named 'Project 0', 'Project 1', … each used a day after the one before
  Future saveProjects(int count) async {
    for (var i = 0; i < count; i++) {
      await LocalStore().saveProject(createProject('Project $i')..lastUsed = DateTime(2026, 10, 1 + i, 9, 30));
    }
  }

  // lets the background loads run until the condition holds, failing instead of hanging when it never does
  Future until(bool Function() condition) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await Future.delayed(Duration.zero);
    }
    expect(condition(), isTrue);
  }

  Future<RecentProjectsViewmodel> loadedViewmodel() async {
    var viewmodel = RecentProjectsViewmodel();
    await until(() => viewmodel.isLoaded);
    return viewmodel;
  }

  group('ProjectManager saved projects', () {
    test('lists the last used project first and never used ones last', () async {
      await saveProjects(3);
      await LocalStore().saveProject(createProject('Never used'));

      var names = (await manager.getProjects()).map((x) => x.name);

      expect(names, ['Project 2', 'Project 1', 'Project 0', 'Never used']);
    });

    test('deleting a project returns the remaining ones last used first and notifies', () async {
      await saveProjects(3);
      var changes = 0;
      manager.projectsChangedEvent.subscribe((_) => changes++);

      var remaining = await manager.deleteProject((await manager.getProjects())[1]);

      expect(remaining.map((x) => x.name), ['Project 2', 'Project 0']);
      expect((await manager.getProjects()).map((x) => x.name), ['Project 2', 'Project 0']);
      expect(changes, 1);
    });

    test('saving the current project notifies', () async {
      await openNewProject();
      var changes = 0;
      manager.projectsChangedEvent.subscribe((_) => changes++);

      await manager.saveProject();

      expect(changes, 1);
    });
  });

  group('RecentProjectsViewmodel', () {
    test('keeps the six last used projects', () async {
      await saveProjects(8);

      var viewmodel = await loadedViewmodel();

      expect(viewmodel.projects.map((x) => x.name),
          ['Project 7', 'Project 6', 'Project 5', 'Project 4', 'Project 3', 'Project 2']);
    });

    test('reloads when the open project dialog deletes a project', () async {
      await saveProjects(2);
      var viewmodel = await loadedViewmodel();

      await OpenProjectViewmodel().deleteProject(viewmodel.projects.first);

      await until(() => viewmodel.projects.length == 1);
      expect(viewmodel.projects.map((x) => x.name), ['Project 0']);
    });

    test('shows no projects when the saved projects cannot be read', () async {
      SharedPreferences.setMockInitialValues({LocalStore.localStoreKey: 'not json'});

      var viewmodel = await loadedViewmodel();

      expect(viewmodel.projects, isEmpty);
    });
  });

  group('RecentProjectsPanel', () {
    setUp(() => GetIt.I.registerSingleton(SrxNavigationService(Container(), Container())));

    testWidgets('shows the recent projects with broker and last use', (tester) => ignoringOverflowErrors(() async {
          await tester.runAsync(() => saveProjects(2));
          await tester.pumpWidget(testApp(SingleChildScrollView(child: RecentProjectsPanel())));
          await tester.pumpAndSettle();

          expect(find.text('Recent projects'), findsOneWidget);
          expect(find.text('Project 1'), findsOneWidget);
          expect(find.text('Project 0'), findsOneWidget);
          expect(find.text('test.mosquitto.org:1883 | MQTT 3.1.1'), findsNWidgets(2));
          expect(find.text('Last used 2026-10-02 09:30'), findsOneWidget);
        }));

    testWidgets('opens a project on tap', (tester) => ignoringOverflowErrors(() async {
          await tester.runAsync(() => saveProjects(2));
          await tester.pumpWidget(testApp(SingleChildScrollView(child: RecentProjectsPanel())));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Project 0'));
          await tester.pumpAndSettle();

          expect(manager.currentProject?.name, 'Project 0');
        }));

    testWidgets('shows a watermark without saved projects', (tester) => ignoringOverflowErrors(() async {
          await tester.pumpWidget(testApp(SingleChildScrollView(child: RecentProjectsPanel())));
          await tester.pumpAndSettle();

          expect(find.text('No recent projects'), findsOneWidget);
          expect(find.text('NEW PROJECT'), findsOneWidget);
          expect(find.text('OPEN PROJECT'), findsOneWidget);
        }));

    testWidgets('leaves out the last use of a never used project', (tester) => ignoringOverflowErrors(() async {
          await tester.runAsync(() => LocalStore().saveProject(createProject('Never used')));
          await tester.pumpWidget(testApp(SingleChildScrollView(child: RecentProjectsPanel())));
          await tester.pumpAndSettle();

          expect(find.text('Never used'), findsOneWidget);
          expect(find.textContaining('Last used'), findsNothing);
        }));

    testWidgets('the Sarix banner stays visible below the recent projects', (tester) => ignoringOverflowErrors(() async {
          // the topic viewer body of a maximized window
          tester.view.physicalSize = Size(1620, 870);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.runAsync(() => saveProjects(6));
          await tester.pumpWidget(testApp(NoProjectView()));
          await tester.pumpAndSettle();

          var panel = tester.getRect(find.byType(RecentProjectsPanel));
          var banner = tester.getRect(find.byType(SarixBanner));
          expect(banner.bottom, lessThanOrEqualTo(870));
          expect(panel.bottom, lessThan(banner.top));
        }));
  });
}
