import 'dart:convert';
import 'dart:typed_data';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/recorder/format/recording_writer.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/tools/recording_export.dart';
import 'package:uuid/uuid.dart';

// mosquittoTimed: mosquitto_sub -F "%U %t %p" (Unix time, topic, payload); mosquittoVerbose: mosquitto_sub -v
// (topic, payload) without times
enum ImportFormat { mqttrec, jsonLines, csv, mosquittoTimed, mosquittoVerbose }

// Reads JSON lines, CSV and mosquitto_sub output into a new recording (doc/recorder-design.md §8.3). The summary is
// computed while writing. Lines that can't be read are counted and skipped.
class RecordingImport {
  static const int _yieldEvery = 2000;

  final RecordingLibrary library;
  // lines that were skipped in the last import
  int skipped = 0;

  RecordingImport(this.library);

  // a guess from the file name and its first line; null when nothing fits
  static ImportFormat? formatOf(String fileName, String firstLine) {
    var lower = fileName.toLowerCase();
    if (lower.endsWith('.mqttrec')) {
      return ImportFormat.mqttrec;
    }
    if (lower.endsWith('.jsonl') || lower.endsWith('.json') || firstLine.trimLeft().startsWith('{')) {
      return ImportFormat.jsonLines;
    }
    if (lower.endsWith('.csv') || firstLine.startsWith('time,')) {
      return ImportFormat.csv;
    }
    if (RegExp(r'^\d{9,}(\.\d+)? \S').hasMatch(firstLine)) {
      return ImportFormat.mosquittoTimed;
    }
    return firstLine.trim().isEmpty ? null : ImportFormat.mosquittoVerbose;
  }

  // interval: the time between two lines of mosquitto_sub -v output
  Future<RecordingInfo> importText(String text, ImportFormat format,
      {required String name, Duration interval = const Duration(seconds: 1), void Function(double progress)? onProgress}) async {
    skipped = 0;
    var lines = const LineSplitter().convert(text);
    _Parsed parsed;
    switch (format) {
      case ImportFormat.jsonLines:
        parsed = await _jsonLines(lines, onProgress);
      case ImportFormat.csv:
        parsed = await _csvLines(lines, onProgress);
      case ImportFormat.mosquittoTimed:
        parsed = await _mosquitto(lines, onProgress, null);
      case ImportFormat.mosquittoVerbose:
        parsed = await _mosquitto(lines, onProgress, interval);
      case ImportFormat.mqttrec:
        throw ArgumentError('.mqttrec files are imported with RecordingLibrary.importFile');
    }
    if (parsed.messages.isEmpty) {
      throw FormatException('The file holds no messages that can be read');
    }
    return _write(name, parsed);
  }

  Future<_Parsed> _jsonLines(List<String> lines, void Function(double)? onProgress) async {
    var parsed = _Parsed();
    DateTime? headerStart;
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (line.isEmpty) {
        continue;
      }
      try {
        var json = jsonDecode(line) as Map<String, dynamic>;
        if (json['format'] == RecordingExport.formatName) {
          var header = RecordingHeader.fromJson(json['header'] as Map<String, dynamic>);
          headerStart = header.startedAt;
          parsed.header = header;
          parsed.notes = json['notes'] as String? ?? '';
          parsed.bookmarks = [
            for (var bookmark in (json['bookmarks'] as List<dynamic>? ?? []))
              Bookmark((bookmark as Map<String, dynamic>)['t'] as int, bookmark['label'] as String)
          ];
          continue;
        }
        var time = headerStart != null && json['t'] is int
            ? headerStart.add(Duration(microseconds: json['t'] as int))
            : DateTime.parse(json['time'] as String).toUtc();
        if (json.containsKey('marker')) {
          parsed.markers.add((time, json['marker'] as String));
          continue;
        }
        var payload = json.containsKey('payloadBase64')
            ? base64Decode(json['payloadBase64'] as String)
            : Uint8List.fromList(utf8.encode(json['payload'] as String? ?? ''));
        parsed.messages.add((
          time,
          RecordedMessage(
            offsetMicros: 0,
            topic: json['topic'] as String,
            payload: payload,
            payloadLength: json['payloadLength'] as int?,
            qos: MqttQos.values[(json['qos'] as int? ?? 0).clamp(0, 2)],
            retain: json['retain'] as bool? ?? false,
            snapshot: json['snapshot'] as bool? ?? false,
            truncated: json['truncated'] as bool? ?? false,
            properties: json['properties'] == null
                ? null
                : RecordedProperties.fromJson(json['properties'] as Map<String, dynamic>),
          )
        ));
      } catch (_) {
        skipped++;
      }
      await _progress(i, lines.length, onProgress);
    }
    return parsed;
  }

  Future<_Parsed> _csvLines(List<String> lines, void Function(double)? onProgress) async {
    var parsed = _Parsed();
    var rows = _CsvReader(lines).rows();
    if (rows.isEmpty) {
      return parsed;
    }
    var columns = rows.first;
    int column(String name) => columns.indexOf(name);
    var time = column('time');
    var offset = column('offset_ms');
    var topic = column('topic');
    var qos = column('qos');
    var retain = column('retain');
    var payload = column('payload');
    var encoding = column('payload_encoding');
    if (topic < 0 || payload < 0 || (time < 0 && offset < 0)) {
      throw FormatException('A CSV import needs the columns topic, payload and time or offset_ms');
    }
    var start = DateTime.now().toUtc();
    for (var i = 1; i < rows.length; i++) {
      var row = rows[i];
      try {
        String cell(int index) => index >= 0 && index < row.length ? row[index] : '';
        var at = time >= 0 && cell(time).isNotEmpty
            ? DateTime.parse(cell(time)).toUtc()
            : start.add(Duration(microseconds: (double.parse(cell(offset)) * 1000).round()));
        var bytes = cell(encoding) == 'base64' ? base64Decode(cell(payload)) : Uint8List.fromList(utf8.encode(cell(payload)));
        parsed.messages.add((
          at,
          RecordedMessage(
            offsetMicros: 0,
            topic: cell(topic),
            payload: bytes,
            qos: MqttQos.values[(int.tryParse(cell(qos)) ?? 0).clamp(0, 2)],
            retain: cell(retain) == 'true',
          )
        ));
      } catch (_) {
        skipped++;
      }
      await _progress(i, rows.length, onProgress);
    }
    return parsed;
  }

  Future<_Parsed> _mosquitto(List<String> lines, void Function(double)? onProgress, Duration? interval) async {
    var parsed = _Parsed();
    var start = DateTime.now().toUtc();
    var index = 0;
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        DateTime at;
        String rest;
        if (interval == null) {
          var space = line.indexOf(' ');
          var seconds = double.parse(line.substring(0, space));
          at = DateTime.fromMicrosecondsSinceEpoch((seconds * Duration.microsecondsPerSecond).round(), isUtc: true);
          rest = line.substring(space + 1);
        } else {
          at = start.add(interval * index);
          rest = line;
        }
        var space = rest.indexOf(' ');
        var topic = space < 0 ? rest : rest.substring(0, space);
        var payload = space < 0 ? '' : rest.substring(space + 1);
        if (topic.isEmpty) {
          throw FormatException('no topic');
        }
        parsed.messages.add((at, RecordedMessage(offsetMicros: 0, topic: topic, payload: Uint8List.fromList(utf8.encode(payload)))));
        index++;
      } catch (_) {
        skipped++;
      }
      await _progress(i, lines.length, onProgress);
    }
    return parsed;
  }

  static Future<void> _progress(int index, int total, void Function(double)? onProgress) async {
    if (index % _yieldEvery == 0) {
      onProgress?.call(total == 0 ? 1 : index / total);
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<RecordingInfo> _write(String name, _Parsed parsed) async {
    parsed.messages.sort((a, b) => a.$1.compareTo(b.$1));
    var first = parsed.messages.first.$1;
    var startedAt = parsed.header?.startedAt ?? first;
    if (first.isBefore(startedAt)) {
      startedAt = first;
    }
    var hasProperties = parsed.messages.any((entry) => entry.$2.properties != null);
    var header = parsed.header ??
        RecordingHeader(
          id: '',
          startedAt: startedAt,
          filters: [RecorderFilter('#')],
          broker: 'import',
          protocol: hasProperties ? MqttProtocolVersion.v5 : MqttProtocolVersion.v311,
          clientId: '',
          appVersion: '',
        );
    header
      ..id = const Uuid().v4()
      ..startedAt = startedAt
      ..origin = RecordingOrigin.import;
    var entries = <(DateTime, Object)>[
      for (var (time, message) in parsed.messages) (time, message),
      for (var (time, kind) in parsed.markers) (time, kind),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var file = await library.create(name, startedAt);
    try {
      var writer = await RecordingWriter.start(file, header);
      var last = 0;
      for (var (time, entry) in entries) {
        var offset = time.difference(startedAt).inMicroseconds;
        last = offset;
        if (entry is RecordedMessage) {
          writer.addMessage(entry.at(offset));
        } else {
          writer.addMarker(RecordingMarker(offset, entry as String));
        }
        if (writer.needsFlush) {
          await writer.flush();
        }
      }
      var footer = await writer.finish(name: name, durationMicros: last, notes: parsed.notes, bookmarks: parsed.bookmarks);
      return RecordingInfo(file.name, writer.header, footer, writer.length);
    } catch (_) {
      try {
        await file.close();
      } catch (_) {
        // already closed by the writer
      }
      await library.store.delete(file.name);
      rethrow;
    } finally {
      library.finishedWriting(file.name);
    }
  }
}

class _Parsed {
  RecordingHeader? header;
  String notes = '';
  List<Bookmark> bookmarks = [];
  final List<(DateTime, RecordedMessage)> messages = [];
  final List<(DateTime, String)> markers = [];
}

// CSV as RecordingExport writes it: quoted fields may hold commas, quotes ("") and line breaks
class _CsvReader {
  final List<String> lines;

  _CsvReader(this.lines);

  List<List<String>> rows() {
    var rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    for (var line in lines) {
      for (var i = 0; i < line.length; i++) {
        var char = line[i];
        if (quoted) {
          if (char == '"' && i + 1 < line.length && line[i + 1] == '"') {
            field.write('"');
            i++;
          } else if (char == '"') {
            quoted = false;
          } else {
            field.write(char);
          }
        } else if (char == '"') {
          quoted = true;
        } else if (char == ',') {
          row.add(field.toString());
          field.clear();
        } else {
          field.write(char);
        }
      }
      if (quoted) {
        // the field goes on in the next line
        field.write('\n');
        continue;
      }
      row.add(field.toString());
      field.clear();
      if (row.length > 1 || row.first.isNotEmpty) {
        rows.add(row);
      }
      row = <String>[];
    }
    return rows;
  }
}

// what the import dialog asks for: the file by its path on desktop, by its bytes in the browser
class ImportRequest {
  final String fileName;
  final String? path;
  final Uint8List? bytes;
  final ImportFormat format;
  final String name;
  final Duration interval;

  ImportRequest(this.fileName, this.format, this.name,
      {this.path, this.bytes, this.interval = const Duration(seconds: 1)});
}
