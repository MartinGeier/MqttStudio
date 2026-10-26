import 'dart:math';

// Rates, time since the last message and interval jitter of one topic, for the tree viewer. The rates count the
// messages of the last [windowSeconds] seconds in buckets of one second. Retained messages the broker sends on
// subscribe don't count as intervals, they arrive all at once.
class TopicStats {
  static const int windowSeconds = 10;

  final List<int> _bucketSecond = List.filled(windowSeconds, -1);
  final List<int> _bucketCount = List.filled(windowSeconds, 0);
  final List<int> _bucketBytes = List.filled(windowSeconds, 0);
  DateTime? _first;
  DateTime? _last;
  DateTime? _lastLive;
  int count = 0;
  int totalBytes = 0;
  // Welford's running mean and variance of the intervals in microseconds
  int _intervals = 0;
  double _mean = 0;
  double _m2 = 0;

  DateTime? get lastReceived => _last;

  void add(DateTime receivedOn, int bytes, {bool retained = false}) {
    count++;
    totalBytes += bytes;
    _first ??= receivedOn;
    if (_last == null || receivedOn.isAfter(_last!)) {
      _last = receivedOn;
    }
    _addToBucket(receivedOn, bytes);
    if (retained) {
      return;
    }
    if (_lastLive != null) {
      var interval = receivedOn.difference(_lastLive!).inMicroseconds.toDouble();
      if (interval >= 0) {
        _intervals++;
        var delta = interval - _mean;
        _mean += delta / _intervals;
        _m2 += delta * (interval - _mean);
      }
    }
    _lastLive = receivedOn;
  }

  void _addToBucket(DateTime receivedOn, int bytes) {
    var second = receivedOn.millisecondsSinceEpoch ~/ 1000;
    var index = second % windowSeconds;
    if (_bucketSecond[index] == second) {
      _bucketCount[index]++;
      _bucketBytes[index] += bytes;
    } else if (_bucketSecond[index] < second) {
      _bucketSecond[index] = second;
      _bucketCount[index] = 1;
      _bucketBytes[index] = bytes;
    }
  }

  double messagesPerSecond(DateTime now) => _perSecond(now, _bucketCount);

  double bytesPerSecond(DateTime now) => _perSecond(now, _bucketBytes);

  // per second over the window, or over the time since the first message when that is shorter
  double _perSecond(DateTime now, List<int> values) {
    if (_first == null) {
      return 0;
    }
    var second = now.millisecondsSinceEpoch ~/ 1000;
    var sum = 0;
    for (var i = 0; i < windowSeconds; i++) {
      if (_bucketSecond[i] > second - windowSeconds && _bucketSecond[i] <= second) {
        sum += values[i];
      }
    }
    var firstSecond = _first!.millisecondsSinceEpoch ~/ 1000;
    var span = min(windowSeconds, max(1, second - firstSecond + 1));
    return sum / span;
  }

  Duration? sinceLast(DateTime now) {
    if (_last == null) {
      return null;
    }
    var since = now.difference(_last!);
    return since.isNegative ? Duration.zero : since;
  }

  // null until two messages arrived
  Duration? get meanInterval => _intervals == 0 ? null : Duration(microseconds: _mean.round());

  // the standard deviation of the intervals, null until three messages arrived
  Duration? get jitter => _intervals < 2 ? null : Duration(microseconds: sqrt(_m2 / (_intervals - 1)).round());

  static String formatRate(double value) {
    if (value == 0) {
      return '0';
    }
    if (value < 10) {
      return value.toStringAsFixed(1);
    }
    if (value < 1000) {
      return value.toStringAsFixed(0);
    }
    return '${(value / 1000).toStringAsFixed(1)}k';
  }

  static String formatBytesPerSecond(double value) {
    if (value < 1000) {
      return '${value.toStringAsFixed(0)} B/s';
    }
    if (value < 1000 * 1000) {
      return '${(value / 1000).toStringAsFixed(1)} kB/s';
    }
    return '${(value / 1000 / 1000).toStringAsFixed(1)} MB/s';
  }

  static String formatDuration(Duration value) {
    var micros = value.inMicroseconds;
    if (micros < 1000) {
      return '$micros µs';
    }
    if (micros < 1000 * 1000) {
      return '${(micros / 1000).toStringAsFixed(0)} ms';
    }
    var seconds = micros / 1000 / 1000;
    if (seconds < 60) {
      return '${seconds.toStringAsFixed(seconds < 10 ? 2 : 1)} s';
    }
    if (seconds < 3600) {
      return '${(seconds / 60).toStringAsFixed(1)} min';
    }
    return '${(seconds / 3600).toStringAsFixed(1)} h';
  }
}
