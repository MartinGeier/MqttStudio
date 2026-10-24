import 'package:get_it/get_it.dart';
import 'package:mqttstudio/recorder/analysis/recording_message_source.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the MESSAGES tab: loads the selected range of a recording into a RecordingMessageSource, which the
// topic viewer widgets show through their own MessageViewerViewmodel (doc/recorder-design.md §7.2)
class RecordingMessagesViewmodel extends SrxChangeNotifier {
  final _library = GetIt.I.get<RecordingLibrary>();
  final RecordingMessageSource source = RecordingMessageSource();

  String? _loadedKey;
  String? _loadingKey;
  bool failed = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _loadingKey = null;
    super.dispose();
  }

  bool get isLoading => _loadingKey != null;

  bool get isCut => source.isCut;

  int get loadedCount => source.loadedCount;

  int get messagesInRange => source.messagesInRange;

  Future<void> show(RecordingInfo info, {int? rangeFrom, int? rangeTo}) async {
    var key = '${info.id}|${info.fileName}|$rangeFrom|$rangeTo';
    if (key == _loadedKey || key == _loadingKey) {
      return;
    }
    _loadingKey = key;
    failed = false;
    notifyListeners();
    var loaded = false;
    try {
      var reader = await _library.open(info);
      try {
        loaded = await source.load(reader, fromMicros: rangeFrom, toMicros: rangeTo, isCancelled: () => _loadingKey != key);
      } finally {
        await reader.close();
      }
    } on Exception {
      failed = _loadingKey == key;
    }
    if (_disposed || _loadingKey != key) {
      return;
    }
    _loadingKey = null;
    _loadedKey = loaded ? key : null;
    if (!loaded) {
      source.clear();
    }
    notifyListeners();
  }

  void toggleFilter(String filter) {
    source.toggleFilter(filter);
    notifyListeners();
  }
}
