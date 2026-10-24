import 'dart:async';
import 'dart:math';
import 'package:clock/clock.dart';
import 'package:event/event.dart';
import 'package:mqttstudio/recorder/format/recording_reader.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
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
  final RecordingReader reader;
  final SimulatorPublisher _publisher;
  // msg/s at Max speed (R12)
  double maxRate;
  final Duration progressInterval;
  PlaybackOptions _options;

  final stateChangedEvent = Event();
  // raised at most once per progressInterval
  final progressChangedEvent = Event();
  // the publisher lost its connection; playback has stopped
  final connectionLostEvent = Event();
  // the end of the range was reached without loop
  final finishedEvent = Event();

  PlaybackState _state = PlaybackState.stopped;
  RecordingCursor? _cursor;
  // the next message, read but not yet due
  _Scheduled? _next;
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

  RecordingPlayer(this.reader, PlaybackOptions options, this._publisher,
      {this.maxRate = 1000, this.progressInterval = const Duration(milliseconds: 250)})
      : _options = options.copy();

  PlaybackState get state => _state;

  PlaybackOptions get options => _options;

  bool get isPlaying => _state == PlaybackState.playing;

  int get rangeStartMicros => _options.rangeStartMicros ?? 0;

  int get rangeEndMicros => _options.rangeEndMicros ?? reader.footer?.durationMicros ?? 0;

  // msg/s of the selected topics at the given options, and the busiest second (§6.2)
  static ({double rate, double peak}) estimate(RecordingInfo info, PlaybackOptions options, {double maxRate = 1000}) {
    var summary = info.footer.summary;
    // a recording shorter than a second counts as one, its messages can't come faster than its peak second
    var seconds = max(1.0, info.footer.duration.inMicroseconds / Duration.microsecondsPerSecond);
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
    var next = _next ?? await _read(generation);
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
    if (_options.snapshot == RetainedSnapshotMode.publish && rangeStartMicros > 0) {
      await _publishStateAtRangeStart();
    }
    await _openRange();
    _stopwatch
      ..reset()
      ..start();
    _baseWallMicros = 0;
    _basePlayMicros = 0;
    _lastPublishWallMicros = 0;
  }

  Future<void> _openRange() async {
    var seek = reader.seekEntryFor(rangeStartMicros);
    _cursor = reader.cursor(from: seek?.position);
    _next = null;
    _lastPlayMicros = 0;
    _lastPlayMicrosRead = 0;
    _lastOriginalMicros = rangeStartMicros;
    positionMicros = rangeStartMicros;
  }

  // with a range, the state at its start is the last retained message of each topic before it
  Future<void> _publishStateAtRangeStart() async {
    var state = <String, RecordedMessage>{};
    var cursor = reader.cursor();
    for (var entry = await cursor.next(); entry != null; entry = await cursor.next()) {
      if (entry is! MessageEntry) {
        continue;
      }
      var message = entry.message;
      if (message.offsetMicros >= rangeStartMicros) {
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

  Future<_Scheduled?> _read(int generation) async {
    while (true) {
      var entry = await _cursor?.next();
      if (entry == null || generation != _generation) {
        return null;
      }
      if (entry is! MessageEntry) {
        continue;
      }
      var message = entry.message;
      if (message.offsetMicros < rangeStartMicros || !_options.plays(message.topic)) {
        continue;
      }
      if (_options.rangeEndMicros != null && message.offsetMicros > _options.rangeEndMicros!) {
        return null;
      }
      if (message.snapshot && (!_firstPass || _options.snapshot == RetainedSnapshotMode.skip)) {
        continue;
      }
      var gap = max(0, message.offsetMicros - _lastOriginalMicros);
      var limit = _options.compressGapsOverMicros;
      var playMicros = _lastPlayMicrosRead + (limit != null && gap > limit ? limit : gap);
      _lastOriginalMicros = message.offsetMicros;
      _lastPlayMicrosRead = playMicros;
      return _Scheduled(message, playMicros);
    }
  }

  Future<void> _run(int generation) async {
    while (_state == PlaybackState.playing && generation == _generation) {
      var next = _next ?? await _read(generation);
      if (generation != _generation || _state != PlaybackState.playing) {
        return;
      }
      if (next == null) {
        await _endOfRange(generation);
        return;
      }
      _next = next;
      var now = _stopwatch.elapsedMicroseconds;
      var due = _dueMicros(next);
      if (due > now) {
        _timer = Timer(Duration(microseconds: due - now), () => _run(generation));
        return;
      }
      _next = null;
      if (!_publisher.isConnected) {
        await stop();
        connectionLostEvent.broadcast();
        return;
      }
      _publish(next, now - due);
      _lastPublishWallMicros = now;
    }
  }

  int _dueMicros(_Scheduled next) {
    if (_options.isMaxSpeed) {
      return sent == 0 ? 0 : _lastPublishWallMicros + (Duration.microsecondsPerSecond / max(1, maxRate)).round();
    }
    return _baseWallMicros + ((next.playMicros - _basePlayMicros) / _options.speed).round();
  }

  Future<void> _endOfRange(int generation) async {
    if (!_options.loop) {
      await stop();
      finishedEvent.broadcast();
      return;
    }
    loopCount++;
    _firstPass = false;
    await _openRange();
    _baseWallMicros = _stopwatch.elapsedMicroseconds;
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
    _publisher.publish(_options.remap(message.topic), Uint8Buffer()..addAll(message.payload), _options.qos ?? message.qos,
        retain, properties);
    sent++;
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
