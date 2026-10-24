import 'dart:convert';
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:mqttstudio/common/utils/json_path.dart';
import 'package:mqttstudio/common/utils/payload_utils.dart';
import 'package:mqttstudio/recorder/format/recording_reader.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';

// Which number of a message a chart shows: the payload itself or a JSON path in it (doc/recorder-design.md §7.4)
class ValueSelector {
  // null for the payload as a number
  final JsonPath? path;

  const ValueSelector.payload() : path = null;

  const ValueSelector.json(JsonPath this.path);

  double? valueOf(RecordedMessage message) {
    if (message.truncated) {
      return null;
    }
    var text = utf8.decode(message.payload, allowMalformed: true);
    if (path == null) {
      return double.tryParse(text.trim());
    }
    try {
      var value = path!.evaluate(jsonDecode(text));
      if (value is num) {
        return value.toDouble();
      }
      return value is String ? double.tryParse(value.trim()) : null;
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => path?.toString() ?? 'payload';

  @override
  bool operator ==(Object other) => other is ValueSelector && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

class ValuePoint {
  final int offsetMicros;
  final double value;

  const ValuePoint(this.offsetMicros, this.value);
}

// The values of a topic in a range: thinned out points for drawing, statistics over all values
class ValueSeries {
  final List<ValuePoint> points;
  final double? min;
  final double? max;
  final double sum;
  final int count;
  // messages of the topic without a value at the path
  final int skipped;

  ValueSeries(this.points, {this.min, this.max, this.sum = 0, this.count = 0, this.skipped = 0});

  double? get average => count == 0 ? null : sum / count;
}

// Reads the values for the CHARTS tab in one pass over the range. Long series keep the lowest and the highest value
// of each of maxPoints / 2 time slices, so peaks stay visible.
class RecordingValues {
  static const int _yieldEvery = 2000;

  static Future<ValueSeries?> load(RecordingReader reader, String topic, ValueSelector selector,
      {int? fromMicros, int? toMicros, int maxPoints = 2000, bool Function()? isCancelled}) async {
    var from = fromMicros ?? 0;
    var to = toMicros ?? reader.footer!.durationMicros;
    var slices = max(1, maxPoints ~/ 2);
    var sliceLength = max(1, to - from) / slices;
    var low = List<ValuePoint?>.filled(slices, null);
    var high = List<ValuePoint?>.filled(slices, null);
    double? minValue;
    double? maxValue;
    var sum = 0.0;
    var count = 0;
    var skipped = 0;
    var completed = await _forEach(reader, topic, from, to, isCancelled, (message) {
      var value = selector.valueOf(message);
      if (value == null || value.isNaN || value.isInfinite) {
        skipped++;
        return;
      }
      count++;
      sum += value;
      minValue = minValue == null ? value : min(minValue!, value);
      maxValue = maxValue == null ? value : max(maxValue!, value);
      var slice = ((message.offsetMicros - from) / sliceLength).floor().clamp(0, slices - 1);
      var point = ValuePoint(message.offsetMicros, value);
      if (low[slice] == null || value < low[slice]!.value) {
        low[slice] = point;
      }
      if (high[slice] == null || value > high[slice]!.value) {
        high[slice] = point;
      }
    });
    if (!completed) {
      return null;
    }
    var points = <ValuePoint>[];
    for (var slice = 0; slice < slices; slice++) {
      var a = low[slice];
      var b = high[slice];
      if (a == null) {
        continue;
      }
      if (identical(a, b)) {
        points.add(a);
      } else if (a.offsetMicros <= b!.offsetMicros) {
        points..add(a)..add(b);
      } else {
        points..add(b)..add(a);
      }
    }
    return ValueSeries(points, min: minValue, max: maxValue, sum: sum, count: count, skipped: skipped);
  }

  // positions of a topic: payloads like "46.49,11.33" or two JSON paths. Every n-th position is kept.
  static Future<List<LatLng>?> track(RecordingReader reader, String topic,
      {JsonPath? latitude,
      JsonPath? longitude,
      int? fromMicros,
      int? toMicros,
      int maxPoints = 5000,
      bool Function()? isCancelled}) async {
    var expected = reader.footer!.summary.perTopic[topic]?.count ?? 0;
    var every = max(1, (expected / maxPoints).ceil());
    var seen = 0;
    var points = <LatLng>[];
    var completed = await _forEach(
        reader, topic, fromMicros ?? 0, toMicros ?? reader.footer!.durationMicros, isCancelled, (message) {
      if (seen++ % every != 0 || message.truncated) {
        return;
      }
      var point = _positionOf(message, latitude, longitude);
      if (point != null) {
        points.add(point);
      }
    });
    return completed ? points : null;
  }

  static LatLng? _positionOf(RecordedMessage message, JsonPath? latitude, JsonPath? longitude) {
    var text = utf8.decode(message.payload, allowMalformed: true);
    if (latitude == null || longitude == null) {
      return PayloadUtils.tryParseCoordinates(text);
    }
    var lat = ValueSelector.json(latitude).valueOf(message);
    var lon = ValueSelector.json(longitude).valueOf(message);
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
      return null;
    }
    return LatLng(lat, lon);
  }

  // false when cancelled
  static Future<bool> _forEach(RecordingReader reader, String topic, int from, int to, bool Function()? isCancelled,
      void Function(RecordedMessage message) visit) async {
    var cursor = reader.cursor(from: reader.seekEntryFor(from)?.position);
    var count = 0;
    while (true) {
      var entry = await cursor.next();
      if (entry == null) {
        return true;
      }
      if (entry is MessageEntry) {
        var message = entry.message;
        if (message.offsetMicros > to) {
          return true;
        }
        if (message.topic == topic && message.offsetMicros >= from) {
          visit(message);
        }
      }
      if (++count % _yieldEvery == 0) {
        await Future<void>.delayed(Duration.zero);
        if (isCancelled?.call() ?? false) {
          return false;
        }
      }
    }
  }
}
