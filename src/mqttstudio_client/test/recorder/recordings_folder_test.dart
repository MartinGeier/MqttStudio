import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/recorder/format/recording_writer.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';
import 'package:mqttstudio/recorder/widgets/recordings_folder_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/test_app.dart';

void main() {
  late Directory root;
  late String first;
  late String second;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mqttrec');
    first = '${root.path}${Platform.pathSeparator}first';
    second = '${root.path}${Platform.pathSeparator}second';
  });

  tearDown(() => root.delete(recursive: true));

  Future<void> record(RecordingLibrary library, String name) async {
    var file = await library.create(name, DateTime(2026, 10, 24));
    var writer = await RecordingWriter.start(
        file,
        RecordingHeader(
            id: name,
            startedAt: DateTime.utc(2026, 10, 24),
            filters: [],
            broker: 'b',
            protocol: MqttProtocolVersion.v5,
            clientId: 'c',
            appVersion: ''));
    await writer.finish(name: name, durationMicros: 0);
    library.finishedWriting(file.name);
  }

  test('the library switches folders and leaves the recordings where they are', () async {
    var library = RecordingLibrary(FolderRecordingStore(Directory(first)), defaultLocation: first);
    await record(library, 'In first');
    expect(library.isDefaultLocation, isTrue);

    var changes = 0;
    library.changedEvent.subscribe((_) => changes++);
    await library.useFolder(second);
    expect(Directory(second).existsSync(), isTrue);
    expect(library.location, second);
    expect(library.isDefaultLocation, isFalse);
    expect(await library.list(), isEmpty);
    await record(library, 'In second');
    expect((await library.list()).map((info) => info.name), ['In second']);

    await library.useFolder(first);
    expect((await library.list()).map((info) => info.name), ['In first']);
    expect(changes, greaterThanOrEqualTo(2));
  });

  test('the folder cannot change while a recording is written', () async {
    var library = RecordingLibrary(FolderRecordingStore(Directory(first)));
    var file = await library.create('Running', DateTime(2026, 10, 24));
    expect(() => library.useFolder(second), throwsStateError);
    await file.close();
  });

  test('the chosen folder is kept in the local store, null means the default', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await LocalStore().getRecordingsFolder(), isNull);
    await LocalStore().saveRecordingsFolder(second);
    expect(await LocalStore().getRecordingsFolder(), second);
    await LocalStore().saveRecordingsFolder(null);
    expect(await LocalStore().getRecordingsFolder(), isNull);
  });

  group('RecordingsFolderDialog', () {
    setUpAll(loadTranslations);

    setUp(() => GetIt.I.registerSingleton(SrxNavigationService(Container(), Container())));

    tearDown(() => GetIt.I.reset());

    Future<DialogHostState> open(WidgetTester tester, String current) async {
      await tester.pumpWidget(testApp(DialogHost(RecordingsFolderDialog(current: current, defaultFolder: first))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return tester.state<DialogHostState>(find.byType(DialogHost));
    }

    testWidgets('DEFAULT goes back to the default folder', (tester) async {
      var host = await open(tester, second);
      expect(find.text(second), findsOneWidget);
      await tester.tap(find.text('DEFAULT'));
      await tester.pump();
      expect(find.text(first), findsOneWidget);
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();
      expect(host.result, first);
    });

    testWidgets('saving without a change returns nothing, DEFAULT is off on the default folder', (tester) async {
      var host = await open(tester, first);
      var defaultButton = tester.widget<TextButton>(find.ancestor(of: find.text('DEFAULT'), matching: find.byType(TextButton)));
      expect(defaultButton.onPressed, isNull);
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();
      expect(host.result, isNull);
    });
  });
}
