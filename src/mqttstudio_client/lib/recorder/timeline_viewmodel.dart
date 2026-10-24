import 'dart:io';
import 'dart:math';
import 'package:easy_localization/easy_localization.dart';
import 'package:event/event.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/analysis/recording_analysis.dart';
import 'package:mqttstudio/recorder/analysis/recording_analysis_service.dart';
import 'package:mqttstudio/recorder/engine/playback_service.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:srx_flutter/srx_flutter.dart';

class TopicDuplicates {
  final String topic;
  final int consecutive;
  final int quickRepeats;

  TopicDuplicates(this.topic, this.consecutive, this.quickRepeats);
}

// Viewmodel of the TIMELINE tab (doc/recorder-design.md §7.3, §7.5): the visible window, the selected range, gaps,
// duplicates and bookmarks of the selected recording
class TimelineViewmodel extends SrxChangeNotifier {
  static const int minWindowMicros = 10000;

  final _analysisService = GetIt.I.get<RecordingAnalysisService>();
  final _library = GetIt.I.get<RecordingLibrary>();
  final _playback = GetIt.I.get<PlaybackService>();

  RecordingInfo? _info;
  RecordingAnalysis? analysis;
  bool _disposed = false;
  // the visible part of the recording
  int viewFromMicros = 0;
  int viewToMicros = 1;
  // the range used by playback, MESSAGES and CHARTS; null = all
  int? rangeFromMicros;
  int? rangeToMicros;

  // the user picked a range on the timeline, null when it was cleared
  void Function(int? fromMicros, int? toMicros)? onRangeSelected;
  void Function(String message)? onSaveFailed;

  TimelineViewmodel() {
    _analysisService.changedEvent.subscribe(_onChanged);
    _playback.changedEvent.subscribe(_onChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    _analysisService.changedEvent.unsubscribe(_onChanged);
    _playback.changedEvent.unsubscribe(_onChanged);
    super.dispose();
  }

  RecordingInfo? get info => _info;

  int get durationMicros => max(1, _info?.footer.durationMicros ?? 1);

  bool get isAnalyzing => _info != null && analysis == null && _analysisService.isRunning(_info!);

  double get progress => _analysisService.progress;

  // shows another recording, or the same one with a new footer or range
  Future<void> show(RecordingInfo info, {int? rangeFrom, int? rangeTo}) async {
    var other = _info?.id != info.id || _info?.fileName != info.fileName;
    _info = info;
    rangeFromMicros = rangeFrom;
    rangeToMicros = rangeTo;
    if (other) {
      viewFromMicros = 0;
      viewToMicros = durationMicros;
      analysis = _analysisService.cached(info);
    }
    if (analysis == null) {
      var running = _analysisService.analysisOf(info);
      notifyListeners();
      var result = await running;
      if (_disposed || _info?.id != info.id) {
        return;
      }
      analysis = result;
    }
    notifyListeners();
  }

  // ---------- topics and lanes ----------

  List<String> get topics => _info == null ? [] : (List.of(_info!.footer.topics)..sort());

  TopicColor colorOf(String topic) =>
      RecorderRules.colorFilterOf(topic, _info?.header.filters ?? [])?.color ?? TopicColor(Colors.black);

  // the analysis finished without a result: the file could not be read
  bool get analysisFailed => _info != null && analysis == null && !_analysisService.isRunning(_info!);

  bool get isCoarse => analysis != null && !analysis!.hasExactOffsets;

  List<int> densityOf(String topic, int bins) =>
      analysis?.density(topic, viewFromMicros, viewToMicros, bins) ?? List.filled(bins, 0);

  List<RecordingMarker> get markers => analysis?.markers ?? [];

  List<Bookmark> get bookmarks => List.of(_info?.footer.bookmarks ?? <Bookmark>[])
    ..sort((a, b) => a.offsetMicros.compareTo(b.offsetMicros));

  DateTime timeAt(int offsetMicros) => _info!.header.startedAt.add(Duration(microseconds: offsetMicros));

  // where the playback of this recording is, null when it doesn't play
  int? get playheadMicros =>
      _playback.recording?.id == _info?.id && _playback.player != null ? _playback.player!.positionMicros : null;

  // ---------- zoom and pan ----------

  int get windowMicros => viewToMicros - viewFromMicros;

  void zoom(double factor, {int? aroundMicros}) {
    var anchor = aroundMicros ?? (viewFromMicros + windowMicros ~/ 2);
    var window = (windowMicros * factor).round().clamp(minWindowMicros, durationMicros);
    var share = windowMicros == 0 ? 0.5 : (anchor - viewFromMicros) / windowMicros;
    _setView((anchor - window * share).round(), window);
  }

  void pan(int deltaMicros) => _setView(viewFromMicros + deltaMicros, windowMicros);

  void showAll() => _setView(0, durationMicros);

  // centers the window on a span and zooms in enough to see it
  void reveal(int fromMicros, int toMicros) {
    var length = max(minWindowMicros, toMicros - fromMicros);
    // zoom out to three times the span when it hardly fits, else keep the zoom
    var wanted = windowMicros * 5 < length * 6 ? length * 3 : windowMicros;
    var window = min(max(wanted, minWindowMicros), durationMicros);
    _setView(fromMicros + length ~/ 2 - window ~/ 2, window);
  }

  void _setView(int from, int window) {
    var start = min(max(from, 0), max(0, durationMicros - window));
    viewFromMicros = start;
    viewToMicros = min(durationMicros, start + window);
    notifyListeners();
  }

  // ---------- range ----------

  bool get hasRange => rangeFromMicros != null || rangeToMicros != null;

  void selectRange(int fromMicros, int toMicros) {
    var from = max(0, min(fromMicros, toMicros));
    var to = min(durationMicros, max(fromMicros, toMicros));
    if (to - from < minWindowMicros) {
      return;
    }
    rangeFromMicros = from;
    rangeToMicros = to;
    notifyListeners();
    onRangeSelected?.call(from, to);
  }

  void clearRange() {
    rangeFromMicros = null;
    rangeToMicros = null;
    notifyListeners();
    onRangeSelected?.call(null, null);
  }

  // ---------- gaps and duplicates ----------

  // null = each topic's default (10 × median interval, at least 5 s)
  Duration? get gapThreshold => _analysisService.gapThreshold;

  void setGapThreshold(Duration? threshold) => _analysisService.gapThreshold = threshold;

  List<RecordingGap> gapsOf(String topic) => _info == null ? [] : _analysisService.gapsOf(_info!, topic) ?? [];

  List<RecordingGap> get gaps {
    var all = [for (var topic in topics) ...gapsOf(topic)];
    all.sort((a, b) => a.startMicros.compareTo(b.startMicros));
    return all;
  }

  List<TopicDuplicates> get duplicates {
    var result = <TopicDuplicates>[];
    for (var topic in topics) {
      var consecutive = _info!.footer.summary.perTopic[topic]?.consecutiveDuplicates ?? 0;
      var quick = analysis?.topics[topic]?.quickRepeats ?? 0;
      if (consecutive > 0 || quick > 0) {
        result.add(TopicDuplicates(topic, consecutive, quick));
      }
    }
    return result;
  }

  // ---------- bookmarks ----------

  // a bookmark can be set at the playhead, else at the start of the range
  int? get bookmarkPosition => playheadMicros ?? rangeFromMicros;

  Future<void> addBookmark(int offsetMicros, [String? label]) async {
    var list = bookmarks..add(Bookmark(offsetMicros, label ?? 'recorder.bookmark.label'.tr(args: ['${bookmarks.length + 1}'])));
    await _saveBookmarks(list..sort((a, b) => a.offsetMicros.compareTo(b.offsetMicros)));
  }

  Future<void> renameBookmark(Bookmark bookmark, String label) async {
    var list = [
      for (var b in bookmarks) b.offsetMicros == bookmark.offsetMicros && b.label == bookmark.label ? Bookmark(b.offsetMicros, label) : b
    ];
    await _saveBookmarks(list);
  }

  Future<void> deleteBookmark(Bookmark bookmark) async {
    var list = bookmarks;
    var index = list.indexWhere((b) => b.offsetMicros == bookmark.offsetMicros && b.label == bookmark.label);
    if (index >= 0) {
      list.removeAt(index);
    }
    await _saveBookmarks(list);
  }

  // bookmarks live in the footer, the messages stay as they are (R9)
  Future<void> _saveBookmarks(List<Bookmark> list) async {
    var info = _info;
    if (info == null) {
      return;
    }
    try {
      _info = await _library.updateMetadata(info, bookmarks: list);
      notifyListeners();
    } on FileSystemException catch (exc) {
      onSaveFailed?.call('timeline.bookmark.error'.tr(args: [exc.osError?.message ?? exc.message]));
    }
  }

  void _onChanged(EventArgs? _) {
    if (!_disposed) {
      notifyListeners();
    }
  }
}
