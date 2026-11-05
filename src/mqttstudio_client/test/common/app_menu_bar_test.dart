import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/app_menu_bar.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';

void main() {
  late TabController tabController;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTranslations();
  });

  setUp(() {
    setUpServices();
    GetIt.I.registerSingleton(SrxNavigationService(Container(), Container()));
  });
  tearDown(tearDownServices);

  Widget menuBar({bool isProjectOpen = false}) => DefaultTabController(
      length: 4,
      child: Builder(builder: (context) {
        tabController = DefaultTabController.of(context);
        return AppMenuBar(tabController: tabController, isProjectOpen: isProjectOpen, child: Text('window'));
      }));

  PlatformMenuItem item(WidgetTester tester, String menu, String label) {
    var menus = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus;
    var items = menus.whereType<PlatformMenu>().singleWhere((m) => m.label == menu).menus;
    return items
        .expand((i) => i is PlatformMenuItemGroup ? i.members : [i])
        .singleWhere((i) => i.label == label);
  }

  // SingleActivator has no value equality
  String keys(PlatformMenuItem item) {
    var shortcut = item.shortcut as SingleActivator;
    return [
      if (shortcut.meta) 'meta',
      if (shortcut.control) 'control',
      if (shortcut.shift) 'shift',
      shortcut.trigger.keyLabel,
    ].join('+');
  }

  group('on Windows', () {
    testWidgets('Ctrl with a digit switches the tab', (tester) async {
      await tester.pumpWidget(testApp(menuBar()));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(tabController.index, 2);

      // the macOS key does nothing on Windows
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(tabController.index, 2);
      expect(find.byType(PlatformMenuBar), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });

  group('on macOS', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.menu, (_) async => null);
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.menu, null);
    });

    testWidgets('the menu bar uses ⌘ and disables the project commands without a project', (tester) async {
      await tester.pumpWidget(testApp(menuBar()));
      await tester.pumpAndSettle();

      expect(keys(item(tester, 'File', 'New Project…')), 'meta+N');
      expect(keys(item(tester, 'Edit', 'Redo')), 'meta+shift+Z');
      expect(item(tester, 'File', 'Save Project').onSelected, isNull);
      expect(item(tester, 'File', 'Close Project').onSelected, isNull);

      item(tester, 'View', 'Recorder').onSelected!();
      await tester.pumpAndSettle();
      expect(tabController.index, 2);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('the project commands are enabled while a project is open', (tester) async {
      await tester.pumpWidget(testApp(menuBar(isProjectOpen: true)));
      await tester.pumpAndSettle();

      expect(keys(item(tester, 'File', 'Save Project')), 'meta+S');
      expect(item(tester, 'File', 'Save Project').onSelected, isNotNull);
      expect(item(tester, 'File', 'Project Settings…').onSelected, isNotNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });
}
