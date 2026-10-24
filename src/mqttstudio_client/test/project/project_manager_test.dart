import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:mqttstudio/project/project_manager.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_setup.dart';

void main() {
  late FakeMqttAdapter adapter;
  late ProjectManager manager;

  setUp(() {
    adapter = setUpServices();
    manager = GetIt.I.get<ProjectManager>();
  });

  tearDown(tearDownServices);

  Future<List<String>> savedProjectNames() async => (await LocalStore().getProjects()).map((x) => x.name).toList();

  group('ProjectManager open', () {
    test('opens a project and notifies', () async {
      var opened = 0;
      manager.projectOpenedEvent.subscribe((_) => opened++);

      var project = await openNewProject();

      expect(manager.currentProject, same(project));
      expect(manager.isProjectOpen, isTrue);
      expect(project.lastUsed, isNotNull);
      expect(opened, 1);
    });

    test('a newly opened project is unchanged', () async {
      await openNewProject();
      expect(manager.hasProjectChanged(), isFalse);
    });

    test('does not save a new project until it is changed and closed', () async {
      await openNewProject();
      expect(await savedProjectNames(), isEmpty);
    });

    test('saves a previously used project again when it is opened', () async {
      var project = createProject('Used before')..lastUsed = DateTime(2026, 1, 1);

      await manager.openProject(project);

      expect(await savedProjectNames(), ['Used before']);
      expect(project.lastUsed!.isAfter(DateTime(2026, 1, 1)), isTrue);
    });

    test('opening another project saves and closes the current one', () async {
      var first = await openNewProject('First');
      first.recentTopics.add('changed');

      await manager.openProject(createProject('Second'));

      expect(manager.currentProject!.name, 'Second');
      expect(await savedProjectNames(), ['First']);
      expect(closingNotSavedCount, 0, reason: 'opening another project saves without asking');
    });
  });

  group('ProjectManager changes and saving', () {
    test('detects a change of the project', () async {
      var project = await openNewProject();

      project.recentTopics.add('home/temp');

      expect(manager.hasProjectChanged(), isTrue);
    });

    test('saving resets the change detection', () async {
      var project = await openNewProject();
      project.recentTopics.add('home/temp');

      await manager.saveProject();

      expect(manager.hasProjectChanged(), isFalse);
      expect(await savedProjectNames(), ['Test project']);
    });
  });

  group('ProjectManager close', () {
    test('closes an unchanged project without asking', () async {
      var closed = 0;
      await openNewProject();
      manager.projectClosedEvent.subscribe((_) => closed++);

      expect(await manager.closeProject(), isTrue);

      expect(closingNotSavedCount, 0);
      expect(manager.isProjectOpen, isFalse);
      expect(closed, greaterThan(0));
    });

    test('asks before closing a changed project and saves on yes', () async {
      var project = await openNewProject();
      project.recentTopics.add('home/temp');
      closingNotSavedAnswer = true;

      expect(await manager.closeProject(), isTrue);

      expect(closingNotSavedCount, 1);
      expect(manager.isProjectOpen, isFalse);
      expect((await LocalStore().getProjects()).single.recentTopics, ['home/temp']);
    });

    test('closes without saving on no', () async {
      var project = await openNewProject();
      project.recentTopics.add('home/temp');
      closingNotSavedAnswer = false;

      expect(await manager.closeProject(), isTrue);

      expect(manager.isProjectOpen, isFalse);
      expect(await savedProjectNames(), isEmpty);
    });

    test('stays open on cancel', () async {
      var project = await openNewProject();
      project.recentTopics.add('home/temp');
      closingNotSavedAnswer = null;
      var disconnects = adapter.disconnectCount;

      expect(await manager.closeProject(), isFalse);

      expect(manager.currentProject, same(project));
      expect(adapter.disconnectCount, disconnects);
    });

    test('closing disconnects from the broker', () async {
      var project = await openNewProject();
      await adapter.connect(project.mqttSettings);

      await manager.closeProject();

      expect(adapter.isConnected(), isFalse);
    });

    test('closing with force saves without asking', () async {
      var project = await openNewProject();
      project.recentTopics.add('home/temp');

      await manager.closeProject(true);

      expect(closingNotSavedCount, 0);
      expect(await savedProjectNames(), ['Test project']);
    });
  });
}
