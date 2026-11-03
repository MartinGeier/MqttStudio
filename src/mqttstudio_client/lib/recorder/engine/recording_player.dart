import 'dart:async';
import 'dart:math';
import 'package:clock/clock.dart';
import 'package:event/event.dart';
import 'package:mqttstudio/recorder/format/recording_reader.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:typed_data/typed_buffers.dart';

enum PlaybackState { stopped, playing, paused }

class _Scheduled {
  final RecordedMessage message;
  // offset from the range start after shortening gaps
  final int playMicros;

  _Scheduled(this.message, this.playMicros);
}

// Plays a recording through the simulator's publisher (doc/recorder-design.md §6.1). Each message is due at
// start + (its offset − range start) / speed on a stopwatch, so the schedule doesn't drift with timer precision;
// when the player falls behind it sends in order without waiting and reports the lag (R11).
class RecordingPlayer {
  // a loop pass lasts at least this long, so a short recording doesn't republish without a pause
  static const Duration minLoopPass = Duration(seconds: 1);

  final RecordingReader reader;
  final SimulatorPublisher _publisher;
  // msg/s at Max speed (R12)
  double maxRate;
  final Duration progressInterval;
  PlaybackOptions _options;

  final stateChangedEvent = Event();
  // raised at most once per progressInterval
  final progressChangedEvent = Event();
  // the publisher lost its connection, raised once per outage. Playback keeps its schedule and skips the messages
  // that are due until the publisher is connected again.
  final connectionLostEvent = Event();
  // the end of the range was reached without loop, or a loop pass had nothing to play
  final finishedEvent = Event();

  PlaybackState _state = PlaybackState.stopped;
  RecordingCursor? _cursor;
  // the next message, read but not yet due
  _Scheduled? _next;
  // the read that fills _next; there is only one at a time, so a pause or a new schedule neither skips nor loses one
  Future<void>? _reading;
  // the cursor reached the end of the pass
  bool _atEnd = false;
  // messages read in this pass
  int _passMessages = 0;
  int _passStartWallMicros = 0;
  bool _publisherLost = false;
  Timer? _timer;
  Timer? _progressTimer;
  bool _progressDirty = false;
  // bumped whenever the schedule restarts, so a pending run of an older schedule ends
  int _generation = 0;
  final Stopwatch _stopwatch = clock.stopwatch();
  int _baseWallMicros = 0;
  int _basePlayMicros = 0;
  // offset of the last sent message and of the last read one, after shortening gaps
  int _lastPlayMicros = 0;
  int _lastPlayMicrosRead = 0;
  int _lastOriginalMicros = 0;
  int _lastPublishWallMicros = 0;
  bool _firstPass = true;

  int positionMicros = 0;
  int sent = 0;
  int skipped = 0;
  int lagMicros = 0;
  int loopCount = 0;

  // where a message is published, by default its remapped topic; recorded devices also resolve {n}
  final String Function(String recordedTopic)? mapTopic;
  // called for every published message, e.g. for the simulator's statistics
  final void Function(RecordedMessage message, String topic)? onPublished;
  // the first pass starts here instead of at the range start, later loops start at the range start
  final int? startPositionMicros;
  int _passStartMicros = 0;

  RecordingPlayer(this.reader, PlaybackOptions options, this._publisher,
      {this.maxRate = 1000,
      this.progressInterval = const Duration(milliseconds: 250),
      this.mapTopic,
      this.onPublished,
      this.startPositionMicros})
      : _options = options.copy();

  PlaybackState get state => _state;

  PlaybackOptions get options => _options;

  bool get isPlaying => _state == PlaybackState.playing;

  int get rangeStartMicros => _options.rangeStartMicros ?? 0;

  int get rangeEndMicros => _options.rangeEndMicros ?? reader.footer?.durationMicros ?? 0;

  // msg/s of the selected topics at the given options, and the busiest second (§6.2)
  static ({double rate, double peak}) estimate(RecordingInfo info, PlaybackOptions options, {double maxRate = 1000}) =>
      estimateFooter(info.footer, options, maxRate: maxRate);

  static ({double rate, double peak}) estimateFooter(RecordingFooter footer, PlaybackOptions options,
      {double maxRate = 1000}) {
    var summary = footer.summary;
    // a recording shorter than a second counts as one, its messages can't come faster than its peak second
    var seconds = max(1.0, footer.duration.inMicroseconds / Duration.microsecondsPerSecond);
    var count = 0;
    var peak = 0;
    summary.perTopic.forEach((topic, stats) {
      if (options.plays(topic)) {
        count += stats.count;
        peak += stats.peakRatePerSecond;
      }
    });
    if (options.isMaxSpeed) {
      return (rate: count == 0 ? 0 : maxRate, peak: count == 0 ? 0 : maxRate);
    }
    return (rate: count / seconds * options.speed, peak: min(peak, summary.peakRatePerSecond) * options.speed);
  }

  Future<void> play() async {
    switch (_state) {
      case PlaybackState.playing:
        return;
      case PlaybackState.paused:
        _stopwatch.start();
        _rebase();
        _setState(PlaybackState.playing);
        _run(_generation);
      case PlaybackState.stopped:
        await _prepare();
        _setState(PlaybackState.playing);
        _run(_generation);
    }
  }

  void pause() {
    if (_state != PlaybackState.playing) {
      return;
    }
    _generation++;
    _timer?.cancel();
    _stopwatch.stop();
    _setState(PlaybackState.paused);
  }

  Future<void> stop() async {
    if (_state == PlaybackState.stopped) {
      return;
    }
    _generation++;
    _timer?.cancel();
    _stopwatch
      ..stop()
      ..reset();
    _cursor = null;
    _next = null;
    _reading = null;
    _setState(PlaybackState.stopped);
  }

  // sends the next message at once, starting a paused playback if needed
  Future<void> step() async {
    if (_state == PlaybackState.playing) {
      return;
    }
    if (_state == PlaybackState.stopped) {
      await _prepare();
      _stopwatch.stop();
      _setState(PlaybackState.paused);
    }
    var generation = _generation;
    await _fill();
    var next = _next;
    if (generation != _generation || next == null) {
      return;
    }
    _next = null;
    _publish(next, 0);
    _lastPlayMicros = next.playMicros;
    _markProgress();
  }

  void setSpeed(double speed) {
    _rebase();
    _options.speed = speed;
    if (_state == PlaybackState.playing) {
      _generation++;
      _timer?.cancel();
      _run(_generation);
    }
  }

  void setLoop(bool loop) => _options.loop = loop;

  // applies new options; a running playback starts again from the range start
  Future<void> setOptions(PlaybackOptions options) async {
    var wasPlaying = _state != PlaybackState.stopped;
    await stop();
    _options = options.copy();
    if (wasPlaying) {
      await play();
    }
  }

  void dispose() {
    _generation++;
    _timer?.cancel();
    _progressTimer?.cancel();
  }

  Future<void> _prepare() async {
    _generation++;
    sent = 0;
    skipped = 0;
    lagMicros = 0;
    loopCount = 0;
    _firstPass = true;
    var start = max(rangeStartMicros, startPositionMicros ?? 0);
    if (_options.snapshot == RetainedSnapshotMode.publish && start > 0) {
      await _publishStateAt(start);
    }
    await _openRange(start);
    _stopwatch
      ..reset()
      ..start();
    _baseWallMicros = 0;
    _basePlayMicros = 0;
    _lastPublishWallMicros = 0;
    _passStartWallMicros = 0;
    _publisherLost = false;
  }

  Future<void> _openRange([int? from]) async {
    _passStartMicros = from ?? rangeStartMicros;
    var seek = reader.seekEntryFor(_passStartMicros);
    _cursor = reader.cursor(from: seek?.position);
    _next = null;
    _reading = null;
    _atEnd = false;
    _passMessages = 0;
    _lastPlayMicros = 0;
    _lastPlayMicrosRead = 0;
    _lastOriginalMicros = _passStartMicros;
    positionMicros = _passStartMicros;
  }

  // when playback starts later than the recording, the state there is the last retained message of each topic
  Future<void> _publishStateAt(int position) async {
    var state = <String, RecordedMessage>{};
    var cursor = reader.cursor();
    for (var entry = await cursor.next(); entry != null; entry = await cursor.next()) {
      if (entry is! MessageEntry) {
        continue;
      }
      var message = entry.message;
      if (message.offsetMicros >= position) {
        break;
      }
      if ((message.retain || message.snapshot) && _options.plays(message.topic)) {
        state[message.topic] = message;
      }
    }
    for (var message in state.values) {
      _send(message, retain: _options.retain != RetainOverride.never);
    }
  }

  // reads the next message into _next, or sets _atEnd. A read of an older cursor (after stop or a new pass) is dropped.
  Future<void> _fill() {
    var cursor = _cursor;
    if (_next != null || _atEnd || cursor == null) {
      return Future.value();
    }
    var reading = _reading;
    if (reading == null) {
      late Future<void> started;
      started = _read(cursor).then((next) {
        if (identical(cursor, _cursor)) {
          _next = next;
          _atEnd = next == null;
        }
      }).whenComplete(() {
        if (identical(_reading, started)) {
          _reading = null;
        }
      });
      _reading = reading = started;
    }
    return reading;
  }

  Future<_Scheduled?> _read(RecordingCursor cursor) async {
    while (true) {
      var entry = await cursor.next();
      if (entry == null || !identical(cursor, _cursor)) {
        return null;
      }
      if (entry is! MessageEntry) {
        continue;
      }
      var message = entry.message;
      if (message.offsetMicros < _passStartMicros || !_options.plays(message.topic)) {
        continue;
      }
      if (_options.rangeEndMicros != null && message.offsetMicros > _options.rangeEndMicros!) {
        return null;
      }
      if (message.snapshot && (!_firstPass || _options.snapshot == RetainedSnapshotMode.skip)) {
        continue;
      }
      var playMicros = _playMicrosAt(message.offsetMicros);
      _lastOriginalMicros = message.offsetMicros;
      _lastPlayMicrosRead = playMicros;
      _passMessages++;
      return _Scheduled(message, playMicros);
    }
  }

  // the play time of an offset after the last read message, with a long gap shortened
  int _playMicrosAt(int offsetMicros) {
    var gap = max(0, offsetMicros - _lastOriginalMicros);
    var limit = _options.compressGapsOverMicros;
    return _lastPlayMicrosRead + (limit != null && gap > limit ? limit : gap);
  }

  Future<void> _run(int generation) async {
    while (_state == PlaybackState.playing && generation == _generation) {
      if (_next == null && !_atEnd) {
        await _fill();
        continue;
      }
      var next = _next;
      if (next == null) {
        await _endOfRange(generation);
        return;
      }
      var now = _stopwatch.elapsedMicroseconds;
      var due = _dueMicros(next.playMicros);
      if (due > now) {
        _timer = Timer(Duration(microseconds: due - now), () => _run(generation));
        return;
      }
      _next = null;
      _lastPublishWallMicros = now;
      if (!_publisher.isConnected) {
        _skipDisconnected(next);
        continue;
      }
      try {
        _publish(next, now - due);
      } on Exception {
        // the connection broke between the check and the publish
        _skipDisconnected(next);
        continue;
      }
      _publisherLost = false;
    }
  }

  // The message is due while the publisher has no connection. It is skipped so the schedule goes on and playback
  // resumes at the right place after a reconnect; the owner hears about the outage once.
  void _skipDisconnected(_Scheduled scheduled) {
    _lastPlayMicros = scheduled.playMicros;
    positionMicros = scheduled.message.offsetMicros;
    skipped++;
    _markProgress();
    if (!_publisherLost) {
      _publisherLost = true;
      connectionLostEvent.broadcast();
    }
  }

  int _dueMicros(int playMicros) {
    if (_options.isMaxSpeed) {
      return sent + skipped == 0 ? 0 : _lastPublishWallMicros + (Duration.microsecondsPerSecond / max(1, maxRate)).round();
    }
    return _baseWallMicros + ((playMicros - _basePlayMicros) / _options.speed).round();
  }

  // A loop pass ends at the range end, not at its last message, and lasts at least minLoopPass. A pass after the first
  // that had nothing to play (e.g. a recording of only the retained snapshot) ends the playback.
  Future<void> _endOfRange(int generation) async {
    if (!_options.loop || (!_firstPass && _passMessages == 0)) {
      await stop();
      finishedEvent.broadcast();
      return;
    }
    var now = _stopwatch.elapsedMicroseconds;
    var passEnd = max(_passStartWallMicros + minLoopPass.inMicroseconds,
        _options.isMaxSpeed ? 0 : _dueMicros(_playMicrosAt(max(rangeEndMicros, _lastOriginalMicros))));
    if (passEnd > now) {
      _timer = Timer(Duration(microseconds: passEnd - now), () => _run(generation));
      return;
    }
    loopCount++;
    _firstPass = false;
    await _openRange();
    _passStartWallMicros = _stopwatch.elapsedMicroseconds;
    _baseWallMicros = _passStartWallMicros;
    _basePlayMicros = 0;
    if (generation == _generation) {
      _run(generation);
    }
  }

  // the schedule continues from the last sent message at the current time
  void _rebase() {
    _baseWallMicros = _stopwatch.elapsedMicroseconds;
    _basePlayMicros = _lastPlayMicros;
  }

  void _publish(_Scheduled scheduled, int lateMicros) {
    var message = scheduled.message;
    _lastPlayMicros = scheduled.playMicros;
    positionMicros = message.offsetMicros;
    lagMicros = max(0, lateMicros);
    if (message.truncated) {
      skipped++;
      _markProgress();
      return;
    }
    bool retain;
    switch (_options.retain) {
      case RetainOverride.asRecorded:
        retain = message.retain || message.snapshot;
      case RetainOverride.never:
        retain = false;
      case RetainOverride.always:
        retain = true;
    }
    _send(message, retain: retain);
    _markProgress();
  }

  void _send(RecordedMessage message, {required bool retain}) {
    var properties = _options.republishProperties && _publisher.supportsProperties ? message.properties : null;
    var topic = mapTopic?.call(message.topic) ?? _options.remap(message.topic);
    _publisher.publish(topic, Uint8Buffer()..addAll(message.payload), _options.qos ?? message.qos, retain, properties);
    sent++;
    onPublished?.call(message, topic);
  }

  void _setState(PlaybackState state) {
    _state = state;
    stateChangedEvent.broadcast();
    progressChangedEvent.broadcast();
  }

  void _markProgress() {
    _progressDirty = true;
    _progressTimer ??= Timer(progressInterval, () {
      _progressTimer = null;
      if (_progressDirty) {
        _progressDirty = false;
        progressChangedEvent.broadcast();
      }
    });
  }
}
