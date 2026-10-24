import 'dart:convert';
import 'package:mqttstudio/common/utils/json_path.dart';
import 'package:mqttstudio/recorder/format/recording_reader.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';

enum ExportFormat { mqttrec, jsonLines, csv }

// Writes the messages of a recording as JSON lines or CSV (doc/recorder-design.md §8.3). The selected topics and range
// are exported, with offsets from the start of the range. A .mqttrec export is a copy of the file instead.
class RecordingExport {
  static const String formatName = 'mqttstudio-recording';
  static const int formatVersion = 1;
  static const List<String> csvColumns = ['time', 'offset_ms', 'topic', 'qos', 'retain', 'payload', 'payload_encoding'];
  static const int _yieldEvery = 2000;

  static String extensionOf(ExportFormat format) => switch (format) {
        ExportFormat.mqttrec => 'mqttrec',
        ExportFormat.jsonLines => 'jsonl',
        ExportFormat.csv => 'csv',
      };

  // returns the number of exported messages, null when cancelled
  static Future<int?> writeText(RecordingReader reader, StringSink out,
      {required ExportFormat format,
      Set<String>? topics,
      int? fromMicros,
      int? toMicros,
      List<JsonPath> columns = const [],
      bool Function()? isCancelled}) async {
    var footer = reader.footer!;
    var from = fromMicros ?? 0;
    var to = toMicros ?? footer.durationMicros;
    var startedAt = reader.header.startedAt.add(Duration(microseconds: from));
    if (format == ExportFormat.jsonLines) {
      var header = reader.header.toJson()..['startedAt'] = startedAt.toIso8601String();
      out.writeln(jsonEncode({
        'format': formatName,
        'version': formatVersion,
        'header': header,
        'name': footer.name,
        'notes': footer.notes,
        'durationMicros': to - from,
        'bookmarks': [
          for (var bookmark in footer.bookmarks)
            if (bookmark.offsetMicros >= from && bookmark.offsetMicros <= to) {'t': bookmark.offsetMicros - from, 'label': bookmark.label}
        ],
      }));
    } else {
      out.writeln([...csvColumns, ...columns.map((path) => path.toString())].map(_csv).join(','));
    }
    var cursor = reader.cursor(from: reader.seekEntryFor(from)?.position);
    var count = 0;
    var exported = 0;
    while (true) {
      var entry = await cursor.next();
      if (entry == null) {
        break;
      }
      var offset = switch (entry) {
        MessageEntry(:var message) => message.offsetMicros,
        MarkerEntry(:var marker) => marker.offsetMicros,
      };
      if (offset > to) {
        break;
      }
      if (offset >= from) {
        if (entry is MessageEntry && (topics == null || topics.contains(entry.message.topic))) {
          var message = entry.message;
          var time = startedAt.add(Duration(microseconds: offset - from));
          out.writeln(format == ExportFormat.jsonLines
              ? jsonEncode(_messageJson(message, offset - from, time))
              : _csvLine(message, offset - from, time, columns));
          exported++;
        } else if (entry is MarkerEntry && format == ExportFormat.jsonLines) {
          var time = startedAt.add(Duration(microseconds: offset - from));
          out.writeln(jsonEncode({'t': offset - from, 'time': time.toIso8601String(), 'marker': entry.marker.kind}));
        }
      }
      if (++count % _yieldEvery == 0) {
        await Future<void>.delayed(Duration.zero);
        if (isCancelled?.call() ?? false) {
          return null;
        }
      }
    }
    return exported;
  }

  // the payload as text when it is UTF-8, else as base64
  static (String, bool) payloadText(RecordedMessage message) {
    try {
      return (utf8.decode(message.payload), false);
    } on FormatException {
      return (base64Encode(message.payload), true);
    }
  }

  static Map<String, dynamic> _messageJson(RecordedMessage message, int offset, DateTime time) {
    var (payload, base64) = payloadText(message);
    return {
      't': offset,
      'time': time.toIso8601String(),
      'topic': message.topic,
      'qos': message.qos.index,
      'retain': message.retain,
      if (message.snapshot) 'snapshot': true,
      if (base64) 'payloadBase64': payload else 'payload': payload,
      if (message.truncated) 'truncated': true,
      if (message.truncated) 'payloadLength': message.payloadLength,
      if (message.properties != null && RecordedProperties.hasContent(message.properties))
        'properties': RecordedProperties.toJson(message.properties!),
    };
  }

  static String _csvLine(RecordedMessage message, int offset, DateTime time, List<JsonPath> columns) {
    var (payload, base64) = payloadText(message);
    Object? json;
    if (columns.isNotEmpty && !base64) {
      try {
        json = jsonDecode(payload);
      } on FormatException {
        json = null;
      }
    }
    var values = [
      time.toIso8601String(),
      (offset / 1000).toStringAsFixed(3),
      message.topic,
      '${message.qos.index}',
      '${message.retain}',
      payload,
      base64 ? 'base64' : 'text',
      for (var path in columns) _columnValue(json == null ? null : path.evaluate(json)),
    ];
    return values.map(_csv).join(',');
  }

  static String _columnValue(Object? value) => switch (value) {
        null => '',
        String text => text,
        num number => '$number',
        bool flag => '$flag',
        _ => jsonEncode(value),
      };

  // quotes a field when it holds a comma, a quote, a line break or blanks at its ends
  static String _csv(String value) {
    var needsQuotes = value.contains(RegExp(r'[",\r\n]')) || value != value.trim();
    return needsQuotes ? '"${value.replaceAll('"', '""')}"' : value;
  }

}

// what the export dialog asks for
class ExportRequest {
  final ExportFormat format;
  final bool onlySelectedTopics;
  final bool onlyRange;
  // CSV only: one extra column per path
  final List<JsonPath> columns;

  ExportRequest(this.format, {this.onlySelectedTopics = false, this.onlyRange = false, this.columns = const []});
}
