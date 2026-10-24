// Durations on the command line: 90s, 15m, 8h, 1h30m, 500ms, 2d. A plain number is seconds.
class DurationParser {
  static final RegExp _part = RegExp(r'(\d+(?:\.\d+)?)(ms|d|h|m|s)');

  static Duration parse(String text) {
    var value = text.trim().toLowerCase();
    var seconds = double.tryParse(value);
    if (seconds != null && seconds >= 0) {
      return Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());
    }
    var matches = _part.allMatches(value).toList();
    if (matches.isEmpty || matches.map((m) => m.group(0)).join() != value) {
      throw FormatException('Not a duration: $text, use e.g. 90s, 15m or 1h30m');
    }
    var micros = 0.0;
    for (var match in matches) {
      var amount = double.parse(match.group(1)!);
      switch (match.group(2)) {
        case 'd':
          micros += amount * Duration.microsecondsPerDay;
        case 'h':
          micros += amount * Duration.microsecondsPerHour;
        case 'm':
          micros += amount * Duration.microsecondsPerMinute;
        case 's':
          micros += amount * Duration.microsecondsPerSecond;
        case 'ms':
          micros += amount * Duration.microsecondsPerMillisecond;
      }
    }
    return Duration(microseconds: micros.round());
  }

  // 10m 00s, 1h 02m 03s, 45s
  static String format(Duration duration) {
    var hours = duration.inHours;
    var minutes = duration.inMinutes % 60;
    var seconds = duration.inSeconds % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours}h ${two(minutes)}m ${two(seconds)}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${two(seconds)}s';
    }
    return '${seconds}s';
  }
}
