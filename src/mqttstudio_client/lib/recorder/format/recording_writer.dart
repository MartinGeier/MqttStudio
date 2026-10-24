import 'dart:math';
import 'dart:typed_data';
import 'package:mqttstudio/recorder/format/record_codec.dart';
import 'package:mqttstudio/recorder/format/summary_builder.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/model/recording_summary.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';

// Appends messages to a new recording and writes its footer when it is finished. Records are collected in memory;
// the owner calls flush regularly (the recorder every second), so a crash loses at most what was not flushed.
class RecordingWriter {
  static const int seekEvery = 1000;
  // flush earlier when this much is waiting
  static const int flushThreshold = 256 * 1024;

  final RecordingFile file;
  final RecordingHeader header;
  final SummaryBuilder _summary = SummaryBuilder();
  final Map<String, int> _topicIndex = {};
  final List<String> _topics = [];
  final List<SeekEntry> _seekIndex = [];
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int _length = 0;
  int _lastOffsetMicros = 0;
  bool _finished = false;

  RecordingWriter._(this.file, this.header);

  static Future<RecordingWriter> start(RecordingFile file, RecordingHeader header) async {
    var writer = RecordingWriter._(file, header);
    writer._write(RecordCodec.encodeStart(header.toJson()));
    await writer.flush();
    return writer;
  }

  // the file length once everything is flushed
  int get length => _length;

  int get messageCount => _summary.summary.messages;

  // live statistics, also while recording
  RecordingSummary get summary => _summary.summary;

  List<String> get topics => List.unmodifiable(_topics);

  int get lastOffsetMicros => _lastOffsetMicros;

  bool get needsFlush => _buffer.length >= flushThreshold;

  void addMessage(RecordedMessage message) {
    _checkOpen();
    var index = _topicIndex[message.topic];
    if (index == null) {
      index = _topics.length;
      _topics.add(message.topic);
      _topicIndex[message.topic] = index;
      _write(RecordCodec.encodeTopic(index, message.topic));
    }
    if (messageCount % seekEvery == 0) {
      _seekIndex.add(SeekEntry(message.offsetMicros, _length, messageCount));
    }
    var properties = RecordedProperties.hasContent(message.properties) ? RecordedProperties.toJson(message.properties!) : null;
    _write(RecordCodec.encodeMessage(message, index, properties));
    _summary.add(message);
    _lastOffsetMicros = max(_lastOffsetMicros, message.offsetMicros);
  }

  void addMarker(RecordingMarker marker) {
    _checkOpen();
    _write(RecordCodec.encodeMarker(marker));
    _summary.addMarker(marker);
  }

  Future<void> flush() async {
    if (_buffer.isEmpty) {
      return;
    }
    await file.append(_buffer.takeBytes());
  }

  // writes the footer and the trailer and closes the file
  Future<RecordingFooter> finish(
      {required String name, required int durationMicros, String notes = '', List<Bookmark>? bookmarks, bool recovered = false}) async {
    _checkOpen();
    var footer = RecordingFooter(
      name: name,
      notes: notes,
      durationMicros: max(durationMicros, _lastOffsetMicros),
      recovered: recovered,
      bookmarks: bookmarks,
      topics: List.of(_topics),
      summary: summary,
      seekIndex: _seekIndex,
    );
    var footerPosition = _length;
    _write(RecordCodec.encodeFooter(footer.toJson()));
    _write(RecordCodec.encodeTrailer(footerPosition));
    _finished = true;
    await flush();
    await file.close();
    return footer;
  }

  // closes the file without a footer, e.g. after a write error. Opening it later recovers it.
  Future<void> abandon() async {
    _finished = true;
    try {
      await flush();
    } finally {
      await file.close();
    }
  }

  void _write(Uint8List bytes) {
    _buffer.add(bytes);
    _length += bytes.length;
  }

  void _checkOpen() {
    if (_finished) {
      throw StateError('The recording ${file.name} is already finished');
    }
  }
}
