import 'dart:collection';
import 'package:mqttstudio/recorder/model/recorded_message.dart';

// The messages and markers of the last `window` in memory, for the pre-roll of a start trigger and for the flight
// recorder (doc/recorder-design.md §5.4, §5.5). When maxBytes is reached first, the oldest entries go and the window
// gets shorter.
class RecordingRing {
  // a guess for the topic, the properties and the object itself
  static const int _overheadBytes = 96;

  final int windowMicros;
  final int maxBytes;
  // RecordedMessage or RecordingMarker, oldest first
  final ListQueue<Object> _entries = ListQueue();
  int _bytes = 0;
  int _messages = 0;
  // the memory limit dropped messages that were still in the window
  bool memoryLimited = false;

  RecordingRing({required this.windowMicros, required this.maxBytes});

  int get bytes => _bytes;

  int get messageCount => _messages;

  bool get isEmpty => _entries.isEmpty;

  int? get firstOffsetMicros => _entries.isEmpty ? null : offsetOf(_entries.first);

  static int offsetOf(Object entry) => entry is RecordedMessage ? entry.offsetMicros : (entry as RecordingMarker).offsetMicros;

  static int sizeOf(Object entry) =>
      entry is RecordedMessage ? entry.payload.length + entry.topic.length + _overheadBytes : _overheadBytes;

  void add(Object entry) {
    _entries.add(entry);
    _bytes += sizeOf(entry);
    if (entry is RecordedMessage) {
      _messages++;
    }
    trim(offsetOf(entry));
  }

  // drops what is older than the window at nowMicros, and the oldest entries while over the memory limit
  void trim(int nowMicros) {
    while (_entries.isNotEmpty) {
      var first = _entries.first;
      var tooOld = offsetOf(first) < nowMicros - windowMicros;
      var tooBig = _bytes > maxBytes;
      if (!tooOld && !tooBig) {
        break;
      }
      if (tooBig && !tooOld) {
        memoryLimited = true;
      }
      _removeFirst();
    }
  }

  // how much time the ring holds right now
  int spanMicros(int nowMicros) => _entries.isEmpty ? 0 : nowMicros - offsetOf(_entries.first);

  List<Object> toList() => List.of(_entries);

  // hands over all entries and empties the ring
  List<Object> drain() {
    var all = List.of(_entries);
    clear();
    return all;
  }

  void clear() {
    _entries.clear();
    _bytes = 0;
    _messages = 0;
  }

  void _removeFirst() {
    var entry = _entries.removeFirst();
    _bytes -= sizeOf(entry);
    if (entry is RecordedMessage) {
      _messages--;
    }
  }
}
