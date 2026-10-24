import 'package:intl/intl.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';

// How the recorder shows sizes, durations and rates
class RecorderFormat {
  static final NumberFormat _count = NumberFormat.decimalPattern('en');
  static final DateFormat _date = DateFormat('dd.MM.yyyy HH:mm');
  static final DateFormat _time = DateFormat('HH:mm:ss');

  static String count(int value) => _count.format(value);

  static String bytes(num value) {
    if (value < 1024) {
      return '${value.round()} B';
    }
    if (value < 1024 * 1024) {
      return '${(value / 1024).toStringAsFixed(value < 10 * 1024 ? 1 : 0)} KB';
    }
    if (value < 1024 * 1024 * 1024) {
      return '${(value / 1024 / 1024).toStringAsFixed(value < 10 * 1024 * 1024 ? 1 : 0)} MB';
    }
    return '${(value / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  // 8h 00m, 12m 31s, 45s, 0.5 s
  static String duration(Duration value) {
    if (value.inHours > 0) {
      return '${value.inHours}h ${_two(value.inMinutes % 60)}m';
    }
    if (value.inMinutes > 0) {
      return '${value.inMinutes}m ${_two(value.inSeconds % 60)}s';
    }
    if (value.inSeconds >= 10) {
      return '${value.inSeconds}s';
    }
    if (value.inMilliseconds >= 1000) {
      return '${(value.inMilliseconds / 1000).toStringAsFixed(1)} s';
    }
    return '${value.inMilliseconds} ms';
  }

  // 01:02:03, for running clocks
  static String clock(Duration value) =>
      '${_two(value.inHours)}:${_two(value.inMinutes % 60)}:${_two(value.inSeconds % 60)}';

  static String date(DateTime value) => _date.format(value.toLocal());

  static String time(DateTime value) => _time.format(value.toLocal());

  static String rate(double perSecond) {
    if (perSecond >= 10) {
      return '≈ ${perSecond.round()} msg/s';
    }
    return '≈ ${perSecond.toStringAsFixed(perSecond >= 1 ? 1 : 2)} msg/s';
  }

  static String messagesPerSecond(double value) => value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

  static String speed(double speed) {
    if (speed == PlaybackOptions.maxSpeed) {
      return 'Max';
    }
    var text = speed == speed.roundToDouble() ? speed.toStringAsFixed(0) : speed.toString();
    return '$text×';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
