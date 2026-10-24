import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:event/event.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/recorder/analysis/recording_analysis_service.dart';
import 'package:mqttstudio/recorder/engine/playback_service.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/engine/recorder_service.dart';
import 'package:mqttstudio/recorder/engine/recording_player.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/model/recorder_config.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/model/recording_summary.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/model/anonymize_rule.dart';
import 'package:mqttstudio/recorder/tools/recording_editor.dart';
import 'package:mqttstudio/recorder/tools/recording_export.dart';
import 'package:mqttstudio/recorder/tools/recording_import.dart';
import 'package:mqttstudio/recorder/widgets/recorder_format.dart';
import 'package:mqttstudio/simulator/simulator.dart';
import 'package:srx_flutter/srx_flutter.dart';

enum SplitMode { atBookmarks, atPlayhead, byTopic }

// Viewmodel of the RECORDER tab: the recordings library, the running recording, the playback and the edits
class RecorderViewmodel extends SrxChangeNotifier {
  final _recorder = GetIt.I.get<RecorderService>();
  final _playback = GetIt.I.get<PlaybackService>();
  final _library = GetIt.I.get<RecordingLibrary>();
  final _projectManager = GetIt.I.get<ProjectManager>();
  final _mqttAdapter = GetIt.I.get<MqttAdapter>();
  final _analysis = GetIt.I.get<RecordingAnalysisService>();

  List<RecordingInfo> recordings = [];
  // the selected recording; null with liveSelected for the running one
  String? _selectedId;
  bool liveSelected = false;
  PlaybackOptions _options = PlaybackOptions();
  bool _disposed = false;

  // a dialog: something the user tried did not work
  void Function(String message)? onError;
  // a snackbar: something went wrong while running
  void Function(String message)? onWarning;
  void Function(String message)? onInfo;

  RecorderViewmodel() {
    _library.changedEvent.subscribe(_onLibraryChanged);
    _recorder.stateChangedEvent.subscribe(_onRecorderStateChanged);
    _recorder.statsChangedEvent.subscribe(_onChanged);
    _recorder.finishedEvent.subscribe(_onRecordingFinished);
    _recorder.savedEvent.subscribe(_onFlightSaved);
    _recorder.errorEvent.subscribe(_onRecorderError);
    _playback.changedEvent.subscribe(_onChanged);
    _playback.stoppedByDisconnectEvent.subscribe(_onPlaybackStoppedByDisconnect);
    _playback.finishedEvent.subscribe(_onPlaybackFinished);
    _mqttAdapter.onConnectedEvent.subscribe(_onChanged);
    _mqttAdapter.onDisconnectedEvent.subscribe(_onChanged);
    _projectManager.projectOpenedEvent.subscribe(_onProjectChanged);
    _projectManager.projectClosedEvent.subscribe(_onProjectChanged);
    _analysis.changedEvent.subscribe(_onChanged);
    liveSelected = _recorder.isRecording;
    loadRecordings();
  }

  @override
  void dispose() {
    _disposed = true;
    _library.changedEvent.unsubscribe(_onLibraryChanged);
    _recorder.stateChangedEvent.unsubscribe(_onRecorderStateChanged);
    _recorder.statsChangedEvent.unsubscribe(_onChanged);
    _recorder.finishedEvent.unsubscribe(_onRecordingFinished);
    _recorder.savedEvent.unsubscribe(_onFlightSaved);
    _recorder.errorEvent.unsubscribe(_onRecorderError);
    _playback.changedEvent.unsubscribe(_onChanged);
    _playback.stoppedByDisconnectEvent.unsubscribe(_onPlaybackStoppedByDisconnect);
    _playback.finishedEvent.unsubscribe(_onPlaybackFinished);
    _mqttAdapter.onConnectedEvent.unsubscribe(_onChanged);
    _mqttAdapter.onDisconnectedEvent.unsubscribe(_onChanged);
    _projectManager.projectOpenedEvent.unsubscribe(_onProjectChanged);
    _projectManager.projectClosedEvent.unsubscribe(_onProjectChanged);
    _analysis.changedEvent.unsubscribe(_onChanged);
    super.dispose();
  }

  // ---------- library ----------

  String? get libraryLocation => _library.location;

  bool get canOpenFolder => !kIsWeb && libraryLocation != null;

  bool get canImport => !isBusy;

  String? get defaultLibraryLocation => _library.defaultLocation;

  // the folder holds files the recorder writes, so it can't change while a recording runs
  bool get canChangeFolder => !kIsWeb && !_recorder.isRecording;

  // null goes back to the default folder. A playback of a recording in the old folder stops.
  Future<void> changeFolder(String? folder) async {
    var target = folder ?? _library.defaultLocation;
    if (target == null || target == _library.location) {
      return;
    }
    await _playback.stop();
    try {
      await _library.useFolder(target);
    } on FileSystemException catch (exc) {
      onError?.call('recordingsfolder.error'.tr(args: [target, exc.osError?.message ?? exc.message]));
      return;
    }
    await LocalStore().saveRecordingsFolder(target == _library.defaultLocation ? null : target);
    _selectedId = null;
    liveSelected = false;
    await loadRecordings();
  }

  Future<void> loadRecordings() async {
    var loaded = await _library.list();
    if (_disposed) {
      return;
    }
    recordings = loaded;
    await _keepSelectionVisible();
  }

  // ---------- projects ----------

  // false: only the recordings of the open project are listed
  bool showAllProjects = false;

  String? get projectName => _projectManager.currentProject?.name;

  // without an open project every recording is listed
  bool get isFiltered => projectName != null && !showAllProjects;

  List<RecordingInfo> get visibleRecordings =>
      isFiltered ? recordings.where((info) => info.belongsTo(projectName!)).toList() : recordings;

  Future<void> toggleAllProjects() async {
    showAllProjects = !showAllProjects;
    await _keepSelectionVisible();
  }

  bool canAssignToProject(RecordingInfo info) => projectName != null && !info.belongsTo(projectName!);

  Future<void> assignToProject(RecordingInfo info) async {
    await _guard(() => _library.updateMetadata(info, projectName: projectName));
  }

  // a recording the filter hides is not selected; the first listed one is
  Future<void> _keepSelectionVisible() async {
    var visible = visibleRecordings;
    if (_selectedId != null && !visible.any((info) => info.id == _selectedId)) {
      _selectedId = null;
    }
    if (_selectedId == null && !liveSelected && visible.isNotEmpty) {
      await select(visible.first);
    } else {
      notifyListeners();
    }
  }

  void _onProjectChanged(EventArgs? _) {
    if (!_disposed) {
      _keepSelectionVisible();
    }
  }

  RecordingInfo? get selected {
    for (var info in recordings) {
      if (info.id == _selectedId) {
        return info;
      }
    }
    return null;
  }

  Future<void> select(RecordingInfo info) async {
    _selectedId = info.id;
    liveSelected = false;
    _options = await LocalStore().getPlaybackOptions(info.id) ?? PlaybackOptions();
    if (!_disposed) {
      notifyListeners();
    }
    // for the gaps column; the timeline and the charts use the same result
    _analysis.analysisOf(info);
  }

  // the number of gaps of a topic, null until the analysis is done
  int? gapCountOf(String topic) => selected == null ? null : _analysis.gapsOf(selected!, topic)?.length;

  void selectLive() {
    liveSelected = true;
    _selectedId = null;
    notifyListeners();
  }

  Future<void> saveDetails(RecordingInfo info, String name, String notes) async {
    await _guard(() => _library.updateMetadata(info, name: name.trim(), notes: notes));
  }

  bool canDelete(RecordingInfo info) => !_playback.isPlayingRecording(info.id);

  Future<void> delete(RecordingInfo info) async {
    await _playback.release(info.id);
    try {
      await _library.delete(info);
    } on FileSystemException catch (exc) {
      onError?.call('recorder.delete.error'.tr(args: [info.name, exc.osError?.message ?? exc.message]));
    }
  }

  // .mqttrec files are copied, the other formats are read into a new recording (§8.3)
  Future<void> importRecording(ImportRequest request) => _edit('recorder.import.busy', () async {
        if (request.format == ImportFormat.mqttrec) {
          return [
            request.bytes != null
                ? await _library.importBytes(request.fileName, request.bytes!)
                : await _library.importFile(request.path!)
          ];
        }
        var bytes = request.bytes ?? await File(request.path!).readAsBytes();
        var importer = RecordingImport(_library);
        var info = await importer.importText(utf8.decode(bytes, allowMalformed: true), request.format,
            name: request.name, interval: request.interval, onProgress: _onBusyProgress);
        if (importer.skipped > 0) {
          onWarning?.call('recorder.import.skipped'.tr(args: ['${importer.skipped}']));
        }
        return [info];
      });

  Future<void> openFolder() async {
    var location = libraryLocation;
    if (location == null) {
      return;
    }
    await Directory(location).create(recursive: true);
    await Process.run('explorer', [location]);
  }

  // ---------- recording ----------

  bool get isProjectOpen => _projectManager.isProjectOpen;

  bool get isConnected => _mqttAdapter.isConnected();

  bool get isRecording => _recorder.isRecording;

  RecorderState get recorderState => _recorder.state;

  bool get canRecord => isProjectOpen && _recorder.state == RecorderState.idle;

  String get liveName => _recorder.config?.name ?? '';

  Duration get liveElapsed => _recorder.elapsed;

  int get liveMessages => _recorder.storedMessages;

  int get liveBytes => _recorder.storedBytes;

  int get liveExcluded => _recorder.excluded;

  List<RecorderFilter> get liveFilters => _recorder.filters;

  RecordingSummary? get liveSummary => _recorder.liveSummary;

  TopicColor liveColorOf(String topic) => _recorder.colorOf(topic) ?? TopicColor(Colors.black);

  // "Recording 1", or the next number not in the library yet, and one empty filter to fill in; the dialog offers
  // filterSuggestions(). Limits and options come from the last recording.
  Future<RecorderConfig> initialConfig() async {
    var last = await LocalStore().getLastRecorderConfig();
    var names = (await _library.list()).map((info) => info.name.toLowerCase()).toSet();
    var number = 1;
    while (names.contains('recorder.defaultname'.tr(args: ['$number']).toLowerCase())) {
      number++;
    }
    return RecorderConfig(
      name: 'recorder.defaultname'.tr(args: ['$number']),
      filters: [RecorderFilter('')],
      mode: last?.mode ?? RecorderMode.normal,
      startWhen: last?.startWhen,
      preRollSeconds: last?.preRollSeconds ?? 0,
      durationSeconds: last?.durationSeconds,
      maxMessages: last?.maxMessages,
      maxBytes: last?.maxBytes,
      stopWhen: last?.stopWhen,
      postRollSeconds: last?.postRollSeconds ?? 0,
      flight: last?.flight,
      maxPayloadBytes: last?.maxPayloadBytes,
      recordRetainedSnapshot: last?.recordRetainedSnapshot ?? true,
    );
  }

  // the topics subscribed in the topic viewer, paused ones too, then the filters of the last recording
  Future<List<String>> filterSuggestions() async {
    var suggestions = <String>{};
    for (var sub in _projectManager.currentProject?.topicSubscriptions ?? <TopicSubscription>[]) {
      // a shared subscription is recorded as its plain filter (R21)
      suggestions.add(TopicSubscription.topicFilterOf(sub.topic));
    }
    var last = await LocalStore().getLastRecorderConfig();
    suggestions.addAll(last?.includes.map((filter) => filter.filter).where((filter) => filter.isNotEmpty) ?? []);
    return suggestions.toList();
  }

  Future<void> startRecording(RecorderConfig config) async {
    await LocalStore().saveLastRecorderConfig(config);
    try {
      await _recorder.start(config);
      liveSelected = true;
      _selectedId = null;
      notifyListeners();
    } catch (exc) {
      onError?.call('recorder.cannotstart.error'.tr(args: [exc.toString()]));
    }
  }

  Future<void> stopRecording() => _recorder.stop();

  bool get isFlightRecorder => _recorder.isFlightRecorder && isRecording;

  bool get isWaitingForTrigger => _recorder.isWaitingForTrigger;

  bool get canSaveFlight => _recorder.canSaveFlight;

  bool get isSaveScheduled => _recorder.isSaveScheduled;

  void saveFlightRecording() => _recorder.saveFlightRecording();

  void addBookmark() => _recorder.addBookmark('recorder.bookmark.label'.tr(args: ['${_recorder.bookmarks.length + 1}']));

  // ---------- playback ----------

  PlaybackOptions get options => _options;

  bool get isSelectedPlaying => selected != null && _playback.recording?.id == selected!.id;

  PlaybackState get playbackState => isSelectedPlaying ? _playback.state : PlaybackState.stopped;

  RecordingPlayer? get player => isSelectedPlaying ? _playback.player : null;

  bool get canPlay => selected != null && isConnected && selectedTopicCount > 0 && playbackState != PlaybackState.playing;

  bool get canStep => canPlay;

  ({double rate, double peak}) get estimate =>
      selected == null ? (rate: 0.0, peak: 0.0) : RecordingPlayer.estimate(selected!, _options, maxRate: _playback.availableRate);

  bool isTopicSelected(String topic) => _options.plays(topic);

  int get selectedTopicCount =>
      selected == null ? 0 : selected!.footer.topics.where((topic) => _options.plays(topic)).length;

  Future<void> toggleTopic(String topic, bool play) async {
    var all = selected!.footer.topics;
    var chosen = (_options.topics ?? all).toSet();
    if (play) {
      chosen.add(topic);
    } else {
      chosen.remove(topic);
    }
    _options.topics = chosen.length == all.length ? null : all.where(chosen.contains).toList();
    await _saveOptions();
  }

  Future<void> setAllTopics(bool play) async {
    _options.topics = play ? null : [];
    await _saveOptions();
  }

  // true when the running recording would record what this playback publishes
  bool get playbackWouldBeRecorded {
    if (!_recorder.isRecording || selected == null) {
      return false;
    }
    return selected!.footer.topics
        .where(_options.plays)
        .any((topic) => RecorderRules.isRecorded(_options.remap(topic), _recorder.filters));
  }

  Future<void> play() async {
    try {
      await _playback.play(selected!, _options);
    } on PlaybackRateException catch (exc) {
      onError?.call('recorder.ratelimit.error'.tr(args: [exc.rate.round().toString()]));
    }
  }

  void pause() => _playback.pause();

  Future<void> stopPlayback() => _playback.stop();

  Future<void> step() => _playback.step(selected!, _options);

  Future<void> setSpeed(double speed) async {
    _options.speed = speed;
    if (isSelectedPlaying) {
      _playback.setSpeed(speed);
    }
    await _saveOptions();
  }

  Future<void> toggleLoop() async {
    _options.loop = !_options.loop;
    if (isSelectedPlaying) {
      _playback.setLoop(_options.loop);
    }
    await _saveOptions();
  }

  // the range picked on the timeline; playback, MESSAGES and CHARTS use it. Null and null is the whole recording.
  Future<void> setRange(int? fromMicros, int? toMicros) async {
    _options.rangeStartMicros = fromMicros;
    _options.rangeEndMicros = toMicros;
    await _saveOptions();
    if (isSelectedPlaying) {
      await _playback.applyOptions(selected!, _options);
    }
  }

  Future<void> applyOptions(PlaybackOptions options) async {
    _options = options;
    await _saveOptions();
    if (isSelectedPlaying) {
      await _playback.applyOptions(selected!, options);
    }
  }

  Future<void> _saveOptions() async {
    notifyListeners();
    if (selected != null) {
      await LocalStore().savePlaybackOptions(selected!.id, _options);
    }
  }

  // ---------- edits, export ----------

  late final _editor = RecordingEditor(_library, onProgress: _onBusyProgress);
  // what runs right now, e.g. an export; null when nothing runs
  String? busyLabel;
  double? busyProgress;

  bool get isBusy => busyLabel != null;

  bool get hasRange => _options.rangeStartMicros != null || _options.rangeEndMicros != null;

  bool get canEdit => selected != null && !liveSelected && !isBusy;

  bool get canTrim => canEdit && hasRange;

  bool get canKeepTopics => canEdit && selectedTopicCount > 0 && selectedTopicCount < selected!.footer.topics.length;

  int get bookmarkCount => selected?.footer.bookmarks.length ?? 0;

  int? get playheadMicros => isSelectedPlaying ? _playback.player?.positionMicros : null;

  List<RecordingInfo> get otherRecordings => recordings.where((info) => info.id != selected?.id).toList();

  Future<void> trimToRange() {
    var info = selected!;
    return _edit('recorder.edit.trim.busy', () async => [
          await _editor.trim(info, _options.rangeStartMicros ?? 0, _options.rangeEndMicros ?? info.footer.durationMicros)
        ]);
  }

  Future<void> keepSelectedTopics() {
    var info = selected!;
    var topics = info.footer.topics.where(_options.plays).toSet();
    return _edit('recorder.edit.topics.busy', () async => [await _editor.keepTopics(info, topics)]);
  }

  Future<void> renameTopics(List<TopicRemap> remaps) {
    var info = selected!;
    return _edit('recorder.edit.rename.busy', () async => [await _editor.renameTopics(info, remaps)]);
  }

  Future<void> anonymize(List<AnonymizeRule> rules, bool properties) {
    var info = selected!;
    return _edit('recorder.edit.anonymize.busy', () async => [await _editor.anonymize(info, rules, properties: properties)]);
  }

  Future<void> merge(List<RecordingInfo> others, String name) {
    var info = selected!;
    return _edit('recorder.edit.merge.busy', () async => [await _editor.merge([info, ...others], name)]);
  }

  Future<void> split(SplitMode mode) {
    var info = selected!;
    var playhead = playheadMicros;
    return _edit('recorder.edit.split.busy', () {
      switch (mode) {
        case SplitMode.atBookmarks:
          return _editor.splitAt(info, info.footer.bookmarks.map((bookmark) => bookmark.offsetMicros).toList());
        case SplitMode.atPlayhead:
          return _editor.splitAt(info, [playhead ?? 0]);
        case SplitMode.byTopic:
          return _editor.splitByTopic(info);
      }
    });
  }

  // JSON lines and CSV are written while reading; in the browser they are collected and downloaded
  Future<void> export(ExportRequest request) async {
    var info = selected!;
    var extension = RecordingExport.extensionOf(request.format);
    var fileName = '${info.name}.$extension';
    String? path;
    if (!kIsWeb) {
      path = await FilePicker.saveFile(
          dialogTitle: 'recorder.export.title'.tr(), fileName: fileName, type: FileType.custom, allowedExtensions: [extension]);
      if (path == null) {
        return;
      }
    }
    await _busy('recorder.export.busy', () async {
      if (request.format == ExportFormat.mqttrec) {
        var file = await _library.store.open(info.fileName);
        Uint8List bytes;
        try {
          bytes = await file.read(0, await file.length());
        } finally {
          await file.close();
        }
        await _saveBytes(path, fileName, extension, bytes);
        return;
      }
      var reader = await _library.open(info);
      try {
        var topics = request.onlySelectedTopics ? info.footer.topics.where(_options.plays).toSet() : null;
        var from = request.onlyRange ? _options.rangeStartMicros : null;
        var to = request.onlyRange ? _options.rangeEndMicros : null;
        if (path == null) {
          var text = StringBuffer();
          await RecordingExport.writeText(reader, text,
              format: request.format, topics: topics, fromMicros: from, toMicros: to, columns: request.columns);
          await _saveBytes(null, fileName, extension, Uint8List.fromList(utf8.encode(text.toString())));
        } else {
          var sink = File(path).openWrite();
          try {
            await RecordingExport.writeText(reader, sink,
                format: request.format, topics: topics, fromMicros: from, toMicros: to, columns: request.columns);
          } finally {
            await sink.close();
          }
        }
      } finally {
        await reader.close();
      }
      onInfo?.call('recorder.exported.info'.tr(args: [path ?? fileName]));
    });
  }

  Future<void> _saveBytes(String? path, String fileName, String extension, Uint8List bytes) async {
    if (path != null) {
      await File(path).writeAsBytes(bytes);
    } else {
      await FilePicker.saveFile(
          fileName: fileName, type: FileType.custom, allowedExtensions: [extension], bytes: bytes);
    }
  }

  // runs an edit; the first recording it wrote is selected afterwards
  Future<void> _edit(String busyKey, Future<List<RecordingInfo>> Function() action) => _busy(busyKey, () async {
        var created = await action();
        await loadRecordings();
        var first = recordings.where((info) => info.id == created.first.id).firstOrNull;
        if (first != null) {
          await select(first);
        }
        onInfo?.call('recorder.edited.info'.tr(args: [created.map((info) => info.name).join(', ')]));
      });

  Future<void> _busy(String busyKey, Future<void> Function() action) async {
    busyLabel = busyKey.tr();
    busyProgress = null;
    notifyListeners();
    try {
      await action();
    } catch (exc) {
      onError?.call('recorder.edit.error'.tr(args: [exc.toString()]));
    } finally {
      busyLabel = null;
      busyProgress = null;
      _onChanged(null);
    }
  }

  void _onBusyProgress(double progress) {
    busyProgress = progress;
    _onChanged(null);
  }

  // ---------- simulation ----------

  bool get canAddToSimulation => isProjectOpen && !liveSelected && selected != null;

  // a recorded device that plays the selected recording with its playback options (R4); returns its name
  String addToSimulation() => GetIt.I.get<Simulator>().addRecordedDevice(selected!, _options).name;

  // ---------- events ----------

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (exc) {
      onError?.call(exc.toString());
    }
  }

  void _onChanged(EventArgs? _) {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _onLibraryChanged(EventArgs? _) => loadRecordings();

  // the session that just ended was a flight recorder
  bool get _wasFlight => _recorder.config?.isFlightRecorder ?? false;

  void _onRecorderStateChanged(EventArgs? _) {
    if (_recorder.isRecording && _selectedId == null) {
      liveSelected = true;
    }
    _onChanged(null);
  }

  void _onFlightSaved(RecordingFinishedEventArgs? args) {
    var info = args?.info;
    if (info != null) {
      onInfo?.call('recorder.flightsaved.info'.tr(args: [info.name, RecorderFormat.count(info.footer.summary.messages)]));
    }
  }

  void _onRecordingFinished(RecordingFinishedEventArgs? args) {
    var info = args?.info;
    if (info == null) {
      liveSelected = false;
      if (args != null && args.reason != RecordingStopReason.writeError) {
        onInfo?.call(_recorder.flightSaves > 0 || _wasFlight
            ? 'recorder.flightstopped.info'.tr(args: ['${_recorder.flightSaves}'])
            : 'recorder.nothingrecorded.info'.tr());
      }
      _onChanged(null);
      return;
    }
    if (liveSelected) {
      liveSelected = false;
      _selectedId = info.id;
      _library.list().then((loaded) {
        if (!_disposed) {
          recordings = loaded;
          select(info);
        }
      });
    }
    var reason = args!.reason == RecordingStopReason.user ? '' : 'recorder.stopreason.${args.reason.name}'.tr();
    onInfo?.call('${'recorder.saved.info'.tr(args: [info.name, RecorderFormat.count(info.footer.summary.messages)])} $reason'
        .trim());
  }

  void _onRecorderError(RecorderErrorEventArgs? args) => onWarning?.call('recorder.error'.tr(args: [args?.message ?? '']));

  void _onPlaybackStoppedByDisconnect(EventArgs? _) => onWarning?.call('recorder.playbackdisconnected.error'.tr());

  void _onPlaybackFinished(EventArgs? _) => onInfo?.call('recorder.playbackfinished.info'.tr());
}
