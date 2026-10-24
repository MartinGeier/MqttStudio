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
import 'package:mqttstudio/recorder/engine/playback_service.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/engine/recorder_service.dart';
import 'package:mqttstudio/recorder/engine/recording_player.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/model/recorder_config.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/model/recording_summary.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/widgets/recorder_format.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the RECORDER tab: the recordings library, the running recording and the playback
class RecorderViewmodel extends SrxChangeNotifier {
  final _recorder = GetIt.I.get<RecorderService>();
  final _playback = GetIt.I.get<PlaybackService>();
  final _library = GetIt.I.get<RecordingLibrary>();
  final _projectManager = GetIt.I.get<ProjectManager>();
  final _mqttAdapter = GetIt.I.get<MqttAdapter>();

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
    _recorder.errorEvent.subscribe(_onRecorderError);
    _playback.changedEvent.subscribe(_onChanged);
    _playback.stoppedByDisconnectEvent.subscribe(_onPlaybackStoppedByDisconnect);
    _playback.finishedEvent.subscribe(_onPlaybackFinished);
    _mqttAdapter.onConnectedEvent.subscribe(_onChanged);
    _mqttAdapter.onDisconnectedEvent.subscribe(_onChanged);
    _projectManager.projectOpenedEvent.subscribe(_onChanged);
    _projectManager.projectClosedEvent.subscribe(_onChanged);
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
    _recorder.errorEvent.unsubscribe(_onRecorderError);
    _playback.changedEvent.unsubscribe(_onChanged);
    _playback.stoppedByDisconnectEvent.unsubscribe(_onPlaybackStoppedByDisconnect);
    _playback.finishedEvent.unsubscribe(_onPlaybackFinished);
    _mqttAdapter.onConnectedEvent.unsubscribe(_onChanged);
    _mqttAdapter.onDisconnectedEvent.unsubscribe(_onChanged);
    _projectManager.projectOpenedEvent.unsubscribe(_onChanged);
    _projectManager.projectClosedEvent.unsubscribe(_onChanged);
    super.dispose();
  }

  // ---------- library ----------

  String? get libraryLocation => _library.location;

  bool get canOpenFolder => !kIsWeb && libraryLocation != null;

  bool get canImport => !kIsWeb;

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
    if (_selectedId != null && selected == null) {
      _selectedId = null;
    }
    if (_selectedId == null && !liveSelected && recordings.isNotEmpty) {
      await select(recordings.first);
    } else {
      notifyListeners();
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
  }

  void selectLive() {
    liveSelected = true;
    _selectedId = null;
    notifyListeners();
  }

  Future<void> rename(RecordingInfo info, String name) async {
    await _guard(() => _library.updateMetadata(info, name: name.trim()));
  }

  Future<void> saveNotes(RecordingInfo info, String notes) async {
    await _guard(() => _library.updateMetadata(info, notes: notes));
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

  Future<void> importRecording() async {
    var result = await FilePicker.pickFiles(
        dialogTitle: 'recorder.import.title'.tr(), type: FileType.custom, allowedExtensions: ['mqttrec']);
    var path = result?.files.single.path;
    if (path == null) {
      return;
    }
    await _guard(() async {
      var info = await _library.importFile(path);
      await loadRecordings();
      await select(info);
    });
  }

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

  // The filters are the topics subscribed in the topic viewer, paused ones too, with their colors. Without
  // subscriptions they are the ones of the last recording, else everything. Name and limits come from the last
  // recording.
  Future<RecorderConfig> initialConfig() async {
    var last = await LocalStore().getLastRecorderConfig();
    var subscribed = <String, RecorderFilter>{};
    for (var sub in _projectManager.currentProject?.topicSubscriptions ?? <TopicSubscription>[]) {
      // a shared subscription is recorded as its plain filter (R21)
      var filter = TopicSubscription.topicFilterOf(sub.topic);
      subscribed.putIfAbsent(filter, () => RecorderFilter(filter, color: sub.color));
    }
    var filters = subscribed.isNotEmpty ? subscribed.values.toList() : last?.filters ?? [RecorderFilter('#')];
    return RecorderConfig(
      name: last?.name ?? _projectManager.currentProject?.name ?? 'Recording',
      filters: filters,
      durationSeconds: last?.durationSeconds,
      maxMessages: last?.maxMessages,
      maxBytes: last?.maxBytes,
      maxPayloadBytes: last?.maxPayloadBytes,
      recordRetainedSnapshot: last?.recordRetainedSnapshot ?? true,
    );
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

  void _onRecorderStateChanged(EventArgs? _) {
    if (_recorder.isRecording && _selectedId == null) {
      liveSelected = true;
    }
    _onChanged(null);
  }

  void _onRecordingFinished(RecordingFinishedEventArgs? args) {
    var info = args?.info;
    if (info == null) {
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
