import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:mqttstudio/recorder/recorder_viewmodel.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/recorder/engine/playback_service.dart';
import 'package:mqttstudio/recorder/engine/recorder_service.dart';
import 'package:mqttstudio/recorder/engine/recording_player.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/model/recorder_config.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/playback_options_viewmodel.dart';
import 'package:mqttstudio/recorder/record_viewmodel.dart';
import 'package:mqttstudio/recorder/recorder_page.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';

void main() {
  late FakeMqttAdapter adapter;
  late List<FakeMqttAdapter> recorderConnections;

  setUpAll(loadTranslations);

  setUp(() {
    adapter = setUpServices();
    GetIt.I.registerSingleton(SrxNavigationService(Container(), Container()));
    // a recorder whose connections the tests can reach
    GetIt.I.get<RecorderService>().dispose();
    GetIt.I.unregister<RecorderService>();
    recorderConnections = [];
    GetIt.I.registerSingleton(RecorderService(GetIt.I.get<RecordingLibrary>(), connectionFactory: () {
      var connection = FakeMqttAdapter();
      recorderConnections.add(connection);
      return connection;
    }));
  });

  tearDown(() async {
    GetIt.I.get<RecorderService>().dispose();
    GetIt.I.get<PlaybackService>().dispose();
    await tearDownServices();
  });

  Future<void> pumpPage(WidgetTester tester, {bool openProject = true}) async {
    await tester.binding.setSurfaceSize(Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    if (openProject) {
      await openNewProject();
    }
    await tester.pumpWidget(testApp(RecorderPage()));
    await tester.pumpAndSettle();
  }

  void testPage(String description, Future<void> Function(WidgetTester tester) body) =>
      testWidgets(description, (tester) => ignoringOverflowErrors(() => body(tester)));

  ReceivedMqttMessage incoming(String topic, String payload) =>
      ReceivedMqttMessage(1, topic, toPayload(payload), MqttQos.atMostOnce, DateTime.now(), false);

  testPage('without a project nothing can be recorded', (tester) async {
    await pumpPage(tester, openProject: false);
    expect(find.text('No recording selected'), findsOneWidget);
    var record = tester.widget<TextButton>(find.ancestor(of: find.text('RECORD'), matching: find.byType(TextButton)));
    expect(record.onPressed, isNull);
  });

  testPage('records from the dialog, shows it live and lists it once stopped', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('RECORD'));
    await tester.pumpAndSettle();
    expect(find.text('Record'), findsOneWidget);
    // one empty filter to fill in
    await tester.enterText(find.widgetWithText(TextField, 'Topic filter'), '#');
    await tester.enterText(find.widgetWithText(TextField, 'Recording 1'), 'Line 1');
    await tester.ensureVisible(find.text('RECORD').last);
    await tester.tap(find.text('RECORD').last);
    await tester.pumpAndSettle();

    expect(GetIt.I.get<RecorderService>().isRecording, isTrue);
    var connection = recorderConnections.single;
    expect(connection.subscribed, ['#']);
    connection.receive(incoming('plant/temp', '21.5'));
    connection.receive(incoming('plant/temp', '21.6'));
    await tester.pump(Duration(seconds: 1));
    expect(find.textContaining('2 messages'), findsWidgets);

    await tester.tap(find.byTooltip('Stop recording'));
    await tester.pumpAndSettle();
    expect(GetIt.I.get<RecorderService>().isRecording, isFalse);
    expect(find.text('Line 1'), findsWidgets);
    expect(find.text('1 of 1 topics selected for playback'), findsOneWidget);

    // the list item edits and deletes the recording
    await tester.tap(find.byTooltip('Edit name and notes').first);
    await tester.pumpAndSettle();
    expect(find.text('Edit recording'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Line 1 renamed');
    await tester.enterText(find.widgetWithText(TextField, 'Notes'), 'checked');
    await tester.tap(find.text('SAVE').last);
    await tester.pumpAndSettle();
    var edited = (await GetIt.I.get<RecordingLibrary>().list()).single;
    expect(edited.name, 'Line 1 renamed');
    expect(edited.footer.notes, 'checked');
    expect(find.text('Line 1 renamed'), findsWidgets);
    await tester.tap(find.byTooltip('Delete recording'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(await GetIt.I.get<RecordingLibrary>().list(), isEmpty);
  });

  testPage('plays the selected recording on the main connection', (tester) async {
    await pumpPage(tester);
    var recorder = GetIt.I.get<RecorderService>();
    await recorder.start(RecorderConfig(name: 'Replay me', filters: [RecorderFilter('plant/#')]));
    recorderConnections.single.receive(incoming('plant/temp', '1'));
    await recorder.stop();
    await tester.pumpAndSettle();

    var play = find.byTooltip('Connect to a broker first');
    expect(tester.widget<IconButton>(find.ancestor(of: play, matching: find.byType(IconButton))).onPressed, isNull);

    await adapter.connect(MqttSettings('localhost', 'c', 1883));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Play recording'));
    await tester.pump();
    await tester.pump(Duration(milliseconds: 100));
    expect(adapter.published.map((m) => m.topic), ['plant/temp']);
    await tester.pump(Duration(seconds: 1));
    expect(GetIt.I.get<PlaybackService>().state, PlaybackState.stopped);
    await tester.pumpAndSettle();
  });

  testPage('the filter dropdown offers the subscribed topics', (tester) async {
    await pumpPage(tester);
    GetIt.I.get<ProjectManager>().currentProject!.topicSubscriptions.add(TopicSubscription('plant/#', MqttQos.atMostOnce));
    await tester.tap(find.text('RECORD'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Topic filter')).controller!.text, '');
    await tester.tap(find.byTooltip('Subscribed topics and the last filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('plant/#').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Topic filter')).controller!.text, 'plant/#');
  });

  testPage('the flight recorder starts from the dialog and SAVE writes a recording', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('RECORD'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Normal recording'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flight recorder').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Topic filter'), 'plant/#');
    expect(find.text('Window'), findsOneWidget);
    expect(find.text('Start when (empty = right away)'), findsNothing);
    await tester.ensureVisible(find.text('RECORD').last);
    await tester.tap(find.text('RECORD').last);
    await tester.pumpAndSettle();

    var recorder = GetIt.I.get<RecorderService>();
    expect(recorder.isFlightRecorder, isTrue);
    recorderConnections.single.receive(incoming('plant/temp', '1'));
    await tester.pump(Duration(seconds: 1));
    await tester.tap(find.text('SAVE'));
    await tester.pump();
    expect(find.text('SAVING…'), findsOneWidget);
    // stopping writes the save right away instead of after its post-roll
    await tester.tap(find.byTooltip('Stop recording'));
    await tester.pumpAndSettle();
    var saved = await GetIt.I.get<RecordingLibrary>().list();
    expect(saved.single.header.origin, RecordingOrigin.flightRecorder);
    expect(saved.single.footer.summary.messages, 1);
  });

  testPage('the loop button stays pressed while loop is on', (tester) async {
    await pumpPage(tester);
    var recorder = GetIt.I.get<RecorderService>();
    await recorder.start(RecorderConfig(name: 'Loop me', filters: [RecorderFilter('plant/#')]));
    await recorder.stop();
    await tester.pumpAndSettle();

    ToggleButtons loop() =>
        tester.widget<ToggleButtons>(find.ancestor(of: find.byIcon(Icons.repeat), matching: find.byType(ToggleButtons)));
    expect(loop().isSelected, [false]);
    await tester.tap(find.byTooltip('Loop playback'));
    await tester.pumpAndSettle();
    expect(loop().isSelected, [true]);
    await tester.tap(find.byTooltip('Loop playback'));
    await tester.pumpAndSettle();
    expect(loop().isSelected, [false]);
  });

  test('a recording starts with one empty filter and offers the subscribed topics', () async {
    var project = await openNewProject();
    var plant = TopicSubscription('plant/#', MqttQos.atMostOnce);
    project.topicSubscriptions
      ..add(plant)
      ..add(TopicSubscription(r'$share/line/qa/+', MqttQos.atLeastOnce, paused: true))
      ..add(TopicSubscription(r'$share/other/plant/#', MqttQos.atLeastOnce));
    await LocalStore()
        .saveLastRecorderConfig(RecorderConfig(name: 'Night shift', filters: [RecorderFilter('old/#')], durationSeconds: 60));
    var vm = RecorderViewmodel();
    addTearDown(vm.dispose);

    var config = await vm.initialConfig();
    expect(config.filters.map((f) => f.filter), ['']);
    expect(config.name, 'Recording 1');
    await recordInLibrary('Recording 1', ['a']);
    expect((await vm.initialConfig()).name, 'Recording 2');
    expect(config.durationSeconds, 60);
    // shared subscriptions are offered as their plain filter (R21), then the last recording's filters
    expect(await vm.filterSuggestions(), ['plant/#', 'qa/+', 'old/#']);
  });

  group('RecordViewmodel', () {
    RecordViewmodel viewmodel(List<RecorderFilter> filters) =>
        RecordViewmodel(RecorderConfig(name: 'r', filters: filters), MqttSettings('broker.local', 'c', 1883));

    test('reads the entered settings', () {
      var vm = viewmodel([RecorderFilter('plant/#'), RecorderFilter('plant/debug/#', exclude: true)]);
      vm.form.control(RecordViewmodel.durationField).value = '1h30m';
      vm.form.control(RecordViewmodel.maxMessagesField).value = 1000;
      vm.form.control(RecordViewmodel.maxPayloadField).value = 64;
      var config = vm.save()!;
      expect(config.filters.map((f) => '${f.filter}/${f.exclude}'), ['plant/#/false', 'plant/debug/#/true']);
      expect(config.durationSeconds, 5400);
      expect(config.maxMessages, 1000);
      expect(config.maxPayloadBytes, 64 * 1024);
      expect(config.maxBytes, RecorderConfig.defaultMaxBytes);
    });

    test('rejects shared subscriptions, bad wildcards and filters without an include', () {
      expect(viewmodel([RecorderFilter(r'$share/g/plant/#')]).save(), isNull);
      expect(viewmodel([RecorderFilter('plant/#/x')]).save(), isNull);
      expect(viewmodel([RecorderFilter('plant/#', exclude: true)]).save(), isNull);
      var badDuration = viewmodel([RecorderFilter('plant/#')]);
      badDuration.form.control(RecordViewmodel.durationField).value = 'soon';
      expect(badDuration.save(), isNull);
    });

    test('hints at covered filters and at # at the start', () {
      var vm = viewmodel([RecorderFilter('#'), RecorderFilter('plant/temp')]);
      expect(vm.coveredFilters.single.filter.filter, 'plant/temp');
      expect(vm.hasRootWildcard, isTrue);
    });
  });

  group('PlaybackOptionsViewmodel', () {
    RecordingInfo info() => RecordingInfo(
        'r.mqttrec',
        RecordingHeader(
            id: 'r', startedAt: DateTime.utc(2026), filters: [], broker: 'b', protocol: MqttSettings('b', 'c', 1).protocolVersion, clientId: 'c', appVersion: ''),
        RecordingFooter(name: 'r', durationMicros: 3600 * 1000000, topics: ['plant/a', 'plant/b']),
        0);

    test('reads range, gaps, remapping and overrides', () {
      var vm = PlaybackOptionsViewmodel(info(), PlaybackOptions(topics: ['plant/b']));
      vm.form.control(PlaybackOptionsViewmodel.speedField).value = 10.0;
      vm.form.control(PlaybackOptionsViewmodel.fromField).value = '5m';
      vm.form.control(PlaybackOptionsViewmodel.toField).value = '12m30s';
      vm.form.control(PlaybackOptionsViewmodel.gapsField).value = '10s';
      vm.form.control(PlaybackOptionsViewmodel.qosField).value = 1;
      vm.addRemap();
      var remap = vm.remaps.controls.single as dynamic;
      remap.control(PlaybackOptionsViewmodel.remapFromField).value = 'plant/';
      remap.control(PlaybackOptionsViewmodel.remapToField).value = 'test/plant/';
      expect(vm.remapPreview, ('plant/b', 'test/plant/b'));

      var options = vm.save()!;
      expect(options.speed, 10);
      expect(options.topics, ['plant/b']);
      expect(options.rangeStartMicros, 300 * 1000000);
      expect(options.rangeEndMicros, 750 * 1000000);
      expect(options.compressGapsOverMicros, 10 * 1000000);
      expect(options.qos, MqttQos.atLeastOnce);
      expect(options.remap('plant/b'), 'test/plant/b');
    });

    test('the end of the range must come after its start', () {
      var vm = PlaybackOptionsViewmodel(info(), PlaybackOptions());
      vm.form.control(PlaybackOptionsViewmodel.fromField).value = '10m';
      vm.form.control(PlaybackOptionsViewmodel.toField).value = '5m';
      expect(vm.save(), isNull);
    });
  });
}
