import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:mqttstudio/simulator/engine/placeholders.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';

// One generated payload. Text is sent UTF-8 encoded, bytes as they are.
class GeneratedValue {
  final String? text;
  final Uint8List? bytes;
  // named sub-values a template can insert with {{field.part}}, e.g. lat and lon of a GPS position
  final Map<String, String> parts;
  // content type the message is sent with when the topic does not set one
  final String? contentType;
  // shown instead of binary content, e.g. the image file name
  final String? label;

  const GeneratedValue.text(String this.text, {this.parts = const {}, this.contentType})
      : bytes = null,
        label = null;

  const GeneratedValue.binary(Uint8List this.bytes, {this.contentType, this.label})
      : text = null,
        parts = const {};

  bool get isBinary => bytes != null;

  Uint8List get payload => bytes ?? Uint8List.fromList(utf8.encode(text!));

  // short form for statistics and previews
  String describe({int maxLength = 200}) {
    if (bytes != null) {
      var size = '<binary ${(bytes!.length / 1000).toStringAsFixed(1)} KB>';
      return label == null ? size : '$size $label';
    }
    return text!.length > maxLength ? '${text!.substring(0, maxLength)}…' : text!;
  }
}

class GeneratorContext {
  final Random random;
  // value of {n}
  final int instanceNumber;
  final String deviceName;
  // time base of the wave generator
  final DateTime startedAt;

  GeneratorContext({required this.random, this.instanceNumber = 1, this.deviceName = '', required this.startedAt});
}

enum GeneratorError {
  notSupportedInBrowser,
  imageFolderNotFound,
  noUsableImages,
  imageUnreadable,
  routeTooShort,
  invalidTemplateField,
}

class GeneratorException implements Exception {
  final GeneratorError error;
  final String detail;

  GeneratorException(this.error, [this.detail = '']);

  String get message {
    switch (error) {
      case GeneratorError.notSupportedInBrowser:
        return 'Random image is not supported in the browser';
      case GeneratorError.imageFolderNotFound:
        return 'Image folder not found: $detail';
      case GeneratorError.noUsableImages:
        return 'No usable images in $detail';
      case GeneratorError.imageUnreadable:
        return 'Cannot read image $detail';
      case GeneratorError.routeTooShort:
        return 'A GPS route needs at least 2 waypoints';
      case GeneratorError.invalidTemplateField:
        return 'Template field $detail cannot use this generator';
    }
  }

  @override
  String toString() => message;
}

// The running state of a generator for one instance of a simulated topic.
abstract class GeneratorInstance {
  // elapsed: time since the previous message of this instance, or since its start for the first one
  GeneratedValue next(DateTime now, Duration elapsed);
}

// throws a GeneratorException when the generator cannot run, e.g. an image folder that does not exist
GeneratorInstance createGeneratorInstance(PayloadGenerator generator, GeneratorContext context) {
  switch (generator) {
    case RandomStringGenerator g:
      return _RandomStringInstance(g, context.random);
    case RandomNumberGenerator g:
      return _RandomNumberInstance(g, context.random);
    case CounterGenerator g:
      return _CounterInstance(g);
    case BoolGenerator g:
      return _BoolInstance(g, context.random);
    case ValueListGenerator g:
      return _ValueListInstance(g, context.random);
    case RandomWalkGenerator g:
      return _RandomWalkInstance(g, context.random);
    case WaveGenerator g:
      return _WaveInstance(g, context);
    case TimestampGenerator g:
      return _TimestampInstance(g);
    case GpsTrackGenerator g:
      return _GpsTrackInstance(g, context.random);
    case RandomImageGenerator g:
      return _RandomImageInstance(g, context.random);
    case TemplateGenerator g:
      return _TemplateInstance(g, context);
  }
}

String formatNumber(double value, int decimals) {
  if (decimals <= 0) {
    return value.round().toString();
  }
  var text = value.toStringAsFixed(decimals);
  // -0.00 when a negative value rounds to zero
  return double.parse(text) == 0 ? (0.0).toStringAsFixed(decimals) : text;
}

double _seconds(Duration duration) => duration.inMicroseconds / Duration.microsecondsPerSecond;

double _uniform(Random random) => random.nextDouble() * 2 - 1;

class _RandomStringInstance implements GeneratorInstance {
  final RandomStringGenerator g;
  final Random random;

  _RandomStringInstance(this.g, this.random);

  @override
  GeneratedValue next(DateTime now, Duration elapsed) {
    var minLength = max(0, min(g.minLength, g.maxLength));
    var maxLength = max(0, max(g.minLength, g.maxLength));
    var length = minLength + random.nextInt(maxLength - minLength + 1);
    var buffer = StringBuffer(g.prefix);
    if (g.charSet.isNotEmpty) {
      for (var i = 0; i < length; i++) {
        buffer.write(g.charSet[random.nextInt(g.charSet.length)]);
      }
    }
    buffer.write(g.postfix);
    return GeneratedValue.text(buffer.toString());
  }
}

class _RandomNumberInstance implements GeneratorInstance {
  final RandomNumberGenerator g;
  final Random random;

  _RandomNumberInstance(this.g, this.random);

  @override
  GeneratedValue next(DateTime now, Duration elapsed) {
    var low = min(g.min, g.max);
    var high = max(g.min, g.max);
    var value = low + random.nextDouble() * (high - low);
    return GeneratedValue.text('${g.prefix}${formatNumber(value, g.decimals)}${g.postfix}');
  }
}

class _CounterInstance implements GeneratorInstance {
  final CounterGenerator g;
  int _index = 0;

  _CounterInstance(this.g);

  @override
  GeneratedValue next(DateTime now, Duration elapsed) {
    var value = g.start + g.step * _index;
    _index++;
    if (g.resetAfter != null && g.resetAfter! > 0 && _index >= g.resetAfter!) {
      _index = 0;
    }
    return GeneratedValue.text('${g.prefix}${formatNumber(value, g.decimals)}${g.postfix}');
  }
}

class _BoolInstance implements GeneratorInstance {
  final BoolGenerator g;
  final Random random;

  _BoolInstance(this.g, this.random);

  @override
  GeneratedValue next(DateTime now, Duration elapsed) =>
      GeneratedValue.text(random.nextDouble() < g.trueProbability ? g.trueText : g.falseText);
}

class _ValueListInstance implements GeneratorInstance {
  final ValueListGenerator g;
  final Random random;
  int _index = 0;

  _ValueListInstance(this.g, this.random);

  @override
  GeneratedValue next(DateTime now, Duration elapsed) {
    if (g.values.isEmpty) {
      return GeneratedValue.text('');
    }
    if (g.order == PickOrder.random) {
      return GeneratedValue.text(g.values[random.nextInt(g.values.length)]);
    }
    var value = g.values[_index % g.values.length];
    _index = (_index + 1) % g.values.length;
    return GeneratedValue.text(value);
  }
}

class _RandomWalkInstance implements GeneratorInstance {
  final RandomWalkGenerator g;
  final Random random;
  late final double _low = min(g.min, g.max);
  late final double _high = max(g.min, g.max);
  late double _value = g.start.clamp(_low, _high).toDouble();

  _RandomWalkInstance(this.g, this.random);

  @override
  GeneratedValue next(DateTime now, Duration elapsed) {
    var step = _uniform(random) * g.volatility * sqrt(max(0, _seconds(elapsed)));
    _value = reflect(_value + step, _low, _high);
    return GeneratedValue.text('${g.prefix}${formatNumber(_value, g.decimals)}${g.postfix}');
  }

  // mirrors a value that left [low, high] back inside, also for steps larger than the range
  static double reflect(double value, double low, double high) {
    var range = high - low;
    if (range <= 0) {
      return low;
    }
    var offset = (value - low) % (2 * range);
    if (offset < 0) {
      offset += 2 * range;
    }
    return offset <= range ? low + offset : low + 2 * range - offset;
  }
}

class _WaveInstance implements GeneratorInstance {
  final WaveGenerator g;
  final GeneratorContext context;

  _WaveInstance(this.g, this.context);

  @override
  GeneratedValue next(DateTime now, Duration elapsed) {
    var t = _seconds(now.difference(context.startedAt));
    var period = g.periodSeconds > 0 ? g.periodSeconds : 1;
    var x = 2 * pi * t / period + g.phaseDegrees * pi / 180;
    var value = g.offset + g.amplitude * shapeAt(g.shape, x) + g.noise * _uniform(context.random);
    return GeneratedValue.text('${g.prefix}${formatNumber(value, g.decimals)}${g.postfix}');
  }

  // value of the shape between -1 and 1 at the angle x
  static double shapeAt(WaveShape shape, double x) {
    switch (shape) {
      case WaveShape.sine:
        return sin(x);
      case WaveShape.square:
        return sin(x) >= 0 ? 1 : -1;
      case WaveShape.triangle:
        return 2 / pi * asin(sin(x));
      case WaveShape.sawtooth:
        var cycle = x / (2 * pi);
        return 2 * (cycle - cycle.floorToDouble()) - 1;
    }
  }
}

class _TimestampInstance implements GeneratorInstance {
  final TimestampGenerator g;
  late final DateFormat? _dateFormat = g.format == TimestampFormat.pattern ? DateFormat(g.pattern) : null;

  _TimestampInstance(this.g);

  @override
  GeneratedValue next(DateTime now, Duration elapsed) {
    var time = g.utc ? now.toUtc() : now.toLocal();
    switch (g.format) {
      case TimestampFormat.iso8601:
        return GeneratedValue.text(time.toIso8601String());
      case TimestampFormat.epochMillis:
        return GeneratedValue.text('${now.millisecondsSinceEpoch}');
      case TimestampFormat.epochSeconds:
        return GeneratedValue.text('${now.millisecondsSinceEpoch ~/ 1000}');
      case TimestampFormat.pattern:
        return GeneratedValue.text(_dateFormat!.format(time));
    }
  }
}

// Positions on a small area of the earth, a flat projection is accurate enough for a simulated track.
class GeoMath {
  static const double earthRadius = 6371000;

  static double _rad(double degrees) => degrees * pi / 180;
  static double _deg(double radians) => radians * 180 / pi;

  static GpsPoint destination(GpsPoint from, double meters, double bearingRadians) {
    var dLat = meters * cos(bearingRadians) / earthRadius;
    var dLon = meters * sin(bearingRadians) / (earthRadius * cos(_rad(from.lat)));
    return GpsPoint(from.lat + _deg(dLat), from.lon + _deg(dLon));
  }

  static double distance(GpsPoint a, GpsPoint b) {
    var x = _rad(b.lon - a.lon) * cos(_rad((a.lat + b.lat) / 2));
    var y = _rad(b.lat - a.lat);
    return earthRadius * sqrt(x * x + y * y);
  }

  static double bearing(GpsPoint from, GpsPoint to) {
    var x = _rad(to.lon - from.lon) * cos(_rad((from.lat + to.lat) / 2));
    var y = _rad(to.lat - from.lat);
    return atan2(x, y);
  }
}

class _GpsTrackInstance implements GeneratorInstance {
  static const double _turnBackSpread = 30 * pi / 180;

  final GpsTrackGenerator g;
  final Random random;
  late GpsPoint _position;
  double _heading = 0;
  // route mode: distance travelled along the route
  double _routeOffset = 0;
  late final List<double> _segmentLengths;
  late final double _routeLength;

  _GpsTrackInstance(this.g, this.random) {
    var center = GpsPoint(g.centerLat, g.centerLon);
    if (g.mode == GpsMode.wander) {
      // every instance starts somewhere else inside the area
      _position = GeoMath.destination(center, g.radiusMeters * sqrt(random.nextDouble()), random.nextDouble() * 2 * pi);
      _heading = random.nextDouble() * 2 * pi;
      return;
    }
    if (g.waypoints.length < 2) {
      throw GeneratorException(GeneratorError.routeTooShort);
    }
    _segmentLengths = [
      for (var i = 0; i < g.waypoints.length; i++)
        GeoMath.distance(g.waypoints[i], g.waypoints[(i + 1) % g.waypoints.length])
    ];
    _routeLength = _segmentLengths.fold(0, (sum, length) => sum + length);
    _routeOffset = random.nextDouble() * _routeLength;
    _position = _pointOnRoute(_routeOffset);
  }

  @override
  GeneratedValue next(DateTime now, Duration elapsed) {
    var seconds = max(0.0, _seconds(elapsed));
    if (g.mode == GpsMode.wander) {
      _wander(seconds);
    } else if (_routeLength > 0) {
      _routeOffset = (_routeOffset + g.speedMps * seconds) % _routeLength;
      _position = _pointOnRoute(_routeOffset);
    }

    var lat = _position.lat.toStringAsFixed(g.decimals);
    var lon = _position.lon.toStringAsFixed(g.decimals);
    var text = g.format == GpsFormat.latLon ? '$lat,$lon' : '{"lat":$lat,"lon":$lon}';
    return GeneratedValue.text(text, parts: {'lat': lat, 'lon': lon});
  }

  void _wander(double seconds) {
    var center = GpsPoint(g.centerLat, g.centerLon);
    var distance = g.speedMps * seconds;
    _heading += _uniform(random) * g.turnRateDegPerSecond * pi / 180 * seconds;
    var candidate = GeoMath.destination(_position, distance, _heading);
    if (GeoMath.distance(center, candidate) > g.radiusMeters) {
      _heading = GeoMath.bearing(_position, center) + _uniform(random) * _turnBackSpread;
      candidate = GeoMath.destination(_position, distance, _heading);
      if (GeoMath.distance(center, candidate) > g.radiusMeters) {
        // a step longer than the area: stay just inside its edge
        candidate = GeoMath.destination(center, g.radiusMeters * 0.9, GeoMath.bearing(center, candidate));
      }
    }
    _position = candidate;
  }

  GpsPoint _pointOnRoute(double offset) {
    var remaining = offset;
    for (var i = 0; i < _segmentLengths.length; i++) {
      var length = _segmentLengths[i];
      if (remaining <= length || i == _segmentLengths.length - 1) {
        var from = g.waypoints[i];
        var to = g.waypoints[(i + 1) % g.waypoints.length];
        var fraction = length == 0 ? 0 : (remaining / length).clamp(0, 1);
        return GpsPoint(from.lat + (to.lat - from.lat) * fraction, from.lon + (to.lon - from.lon) * fraction);
      }
      remaining -= length;
    }
    return g.waypoints.first;
  }
}

class _RandomImageInstance implements GeneratorInstance {
  final RandomImageGenerator g;
  final Random random;
  late final List<File> _files;
  int _index = 0;

  _RandomImageInstance(this.g, this.random) {
    if (kIsWeb) {
      throw GeneratorException(GeneratorError.notSupportedInBrowser);
    }
    var folder = Directory(g.folderPath);
    if (g.folderPath.isEmpty || !folder.existsSync()) {
      throw GeneratorException(GeneratorError.imageFolderNotFound, g.folderPath);
    }
    var extensions = g.extensions.map((e) => e.trim().toLowerCase()).toSet();
    _files = folder
        .listSync()
        .whereType<File>()
        .where((file) => extensions.contains(extensionOf(file.path)))
        .where((file) => file.lengthSync() <= RandomImageGenerator.maxFileSize)
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (_files.isEmpty) {
      throw GeneratorException(GeneratorError.noUsableImages, g.folderPath);
    }
  }

  static String extensionOf(String filePath) {
    var name = fileNameOf(filePath);
    var dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot).toLowerCase();
  }

  static String fileNameOf(String filePath) => filePath.split(RegExp(r'[\\/]')).last;

  static String? contentTypeOf(String filePath) {
    switch (extensionOf(filePath)) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
    }
    return null;
  }

  @override
  GeneratedValue next(DateTime now, Duration elapsed) {
    File file;
    if (g.order == PickOrder.random) {
      file = _files[random.nextInt(_files.length)];
    } else {
      file = _files[_index];
      _index = (_index + 1) % _files.length;
    }
    try {
      return GeneratedValue.binary(file.readAsBytesSync(),
          contentType: contentTypeOf(file.path), label: fileNameOf(file.path));
    } on FileSystemException {
      throw GeneratorException(GeneratorError.imageUnreadable, file.path);
    }
  }
}

// A reference to a template field: {{name}} or {{name.part}}
final RegExp templateFieldPattern = RegExp(r'\{\{\s*([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z0-9_]+))?\s*\}\}');

class _TemplateInstance implements GeneratorInstance {
  final TemplateGenerator g;
  // the template split into texts with resolved placeholders and field references between them
  final List<String> _texts = [];
  final List<(String, String?)> _references = [];
  final Map<String, GeneratorInstance> _fields = {};

  _TemplateInstance(this.g, GeneratorContext context) {
    for (var entry in g.fields.entries) {
      if (!entry.value.type.allowedInTemplate) {
        throw GeneratorException(GeneratorError.invalidTemplateField, entry.key);
      }
      _fields[entry.key] = createGeneratorInstance(entry.value, context);
    }

    // placeholders are fixed per instance, so they are resolved once. Only outside of {{...}}, a field called n
    // must not be taken for {n}.
    var position = 0;
    for (var match in templateFieldPattern.allMatches(g.template)) {
      _texts.add(_resolve(g.template.substring(position, match.start), context));
      _references.add((match.group(1)!, match.group(2)));
      position = match.end;
    }
    _texts.add(_resolve(g.template.substring(position), context));
  }

  static String _resolve(String text, GeneratorContext context) =>
      Placeholders.resolve(text, instance: context.instanceNumber, deviceName: context.deviceName);

  @override
  GeneratedValue next(DateTime now, Duration elapsed) {
    // every field is generated once per message, so {{pos.lat}} and {{pos.lon}} belong to the same position
    var values = _fields.map((name, instance) => MapEntry(name, instance.next(now, elapsed)));
    var buffer = StringBuffer(_texts.first);
    for (var i = 0; i < _references.length; i++) {
      var (name, part) = _references[i];
      var value = values[name];
      if (value == null) {
        buffer.write(part == null ? '{{$name}}' : '{{$name.$part}}');
      } else {
        buffer.write(part == null ? value.text ?? '' : value.parts[part] ?? '');
      }
      buffer.write(_texts[i + 1]);
    }
    return GeneratedValue.text(buffer.toString(), contentType: g.validateJson ? 'application/json' : null);
  }
}
