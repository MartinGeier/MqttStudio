import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/fast_topic_chip.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/recorder/engine/playback_service.dart';
import 'package:mqttstudio/recorder/engine/recorder_service.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/recorder_page.dart';
import 'package:mqttstudio/recorder/recorder_viewmodel.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';

void main() {
  setUpAll(loadTranslations);

  setUp(() {
    setUpServices();
    GetIt.I.registerSingleton(SrxNavigationService(Container(), Container()));
  });

  tearDown(() async {
    GetIt.I.get<RecorderService>().dispose();
    GetIt.I.get<PlaybackService>().dispose();
    await tearDownServices();
  });

  // a/temp every second for 100 s with a hole from 40 s to 70 s while the connection was lost, b/state now and then
  Future<RecordingInfo> writeLine() {
    var entries = <Object>[];
    for (var s = 0; s < 100; s++) {
      if (s == 45) {
        entries.add(RecordingMarker(45 * 1000000, RecordingMarker.connectionLost));
      }
      if (s < 40 || s >= 70) {
        entries.add(recorded(s.toDouble(), 'a/temp', '${20 + s % 5}'));
      }
      if (s % 25 == 0) {
        entries.add(recorded(s + 0.5, 'b/state', '{"ok": true, "load": $s}'));
      }
    }
    return writeRecording(GetIt.I.get<RecordingLibrary>(), 'Line', entries, durationMicros: 100000000, filters: [
      RecorderFilter('a/#', color: TopicColor(Colors.blue)),
      RecorderFilter('b/#', color: TopicColor(Colors.pink)),
    ]);
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(Size(1700, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openNewProject();
    await tester.pumpWidget(testApp(RecorderPage()));
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String tab) async {
    await tester.tap(find.text(tab));
    await tester.pumpAndSettle();
  }

  RecorderViewmodel recorderViewmodel(WidgetTester tester) =>
      Provider.of<RecorderViewmodel>(tester.element(find.text('TIMELINE')), listen: false);

  // FastTopicChip paints its text, so it is found by its topic
  Finder chip(String topic) => find.byWidgetPredicate((widget) => widget is FastTopicChip && widget.topic == topic);

  Finder lanes() => find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter.runtimeType.toString() == '_LanesPainter');

  void testPage(String description, Future<void> Function(WidgetTester tester) body) =>
      testWidgets(description, (tester) => ignoringOverflowErrors(() => body(tester)));

  testPage('the overview counts the gaps of each topic', (tester) async {
    await writeLine();
    await pumpPage(tester);
    expect(find.text('OVERVIEW'), findsOneWidget);
    expect(find.text('Gaps'), findsOneWidget);
    // a/temp has the 31 s gap, b/state sends every 25 s, so its default threshold is longer
    expect(find.text('1'), findsWidgets);
  });

  testPage('the topic column of the timeline grows with the longest topic, up to 40 %', (tester) async {
    var long = 'vda5050/v3/MQTTStudio/SIM-1/visualization';
    await writeRecording(GetIt.I.get<RecordingLibrary>(), 'Long',
        [recorded(0, 'a/temp', '1'), recorded(1, long, '2'), recorded(2, '$long/${'x' * 200}', '3')],
        durationMicros: 3000000);
    await pumpPage(tester);
    await openTab(tester, 'TIMELINE');
    var column = tester.getRect(lanes()).left - tester.getRect(find.byType(Scrollbar).first).left;
    var timelineWidth = tester.getRect(find.byType(Scrollbar).first).width;
    // wider than the 240 px of short topics, but a very long topic doesn't take more than 40 % of the timeline
    expect(column, greaterThan(240));
    expect(column, lessThanOrEqualTo(timelineWidth * 0.4 + 1));
    expect(chip(long), findsOneWidget);
  });

  testPage('the timeline lists gaps and selects a range by dragging', (tester) async {
    await writeLine();
    await pumpPage(tester);
    await openTab(tester, 'TIMELINE');
    expect(find.text('connection lost'), findsOneWidget);
    expect(find.text('at 00:00:39 for 31s'), findsOneWidget);

    var rect = tester.getRect(lanes());
    await tester.dragFrom(Offset(rect.left + rect.width * 0.1, rect.top + 10), Offset(rect.width * 0.4, 0));
    await tester.pumpAndSettle();
    var options = recorderViewmodel(tester).options;
    expect(options.rangeStartMicros! / 1000000, closeTo(10, 1.5));
    expect(options.rangeEndMicros! / 1000000, closeTo(50, 1.5));
    expect(find.textContaining('Range 00:00:'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear the range'));
    await tester.pumpAndSettle();
    expect(recorderViewmodel(tester).options.rangeStartMicros, isNull);
  });

  testPage('a right-click on the lanes adds a bookmark', (tester) async {
    await writeLine();
    await pumpPage(tester);
    await openTab(tester, 'TIMELINE');
    expect(find.text('No bookmarks'), findsOneWidget);
    var rect = tester.getRect(lanes());
    await tester.tapAt(Offset(rect.left + rect.width / 2, rect.top + 10), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Add bookmark at 00:00:'));
    await tester.pumpAndSettle();
    var info = (await GetIt.I.get<RecordingLibrary>().list()).single;
    expect(info.footer.bookmarks.single.label, 'Bookmark 1');
    expect(info.footer.bookmarks.single.offsetMicros / 1000000, closeTo(50, 1));
    expect(find.text('Bookmark 1'), findsWidgets);
  });

  testPage('MESSAGES shows the recorded messages and hides a filter', (tester) async {
    await writeLine();
    await pumpPage(tester);
    await openTab(tester, 'MESSAGES');
    expect(find.text('74 messages'), findsOneWidget);
    expect(chip('b/state'), findsWidgets);
    var temps = chip('a/temp').evaluate().length;
    expect(temps, greaterThan(1));

    await tester.tap(chip('b/#').last);
    await tester.pumpAndSettle();
    expect(chip('b/state'), findsNothing);
    expect(chip('a/temp').evaluate().length, temps);

    // play, pause, clear and publish don't apply to a recording
    for (var tooltip in ['Pause', 'Clear messages', 'Publish a message']) {
      expect(find.byTooltip(tooltip), findsNothing, reason: tooltip);
    }
    // the views still work, and the detail view has only its close button
    await tester.tap(find.byIcon(Icons.format_list_bulleted));
    await tester.pumpAndSettle();
    expect(chip('a/temp'), findsWidgets);
    await tester.tap(chip('a/temp').first);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsWidgets);
    expect(find.text('AUTOSELECT'), findsNothing);
    expect(find.text('PUBLISH'), findsNothing);
  });

  Future<void> openMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('Edit, export or delete the recording'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  testPage('the menu trims to the range and keeps the selected topics', (tester) async {
    await writeLine();
    await pumpPage(tester);
    var vm = recorderViewmodel(tester);
    await tester.tap(find.byTooltip('Edit, export or delete the recording'));
    await tester.pumpAndSettle();
    // without a range there is nothing to trim to
    expect(tester.widget<PopupMenuItem<String>>(find.widgetWithText(PopupMenuItem<String>, 'Trim to the range')).enabled,
        isFalse);
    await tester.tapAt(Offset(5, 5));
    await tester.pumpAndSettle();

    await vm.setRange(10000000, 30000000);
    await tester.pumpAndSettle();
    await openMenu(tester, 'Trim to the range');
    var trimmed = (await GetIt.I.get<RecordingLibrary>().list()).firstWhere((info) => info.name == 'Line (trimmed)');
    expect(trimmed.footer.durationMicros, 20000000);
    expect(recorderViewmodel(tester).selected!.id, trimmed.id);

    await recorderViewmodel(tester).toggleTopic('b/state', false);
    await tester.pumpAndSettle();
    await openMenu(tester, 'Keep the selected topics');
    var kept = (await GetIt.I.get<RecordingLibrary>().list()).firstWhere((info) => info.name == 'Line (trimmed) (a/temp)');
    expect(kept.footer.topics, ['a/temp']);
  });

  testPage('rename and merge write new recordings from their dialogs', (tester) async {
    await writeLine();
    await writeRecording(GetIt.I.get<RecordingLibrary>(), 'Other', [recorded(0, 'c/x', '1')],
        startedAt: DateTime.utc(2026, 10, 24, 7));
    await pumpPage(tester);
    await tester.tap(find.text('Line').first);
    await tester.pumpAndSettle();

    await openMenu(tester, 'Rename topics…');
    await tester.enterText(find.widgetWithText(TextField, 'From'), 'a/');
    await tester.enterText(find.widgetWithText(TextField, 'To'), 'site/a/');
    await tester.pumpAndSettle();
    expect(find.text('a/temp  →  site/a/temp'), findsOneWidget);
    await tester.tap(find.text('RENAME'));
    await tester.pumpAndSettle();
    var renamed = (await GetIt.I.get<RecordingLibrary>().list()).firstWhere((info) => info.name == 'Line (renamed)');
    expect(renamed.footer.topics, containsAll(['site/a/temp', 'b/state']));

    await openMenu(tester, 'Merge with…');
    await tester.tap(find.text('MERGE'));
    await tester.pumpAndSettle();
    expect(find.text('Choose at least one recording'), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Other'));
    await tester.tap(find.text('MERGE'));
    await tester.pumpAndSettle();
    var merged = (await GetIt.I.get<RecordingLibrary>().list()).firstWhere((info) => info.name == 'Line (renamed) (merged)');
    expect(merged.footer.topics, containsAll(['c/x', 'site/a/temp']));
    expect(merged.header.startedAt, DateTime.utc(2026, 10, 24, 7));
  });

  testPage('COMPARE lists the differing topics and shows a difference side by side', (tester) async {
    await writeLine();
    await writeRecording(GetIt.I.get<RecordingLibrary>(), 'Changed', [
      for (var s = 0; s < 100; s++)
        if (s < 40 || s >= 70) recorded(s.toDouble(), 'a/temp', s == 80 ? '99' : '${20 + s % 5}'),
    ], startedAt: DateTime.utc(2026, 10, 24, 7));
    await pumpPage(tester);
    await tester.tap(find.text('Line').first);
    await tester.pumpAndSettle();
    await openTab(tester, 'COMPARE');
    await tester.tap(find.text('COMPARE').last);
    await tester.pumpAndSettle();
    expect(find.text('Choose a recording'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Changed ·').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('COMPARE').last);
    await tester.pumpAndSettle();
    expect(find.text('1 topics differ, 1 only in A, 0 only in B'), findsOneWidget);
    expect(find.text('only in A'), findsOneWidget);
    // the 81st message of a/temp is the 51st one in both recordings
    await tester.tap(find.text('message 51, payload'));
    await tester.pumpAndSettle();
    expect(find.text('a/temp: message 51'), findsOneWidget);
    expect(find.text('99'), findsOneWidget);
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
  });

  testPage('the list shows the open project\'s recordings and assigns others to it', (tester) async {
    var library = GetIt.I.get<RecordingLibrary>();
    await writeRecording(library, 'Mine', [recorded(0, 'a', '1')]);
    await writeRecording(library, 'Theirs', [recorded(0, 'a', '1')], projectName: 'Other');
    await writeRecording(library, 'Loose', [recorded(0, 'a', '1')], projectName: null);
    await pumpPage(tester);
    expect(find.text('Test project: 1 of 3 recordings'), findsOneWidget);
    expect(find.text('Mine'), findsWidgets);
    expect(find.text('Theirs'), findsNothing);

    await tester.tap(find.byTooltip('Showing the recordings of Test project. Click to show all recordings'));
    await tester.pumpAndSettle();
    expect(find.text('All projects: 3 recordings'), findsOneWidget);
    expect(find.text('Other / Theirs'), findsOneWidget);
    expect(find.text('Test project / Mine'), findsOneWidget);
    expect(find.text('Loose'), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.text('Loose').first), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assign to project Test project'));
    await tester.pumpAndSettle();
    var loose = (await library.list()).firstWhere((info) => info.name == 'Loose');
    expect(loose.projectName, 'Test project');
    expect(loose.header.projectName, isNull);

    await tester.tap(find.byTooltip('Showing all recordings. Click to show only those of Test project'));
    await tester.pumpAndSettle();
    expect(find.text('Test project: 2 of 3 recordings'), findsOneWidget);
  });

  testPage('CHARTS shows the values of a topic with their statistics', (tester) async {
    await writeLine();
    await pumpPage(tester);
    await openTab(tester, 'CHARTS');
    expect(find.text('a/temp'), findsWidgets);
    expect(find.text('Payload as number'), findsOneWidget);
    expect(find.textContaining('Values 70', findRichText: true), findsOneWidget);
    expect(find.textContaining('Max 24', findRichText: true), findsOneWidget);
    expect(find.text('Time between messages'), findsOneWidget);
  });
}
