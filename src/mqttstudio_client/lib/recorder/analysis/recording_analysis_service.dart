import 'package:event/event.dart';
import 'package:mqttstudio/recorder/analysis/recording_analysis.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';

// Analyzes recordings for the recorder tab and keeps the last few results (GetIt singleton). One analysis runs at a
// time; asking for another recording cancels the running one.
class RecordingAnalysisService {
  static const int _cacheSize = 3;

  final RecordingLibrary _library;
  final Map<String, RecordingAnalysis> _cache = {};
  String? _runningKey;
  // null = each topic's default (10 × median interval, at least 5 s); shared by the overview and the timeline
  Duration? _gapThreshold;
  Future<RecordingAnalysis?>? _running;
  double _progress = 0;
  // the progress of the running analysis changed, or one finished
  final changedEvent = Event();

  RecordingAnalysisService(this._library);

  // the size is part of the key: an edited footer keeps the messages, a recovered file changes them
  static String _keyOf(RecordingInfo info) => '${info.id}|${info.fileName}|${info.footer.summary.messages}';

  RecordingAnalysis? cached(RecordingInfo info) => _cache[_keyOf(info)];

  bool isRunning(RecordingInfo info) => _runningKey == _keyOf(info);

  double get progress => _progress;

  Duration? get gapThreshold => _gapThreshold;

  set gapThreshold(Duration? value) {
    _gapThreshold = value;
    changedEvent.broadcast();
  }

  // the gaps of a topic with the current threshold, null before the analysis is done
  List<RecordingGap>? gapsOf(RecordingInfo info, String topic) =>
      cached(info)?.gapsOf(topic, thresholdOf(info, topic));

  Duration thresholdOf(RecordingInfo info, String topic) =>
      _gapThreshold ?? RecordingAnalysis.defaultGapThreshold(info.footer.summary.perTopic[topic]);

  // null when it was cancelled or the recording could not be read
  Future<RecordingAnalysis?> analysisOf(RecordingInfo info) {
    var key = _keyOf(info);
    var cached = _cache[key];
    if (cached != null) {
      return Future.value(cached);
    }
    if (_runningKey == key) {
      return _running!;
    }
    _runningKey = key;
    _progress = 0;
    _running = _analyze(info, key);
    return _running!;
  }

  void cancel() {
    _runningKey = null;
    _running = null;
  }

  Future<RecordingAnalysis?> _analyze(RecordingInfo info, String key) async {
    RecordingAnalysis? analysis;
    try {
      var reader = await _library.open(info);
      try {
        analysis = await RecordingAnalyzer.analyze(reader, isCancelled: () => _runningKey != key, onProgress: (progress) {
          _progress = progress;
          changedEvent.broadcast();
        });
      } finally {
        await reader.close();
      }
    } on Exception {
      analysis = null;
    }
    if (_runningKey == key) {
      _runningKey = null;
      _running = null;
    }
    if (analysis != null) {
      _cache.remove(key);
      _cache[key] = analysis;
      while (_cache.length > _cacheSize) {
        _cache.remove(_cache.keys.first);
      }
    }
    changedEvent.broadcast();
    return analysis;
  }
}
