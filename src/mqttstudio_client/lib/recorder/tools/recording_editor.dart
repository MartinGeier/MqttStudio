import 'dart:async';
import 'dart:math';
import 'package:clock/clock.dart';
import 'package:mqttstudio/recorder/format/recording_reader.dart';
import 'package:mqttstudio/recorder/format/recording_writer.dart';
import 'package:mqttstudio/recorder/model/anonymize_rule.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:uuid/uuid.dart';

// Edits of recordings (doc/recorder-design.md §8.1). Messages are never changed in place (R9): every edit writes a
// new recording with origin `edit` and the source ids, named "<name> (<edit>)". The original stays. Edits stream
// from the source to the new file, so large recordings don't have to fit into memory.
class RecordingEditor {
  static const int _yieldEvery = 2000;

  final RecordingLibrary library;
  // called with 0…1 while an edit reads its source
  void Function(double progress)? onProgress;

  RecordingEditor(this.library, {this.onProgress});

  // Keeps [fromMicros, toMicros] with offsets from its start. The retained snapshot is the last retained message per
  // topic before the range, at offset 0.
  Future<RecordingInfo> trim(RecordingInfo info, int fromMicros, int toMicros, {String? name}) {
    var from = max(0, fromMicros);
    var to = min(info.footer.durationMicros, toMicros);
    return _create(
      name: name ?? '${info.name} (trimmed)',
      template: info.header,
      startedAt: info.header.startedAt.add(Duration(microseconds: from)),
      sources: [info],
      durationMicros: to - from,
      bookmarks: _bookmarksIn(info, from, to),
      fill: (writer) async {
        var retained = <String, RecordedMessage>{};
        var snapshotWritten = false;
        Future<void> writeSnapshot() async {
          snapshotWritten = true;
          for (var message in retained.values) {
            await _add(writer, _asSnapshot(message));
          }
        }

        await _read(info, (entry) async {
          var offset = _offsetOf(entry);
          if (offset < from) {
            if (entry is RecordedMessage && (entry.retain || entry.snapshot)) {
              if (entry.payloadLength == 0) {
                retained.remove(entry.topic);
              } else {
                retained[entry.topic] = entry;
              }
            }
            return true;
          }
          if (offset > to) {
            return false;
          }
          if (!snapshotWritten) {
            await writeSnapshot();
          }
          await _add(writer, _shift(entry, -from));
          return true;
        });
        if (!snapshotWritten) {
          await writeSnapshot();
        }
      },
    );
  }

  Future<RecordingInfo> keepTopics(RecordingInfo info, Set<String> topics, {String? name}) => _create(
        name: name ?? (topics.length == 1 ? '${info.name} (${topics.single})' : '${info.name} (topics)'),
        template: info.header,
        startedAt: info.header.startedAt,
        sources: [info],
        durationMicros: info.footer.durationMicros,
        bookmarks: info.footer.bookmarks,
        fill: (writer) => _read(info, (entry) async {
          if (entry is! RecordedMessage || topics.contains(entry.topic)) {
            await _add(writer, entry);
          }
          return true;
        }),
      );

  // the first remap whose prefix matches renames a topic; the filters are renamed the same way
  Future<RecordingInfo> renameTopics(RecordingInfo info, List<TopicRemap> remaps) {
    var options = PlaybackOptions(remaps: remaps);
    var header = _copyHeader(info.header)
      ..filters = [for (var filter in info.header.filters) filter.copy()..filter = options.remap(filter.filter)];
    return _create(
      name: '${info.name} (renamed)',
      template: header,
      startedAt: info.header.startedAt,
      sources: [info],
      durationMicros: info.footer.durationMicros,
      bookmarks: info.footer.bookmarks,
      fill: (writer) => _read(info, (entry) async {
        await _add(writer, entry is RecordedMessage ? _withTopic(entry, options.remap(entry.topic)) : entry);
        return true;
      }),
    );
  }

  Future<RecordingInfo> anonymize(RecordingInfo info, List<AnonymizeRule> rules, {bool properties = false}) {
    var anonymizer = Anonymizer(rules, properties: properties);
    return _create(
      name: '${info.name} (anonymized)',
      template: info.header,
      startedAt: info.header.startedAt,
      sources: [info],
      durationMicros: info.footer.durationMicros,
      bookmarks: info.footer.bookmarks,
      fill: (writer) => _read(info, (entry) async {
        await _add(writer, entry is RecordedMessage ? anonymizer.apply(entry) : entry);
        return true;
      }),
    );
  }

  // interleaves the messages by wall time; the merged recording starts with the earliest one
  Future<RecordingInfo> merge(List<RecordingInfo> infos, String name) {
    if (infos.length < 2) {
      throw ArgumentError('Merging needs at least two recordings');
    }
    var start = infos.map((info) => info.header.startedAt).reduce((a, b) => a.isBefore(b) ? a : b);
    var shifts = [for (var info in infos) info.header.startedAt.difference(start).inMicroseconds];
    var end = 0;
    for (var i = 0; i < infos.length; i++) {
      end = max(end, shifts[i] + infos[i].footer.durationMicros);
    }
    var filters = <String, RecorderFilter>{};
    for (var info in infos) {
      for (var filter in info.header.filters) {
        filters.putIfAbsent('${filter.exclude}|${filter.filter}', () => filter.copy());
      }
    }
    return _create(
      name: name,
      template: _copyHeader(infos.first.header)..filters = filters.values.toList(),
      startedAt: start,
      sources: infos,
      durationMicros: end,
      bookmarks: [
        for (var i = 0; i < infos.length; i++)
          for (var bookmark in infos[i].footer.bookmarks) Bookmark(bookmark.offsetMicros + shifts[i], bookmark.label)
      ]..sort((a, b) => a.offsetMicros.compareTo(b.offsetMicros)),
      fill: (writer) => _mergeInto(writer, infos, shifts),
    );
  }

  // one recording per part between the cut offsets, each trimmed like trim()
  Future<List<RecordingInfo>> splitAt(RecordingInfo info, List<int> cutsMicros) async {
    var duration = info.footer.durationMicros;
    var cuts = cutsMicros.where((cut) => cut > 0 && cut < duration).toSet().toList()..sort();
    var bounds = [0, ...cuts, duration];
    var parts = <RecordingInfo>[];
    for (var i = 0; i + 1 < bounds.length; i++) {
      parts.add(await trim(info, bounds[i], bounds[i + 1], name: '${info.name} (part ${i + 1})'));
    }
    return parts;
  }

  Future<List<RecordingInfo>> splitByTopic(RecordingInfo info) async {
    var parts = <RecordingInfo>[];
    for (var topic in List.of(info.footer.topics)..sort()) {
      parts.add(await keepTopics(info, {topic}));
    }
    return parts;
  }

  // a k-way merge over one cursor per recording; equal times keep the order of the recordings
  Future<void> _mergeInto(RecordingWriter writer, List<RecordingInfo> infos, List<int> shifts) async {
    var readers = <RecordingReader>[];
    try {
      for (var info in infos) {
        readers.add(await library.open(info));
      }
      var cursors = [for (var reader in readers) reader.cursor()];
      var heads = <Object?>[for (var cursor in cursors) _valueOf(await cursor.next())];
      var count = 0;
      while (true) {
        var next = -1;
        for (var i = 0; i < heads.length; i++) {
          if (heads[i] != null && (next < 0 || _offsetOf(heads[i]!) + shifts[i] < _offsetOf(heads[next]!) + shifts[next])) {
            next = i;
          }
        }
        if (next < 0) {
          return;
        }
        await _add(writer, _shift(heads[next]!, shifts[next]));
        heads[next] = _valueOf(await cursors[next].next());
        if (++count % _yieldEvery == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    } finally {
      for (var reader in readers) {
        await reader.close();
      }
    }
  }

  // reads all entries in file order; visit returns false to stop early
  Future<void> _read(RecordingInfo info, Future<bool> Function(Object entry) visit) async {
    var reader = await library.open(info);
    try {
      var end = reader.footerPosition ?? await reader.file.length();
      var cursor = reader.cursor();
      var count = 0;
      while (true) {
        var entry = await cursor.next();
        if (entry == null || !await visit(_valueOf(entry)!)) {
          break;
        }
        if (++count % _yieldEvery == 0) {
          onProgress?.call((entry.position - reader.dataStart) / max(1, end - reader.dataStart));
          await Future<void>.delayed(Duration.zero);
        }
      }
    } finally {
      await reader.close();
    }
  }

  static Object? _valueOf(RecordingEntry? entry) => switch (entry) {
        MessageEntry(:var message) => message,
        MarkerEntry(:var marker) => marker,
        null => null,
      };

  static Future<void> _add(RecordingWriter writer, Object entry) async {
    if (entry is RecordedMessage) {
      writer.addMessage(entry);
    } else if (entry is RecordingMarker) {
      writer.addMarker(entry);
    }
    if (writer.needsFlush) {
      await writer.flush();
    }
  }

  // a new recording in the library; nothing is left behind when filling it fails
  Future<RecordingInfo> _create({
    required String name,
    required RecordingHeader template,
    required DateTime startedAt,
    required List<RecordingInfo> sources,
    required int durationMicros,
    required List<Bookmark> bookmarks,
    required Future<void> Function(RecordingWriter writer) fill,
  }) async {
    var header = _copyHeader(template)
      ..id = const Uuid().v4()
      ..startedAt = startedAt
      ..origin = RecordingOrigin.edit
      ..sourceRecordingIds = [for (var source in sources) source.id];
    var file = await library.create(name, clock.now());
    try {
      var writer = await RecordingWriter.start(file, header);
      await fill(writer);
      // an edit stays with the project of its (first) source
      var footer = await writer.finish(
          name: name,
          durationMicros: max(0, durationMicros),
          bookmarks: bookmarks,
          projectName: sources.first.footer.projectName);
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

  static RecordingHeader _copyHeader(RecordingHeader header) => RecordingHeader.fromJson(header.toJson());

  static List<Bookmark> _bookmarksIn(RecordingInfo info, int from, int to) => [
        for (var bookmark in info.footer.bookmarks)
          if (bookmark.offsetMicros >= from && bookmark.offsetMicros <= to) Bookmark(bookmark.offsetMicros - from, bookmark.label)
      ];

  static int _offsetOf(Object entry) => entry is RecordedMessage ? entry.offsetMicros : (entry as RecordingMarker).offsetMicros;

  static Object _shift(Object entry, int byMicros) => entry is RecordedMessage
      ? entry.at(entry.offsetMicros + byMicros)
      : RecordingMarker((entry as RecordingMarker).offsetMicros + byMicros, entry.kind);

  static RecordedMessage _asSnapshot(RecordedMessage message) => RecordedMessage(
        offsetMicros: 0,
        topic: message.topic,
        payload: message.payload,
        payloadLength: message.payloadLength,
        qos: message.qos,
        retain: true,
        snapshot: true,
        truncated: message.truncated,
        properties: message.properties,
      );

  static RecordedMessage _withTopic(RecordedMessage message, String topic) => RecordedMessage(
        offsetMicros: message.offsetMicros,
        topic: topic,
        payload: message.payload,
        payloadLength: message.payloadLength,
        qos: message.qos,
        retain: message.retain,
        snapshot: message.snapshot,
        truncated: message.truncated,
        properties: message.properties,
      );
}
