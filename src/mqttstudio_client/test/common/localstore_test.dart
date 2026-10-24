import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/test_setup.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('LocalStore projects', () {
    test('returns no projects when nothing was saved', () async {
      expect(await LocalStore().getProjects(), isEmpty);
    });

    test('saves and reloads projects', () async {
      await LocalStore().saveProject(createProject('First'));
      await LocalStore().saveProject(createProject('Second'));

      var projects = await LocalStore().getProjects();

      expect(projects.map((x) => x.name), unorderedEquals(['First', 'Second']));
    });

    test('saving a project with the same name replaces it', () async {
      await LocalStore().saveProject(createProject('First'));
      await LocalStore().saveProject(createProject('First')..mqttSettings.hostname = 'changed.host');

      var projects = await LocalStore().getProjects();

      expect(projects.single.mqttSettings.hostname, 'changed.host');
    });

    test('deletes a project', () async {
      var first = createProject('First');
      await LocalStore().saveProject(first);
      await LocalStore().saveProject(createProject('Second'));

      var remaining = await LocalStore().deleteProject(first);

      expect(remaining.map((x) => x.name), ['Second']);
      expect((await LocalStore().getProjects()).map((x) => x.name), ['Second']);
    });
  });

  group('LocalStore flags', () {
    test('are off by default', () async {
      var store = LocalStore();
      expect(await store.getBrowserPerformanceWarningDoNotShow(), isFalse);
      expect(await store.getNewsletterSignupDoNotShow(), isFalse);
      expect(await store.getCoachingCompleted(), isFalse);
    });

    test('are persisted independently', () async {
      await LocalStore().saveNewsletterSignupDoNotShow(true);
      await LocalStore().saveCoachingCompleted(true);

      var store = LocalStore();
      expect(await store.getBrowserPerformanceWarningDoNotShow(), isFalse);
      expect(await store.getNewsletterSignupDoNotShow(), isTrue);
      expect(await store.getCoachingCompleted(), isTrue);
    });

    test('saving a flag keeps the saved projects', () async {
      await LocalStore().saveProject(createProject('First'));
      await LocalStore().saveBrowserPerformanceWarningDoNotShow(true);

      expect((await LocalStore().getProjects()).single.name, 'First');
    });
  });
}
