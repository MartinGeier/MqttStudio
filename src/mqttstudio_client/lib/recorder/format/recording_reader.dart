import 'dart:math';
import 'dart:typed_data';
import 'package:mqttstudio/recorder/format/record_codec.dart';
import 'package:mqttstudio/recorder/format/summary_builder.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';

sealed class RecordingEntry {
  // file position of the record
  final int position;

  RecordingEntry(this.position);
}

class MessageEntry extends RecordingEntry {
  final RecordedMessage message;

  MessageEntry(super.position, this.message);
}

class MarkerEntry extends RecordingEntry {
  final RecordingMarker marker;

  MarkerEntry(super.position, this.marker);
}

class _RawRecord {
  final int type;
  final Uint8List body;
  final int position;

  _RawRecord(this.type, this.body, this.position);
}

// Reads the records between two file positions in blocks. Stops at the end, at a record that runs past the end or
// at a checksum mismatch; lastGoodPosition is then where the intact part of the file ends.
class _RecordScanner {
  static const int blockSize = 1024 * 1024;

  final RecordingFile file;
  final int end;
  int position;
  int lastGoodPosition;
  bool damaged = false;
  Uint8List _block = Uint8List(0);
  int _blockStart = 0;

  _RecordScanner(this.file, this.position, this.end) : lastGoodPosition = position;

  Future<_RawRecord?> next() async {
    if (position + 5 > end) {
      damaged = position != end;
      return null;
    }
    var head = await _bytes(position, 5);
    var bodyLength = ByteData.sublistView(head).getUint32(1, Endian.little);
    var total = RecordCodec.recordOverhead + bodyLength;
    if (bodyLength > RecordCodec.maxBodyLength || position + total > end) {
      damaged = true;
      return null;
    }
    var record = await _bytes(position, total);
    var body = Uint8List.sublistView(record, 5, 5 + bodyLength);
    var crc = ByteData.sublistView(record).getUint32(5 + bodyLength, Endian.little);
    if (crc != RecordCodec.crcOf(Uint8List.sublistView(record, 0, 5), body)) {
      damaged = true;
      return null;
    }
    var raw = _RawRecord(record[0], body, position);
    position += total;
    lastGoodPosition = position;
    return raw;
  }

  Future<Uint8List> _bytes(int start, int count) async {
    if (start < _blockStart || start + count > _blockStart + _block.length) {
      _blockStart = start;
      _block = await file.read(start, min(max(count, blockSize), end - start));
    }
    return Uint8List.sublistView(_block, start - _blockStart, start - _blockStart + count);
  }
}

// Opens a recording: its header, and its footer when the recording was finished
class RecordingReader {
  final RecordingFile file;
  final RecordingHeader header;
  // where the first record starts
  final int dataStart;
  RecordingFooter? footer;
  int? footerPosition;

  RecordingReader._(this.file, this.header, this.dataStart);

  // throws FormatException if the file is no recording
  static Future<RecordingReader> open(RecordingFile file) async {
    var prefix = await file.read(0, RecordCodec.prefixLength);
    var headerLength = RecordCodec.decodePrefix(prefix);
    if (headerLength == null) {
      throw FormatException('${file.name} is not an MQTT Studio recording');
    }
    var header = RecordingHeader.fromJson(RecordCodec.decodeJson(await file.read(RecordCodec.prefixLength, headerLength)));
    var reader = RecordingReader._(file, header, RecordCodec.prefixLength + headerLength);
    await reader._readFooter();
    return reader;
  }

  // false when the recording was not finished, e.g. after a crash; recover() repairs it
  bool get isComplete => footer != null;

  Future<void> _readFooter() async {
    var length = await file.length();
    if (length < dataStart + RecordCodec.trailerLength) {
      return;
    }
    var position = RecordCodec.decodeTrailer(await file.read(length - RecordCodec.trailerLength, RecordCodec.trailerLength));
    if (position == null || position < dataStart) {
      return;
    }
    var scanner = _RecordScanner(file, position, length - RecordCodec.trailerLength);
    var record = await scanner.next();
    if (record == null || record.type != RecordCodec.typeFooter) {
      return;
    }
    footer = RecordingFooter.fromJson(RecordCodec.decodeJson(record.body));
    footerPosition = position;
  }

  // the messages and markers in file order, from the given position (a seek index entry) on
  Stream<RecordingEntry> entries({int? from}) async* {
    var cursor = this.cursor(from: from);
    while (true) {
      var entry = await cursor.next();
      if (entry == null) {
        return;
      }
      yield entry;
    }
  }

  // reads the entries one by one on request, e.g. for playback
  RecordingCursor cursor({int? from}) => RecordingCursor._(this, from ?? dataStart);

  // Repairs an unfinished recording: keeps every intact record, cuts the rest, adds a "recovered" marker and writes
  // the footer from one pass over the messages.
  Future<RecordingFooter> recover(String name) async {
    var length = await file.length();
    var scanner = _RecordScanner(file, dataStart, length);
    var summary = SummaryBuilder();
    var topics = <String>[];
    var seekIndex = <SeekEntry>[];
    var lastOffset = 0;
    while (true) {
      var record = await scanner.next();
      if (record == null) {
        break;
      }
      switch (record.type) {
        case RecordCodec.typeTopic:
          var topic = RecordCodec.decodeTopic(record.body);
          while (topics.length <= topic.topicIndex) {
            topics.add('');
          }
          topics[topic.topicIndex] = topic.topic;
        case RecordCodec.typeMessage:
          var message = RecordCodec.decodeMessage(record.body, (index) => topics[index]);
          if (summary.summary.messages % 1000 == 0) {
            seekIndex.add(SeekEntry(message.offsetMicros, record.position, summary.summary.messages));
          }
          summary.add(message);
          lastOffset = max(lastOffset, message.offsetMicros);
        case RecordCodec.typeMarker:
          var marker = RecordCodec.decodeMarker(record.body);
          summary.addMarker(marker);
          lastOffset = max(lastOffset, marker.offsetMicros);
      }
    }
    await file.truncate(scanner.lastGoodPosition);
    var marker = RecordingMarker(lastOffset, RecordingMarker.recovered);
    summary.addMarker(marker);
    var recovered = RecordingFooter(
      name: name,
      durationMicros: lastOffset,
      recovered: true,
      topics: topics,
      summary: summary.summary,
      seekIndex: seekIndex,
    );
    var bytes = BytesBuilder(copy: false)..add(RecordCodec.encodeMarker(marker));
    var footerStart = scanner.lastGoodPosition + bytes.length;
    bytes
      ..add(RecordCodec.encodeFooter(recovered.toJson()))
      ..add(RecordCodec.encodeTrailer(footerStart));
    await file.append(bytes.takeBytes());
    footer = recovered;
    footerPosition = footerStart;
    return recovered;
  }

  // replaces the footer, e.g. after a rename. The messages stay untouched.
  Future<void> rewriteFooter(RecordingFooter changed) async {
    if (footerPosition == null) {
      throw StateError('${file.name} has no footer to replace');
    }
    await file.truncate(footerPosition!);
    var bytes = BytesBuilder(copy: false)
      ..add(RecordCodec.encodeFooter(changed.toJson()))
      ..add(RecordCodec.encodeTrailer(footerPosition!));
    await file.append(bytes.takeBytes());
    footer = changed;
  }

  // the last seek index entry at or before the given offset
  SeekEntry? seekEntryFor(int offsetMicros) {
    SeekEntry? best;
    for (var entry in footer?.seekIndex ?? <SeekEntry>[]) {
      if (entry.offsetMicros > offsetMicros) {
        break;
      }
      best = entry;
    }
    return best;
  }

  Future<void> close() => file.close();
}

class RecordingCursor {
  final RecordingReader _reader;
  final int _from;
  final List<String> _topics;
  _RecordScanner? _scanner;

  RecordingCursor._(this._reader, this._from) : _topics = List.of(_reader.footer?.topics ?? <String>[]);

  // the next message or marker, null at the end
  Future<RecordingEntry?> next() async {
    var scanner = _scanner ??= _RecordScanner(_reader.file, _from, _reader.footerPosition ?? await _reader.file.length());
    while (true) {
      var record = await scanner.next();
      if (record == null) {
        return null;
      }
      switch (record.type) {
        case RecordCodec.typeTopic:
          var topic = RecordCodec.decodeTopic(record.body);
          while (_topics.length <= topic.topicIndex) {
            _topics.add('');
          }
          _topics[topic.topicIndex] = topic.topic;
        case RecordCodec.typeMessage:
          return MessageEntry(record.position, RecordCodec.decodeMessage(record.body, (index) => _topics[index]));
        case RecordCodec.typeMarker:
          return MarkerEntry(record.position, RecordCodec.decodeMarker(record.body));
      }
    }
  }
}
