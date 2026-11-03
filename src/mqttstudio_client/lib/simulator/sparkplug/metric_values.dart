import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/simulator/engine/generator_instances.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/sparkplug_source.dart';

// Turns the simulator's generated texts into values of a Sparkplug data type, and written values into the type of
// the metric (doc/sparkplug-design.md §10.3)
class SparkplugValues {
  static const Map<SpbDataType, (int, int)> _ranges = {
    SpbDataType.int8: (-128, 127),
    SpbDataType.int16: (-32768, 32767),
    SpbDataType.int32: (-2147483648, 2147483647),
    SpbDataType.uInt8: (0, 255),
    SpbDataType.uInt16: (0, 65535),
    SpbDataType.uInt32: (0, 4294967295),
  };

  // the types a simulated metric can have in v1 (Q7)
  static const List<SpbDataType> scalarTypes = [
    SpbDataType.boolean,
    SpbDataType.int8,
    SpbDataType.int16,
    SpbDataType.int32,
    SpbDataType.int64,
    SpbDataType.uInt8,
    SpbDataType.uInt16,
    SpbDataType.uInt32,
    SpbDataType.uInt64,
    SpbDataType.float,
    SpbDataType.double,
    SpbDataType.string,
    SpbDataType.text,
    SpbDataType.dateTime,
  ];

  // numbers from number generators, booleans from the boolean or a value list, dates from the timestamp generator;
  // texts from anything that writes text
  static bool generatorFits(SpbDataType type, PayloadGenerator generator) {
    if (isNumber(type)) {
      return generator is RandomNumberGenerator ||
          generator is CounterGenerator ||
          generator is RandomWalkGenerator ||
          generator is WaveGenerator;
    }
    return switch (type) {
      SpbDataType.boolean => generator is BoolGenerator || generator is ValueListGenerator,
      SpbDataType.dateTime => generator is TimestampGenerator,
      SpbDataType.string || SpbDataType.text || SpbDataType.uuid => generator is! RandomImageGenerator,
      _ => false,
    };
  }

  static bool isInteger(SpbDataType type) =>
      _ranges.containsKey(type) || type == SpbDataType.int64 || type == SpbDataType.uInt64;

  static bool isNumber(SpbDataType type) => isInteger(type) || type == SpbDataType.float || type == SpbDataType.double;

  // null when the text isn't a value of the type, e.g. letters for a number
  static Object? fromGenerated(GeneratedValue generated, SparkplugMetricSpec spec, DateTime now) {
    var text = _withoutAffixes(generated.text ?? '', spec.generator);
    var generator = spec.generator;
    switch (spec.type) {
      case SpbDataType.boolean:
        return generator is BoolGenerator ? text == generator.trueText : _bool(text);
      case SpbDataType.string || SpbDataType.text || SpbDataType.uuid:
        return text;
      case SpbDataType.dateTime:
        return now.toUtc();
      default:
        return coerce(double.tryParse(text.trim()), spec.type);
    }
  }

  // a value of a write (NCMD, DCMD) or a generator as the metric's type; null when it doesn't fit
  static Object? coerce(Object? value, SpbDataType type) {
    if (value is BigInt) {
      value = value.toInt();
    }
    switch (type) {
      case SpbDataType.boolean:
        return value is bool ? value : (value is num ? value != 0 : (value is String ? _bool(value) : null));
      case SpbDataType.string || SpbDataType.text || SpbDataType.uuid:
        return value?.toString();
      case SpbDataType.float || SpbDataType.double:
        return value is num ? value.toDouble() : (value is String ? double.tryParse(value) : null);
      case SpbDataType.dateTime:
        return value is DateTime
            ? value
            : (value is int ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true) : null);
      default:
        var number = value is num
            ? value
            : (value is String ? num.tryParse(value) : (value is bool ? (value ? 1 : 0) : null));
        if (number == null || !isInteger(type) || !number.isFinite) {
          return null;
        }
        var whole = number.round();
        var range = _ranges[type];
        if (range != null) {
          return whole.clamp(range.$1, range.$2);
        }
        return type == SpbDataType.uInt64 && whole < 0 ? 0 : whole;
    }
  }

  // report by exception: numbers only when they moved by more than the deadband
  static bool changed(Object? published, Object? value, SparkplugMetricSpec spec) {
    if (published is num && value is num) {
      return spec.deadband > 0 ? (value - published).abs() > spec.deadband : value != published;
    }
    return published != value;
  }

  static bool? _bool(String text) => switch (text.trim().toLowerCase()) {
    'true' || '1' || 'on' || 'yes' => true,
    'false' || '0' || 'off' || 'no' => false,
    _ => null,
  };

  // the generators' prefix and postfix belong to the text payload, not to the value
  static String _withoutAffixes(String text, PayloadGenerator generator) {
    var (prefix, postfix) = switch (generator) {
      RandomNumberGenerator g => (g.prefix, g.postfix),
      CounterGenerator g => (g.prefix, g.postfix),
      RandomWalkGenerator g => (g.prefix, g.postfix),
      WaveGenerator g => (g.prefix, g.postfix),
      _ => ('', ''),
    };
    if (prefix.isNotEmpty && text.startsWith(prefix)) {
      text = text.substring(prefix.length);
    }
    if (postfix.isNotEmpty && text.endsWith(postfix)) {
      text = text.substring(0, text.length - postfix.length);
    }
    return text;
  }
}
