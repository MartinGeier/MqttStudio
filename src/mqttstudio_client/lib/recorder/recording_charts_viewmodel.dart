import 'package:event/event.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:get_it/get_it.dart';
import 'package:latlong2/latlong.dart';
import 'package:mqttstudio/common/utils/json_path.dart';
import 'package:mqttstudio/common/utils/payload_utils.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/analysis/recording_analysis_service.dart';
import 'package:mqttstudio/recorder/analysis/recording_values.dart';
import 'package:mqttstudio/recorder/model/recording_summary.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

enum ChartMode { numbers, positions }

// Viewmodel of the CHARTS tab (doc/recorder-design.md §7.4): a value of one topic over the selected range, the
// topic's interval histogram, and positions as a track on the map
class RecordingChartsViewmodel extends SrxChangeNotifier {
  static const String pathField = 'path';

  final _library = GetIt.I.get<RecordingLibrary>();
  final _analysisService = GetIt.I.get<RecordingAnalysisService>();

  late final FormGroup form = FormGroup({
    pathField: FormControl<String>(validators: [Validators.delegate(_validatePath)]),
  });

  RecordingInfo? _info;
  int? _rangeFrom;
  int? _rangeTo;
  String? topic;
  ChartMode mode = ChartMode.numbers;
  ValueSelector selector = const ValueSelector.payload();
  JsonPath? latitude;
  JsonPath? longitude;
  ValueSeries? series;
  List<LatLng>? track;
  String? _loadingKey;
  String? _loadedKey;
  bool _disposed = false;

  RecordingChartsViewmodel() {
    _analysisService.changedEvent.subscribe(_onAnalysisChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    _loadingKey = null;
    _analysisService.changedEvent.unsubscribe(_onAnalysisChanged);
    super.dispose();
  }

  static Map<String, dynamic>? _validatePath(AbstractControl<dynamic> control) {
    var value = (control.value as String?)?.trim() ?? '';
    if (value.isEmpty || JsonPath.tryParse(value) != null) {
      return null;
    }
    return {'jsonpath': true};
  }

  RecordingInfo? get info => _info;

  bool get isLoading => _loadingKey != null;

  int get rangeFromMicros => _rangeFrom ?? 0;

  int get rangeToMicros => _rangeTo ?? (_info?.footer.durationMicros ?? 0);

  List<String> get topics => _info == null ? [] : (List.of(_info!.footer.topics)..sort());

  TopicSummary? get topicSummary => topic == null ? null : _info?.footer.summary.perTopic[topic];

  // the JSON paths with numbers the analysis found in the topic's payloads
  List<JsonPath> get jsonPaths {
    var analysis = _info == null ? null : _analysisService.cached(_info!);
    return analysis?.topics[topic]?.jsonNumbers.toList() ?? [];
  }

  bool get topicHasNumbers => (topicSummary?.kinds[PayloadType.Number.name] ?? 0) > 0;

  bool get topicHasCoordinates => (topicSummary?.kinds[PayloadType.GnssCoordinates.name] ?? 0) > 0;

  // the selectable values: the payload when it is a number, the discovered paths, and a typed one
  List<ValueSelector> get selectors {
    var list = <ValueSelector>[if (topicHasNumbers || jsonPaths.isEmpty) const ValueSelector.payload()];
    list.addAll(jsonPaths.map(ValueSelector.json));
    if (!list.contains(selector)) {
      list.add(selector);
    }
    return list;
  }

  List<int> get histogram => topicSummary?.histogram ?? [];

  TopicColor colorOf(String topic) =>
      RecorderRules.colorFilterOf(topic, _info?.header.filters ?? [])?.color ?? TopicColor(Colors.black);

  DateTime timeAt(int offsetMicros) => _info!.header.startedAt.add(Duration(microseconds: offsetMicros)).toLocal();

  Future<void> show(RecordingInfo info, {int? rangeFrom, int? rangeTo}) async {
    var other = _info?.id != info.id || _info?.fileName != info.fileName;
    _info = info;
    _rangeFrom = rangeFrom;
    _rangeTo = rangeTo;
    if (other) {
      topic = _defaultTopic(info);
      selector = const ValueSelector.payload();
      latitude = null;
      longitude = null;
      series = null;
      track = null;
      _loadedKey = null;
      _pickDefaults();
      _analysisService.analysisOf(info);
    }
    await _load();
  }

  Future<void> setTopic(String value) async {
    topic = value;
    selector = const ValueSelector.payload();
    latitude = null;
    longitude = null;
    _pickDefaults();
    await _load();
  }

  Future<void> setMode(ChartMode value) async {
    mode = value;
    await _load();
  }

  Future<void> setSelector(ValueSelector value) async {
    selector = value;
    await _load();
  }

  // the typed JSON path from the form
  Future<void> applyPath() async {
    var control = form.control(pathField);
    control.markAsTouched();
    var text = (control.value as String?)?.trim() ?? '';
    if (!control.valid || text.isEmpty) {
      return;
    }
    await setSelector(ValueSelector.json(JsonPath.parse(text)));
  }

  Future<void> setLatitude(JsonPath? path) async {
    latitude = path;
    await _load();
  }

  Future<void> setLongitude(JsonPath? path) async {
    longitude = path;
    await _load();
  }

  bool get canShowTrack => topicHasCoordinates || (latitude != null && longitude != null);

  String? _defaultTopic(RecordingInfo info) {
    var perTopic = info.footer.summary.perTopic;
    var sorted = List.of(info.footer.topics)..sort();
    return sorted.where((t) => (perTopic[t]?.kinds[PayloadType.Number.name] ?? 0) > 0).firstOrNull ??
        sorted.where((t) => (perTopic[t]?.kinds[PayloadType.Json.name] ?? 0) > 0).firstOrNull ??
        sorted.firstOrNull;
  }

  void _pickDefaults() {
    if (!topicHasNumbers && jsonPaths.isNotEmpty) {
      selector = ValueSelector.json(jsonPaths.first);
    }
    if (latitude == null && longitude == null) {
      latitude = jsonPaths.where((path) => _lastName(path).startsWith('lat')).firstOrNull;
      longitude = jsonPaths.where((path) => _lastName(path).startsWith('lon') || _lastName(path) == 'lng').firstOrNull;
    }
  }

  static String _lastName(JsonPath path) {
    var last = path.segments.lastOrNull;
    return last is String ? last.toLowerCase() : '';
  }

  Future<void> _load() async {
    var info = _info;
    var topic = this.topic;
    if (info == null || topic == null) {
      notifyListeners();
      return;
    }
    var key = '${info.id}|$topic|$mode|$selector|$latitude|$longitude|$_rangeFrom|$_rangeTo';
    if (key == _loadedKey || key == _loadingKey) {
      notifyListeners();
      return;
    }
    _loadingKey = key;
    notifyListeners();
    ValueSeries? loadedSeries;
    List<LatLng>? loadedTrack;
    var completed = false;
    try {
      var reader = await _library.open(info);
      try {
        bool cancelled() => _loadingKey != key;
        if (mode == ChartMode.numbers) {
          loadedSeries = await RecordingValues.load(reader, topic, selector,
              fromMicros: _rangeFrom, toMicros: _rangeTo, isCancelled: cancelled);
          completed = loadedSeries != null;
        } else if (canShowTrack) {
          loadedTrack = await RecordingValues.track(reader, topic,
              latitude: topicHasCoordinates ? null : latitude,
              longitude: topicHasCoordinates ? null : longitude,
              fromMicros: _rangeFrom,
              toMicros: _rangeTo,
              isCancelled: cancelled);
          completed = loadedTrack != null;
        } else {
          completed = true;
        }
      } finally {
        await reader.close();
      }
    } on Exception {
      completed = true;
    }
    if (_disposed || _loadingKey != key) {
      return;
    }
    _loadingKey = null;
    if (completed) {
      _loadedKey = key;
      series = loadedSeries;
      track = loadedTrack;
    }
    notifyListeners();
  }

  void _onAnalysisChanged(EventArgs? _) {
    if (_disposed || _info == null || _analysisService.cached(_info!) == null) {
      return;
    }
    // the JSON paths are known now; a JSON topic shows its first number instead of nothing
    if (selector.path == null && !topicHasNumbers && jsonPaths.isNotEmpty) {
      _pickDefaults();
      _load();
      return;
    }
    notifyListeners();
  }
}
