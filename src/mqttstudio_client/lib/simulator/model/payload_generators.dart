import 'package:json_annotation/json_annotation.dart';

// use 'dart run build_runner build' to run the code generator
part 'payload_generators.g.dart';

// The payload generators of a simulated topic. They are configuration only: the state that changes while a
// simulation runs (counter value, walk position, ...) lives in the GeneratorInstance the engine creates on start.
enum GeneratorType {
  randomString('randomString'),
  randomNumber('randomNumber'),
  counter('counter'),
  boolean('bool'),
  valueList('valueList'),
  randomWalk('randomWalk'),
  wave('wave'),
  timestamp('timestamp'),
  gpsTrack('gpsTrack'),
  randomImage('randomImage'),
  template('template');

  final String key;
  const GeneratorType(this.key);

  static GeneratorType? fromKey(Object? key) {
    for (var type in values) {
      if (type.key == key) {
        return type;
      }
    }
    return null;
  }

  // generators a template field may use: no nesting and no binary payloads
  bool get allowedInTemplate => this != template && this != randomImage;
}

enum PickOrder { random, sequential }

enum WaveShape { sine, square, triangle, sawtooth }

enum TimestampFormat { iso8601, epochMillis, epochSeconds, pattern }

enum GpsMode { wander, route }

enum GpsFormat { latLon, json }

sealed class PayloadGenerator {
  const PayloadGenerator();

  GeneratorType get type;

  Map<String, dynamic> toJson();

  static PayloadGenerator fromJson(Map<String, dynamic> json) {
    switch (GeneratorType.fromKey(json['type'])) {
      case GeneratorType.randomString:
        return RandomStringGenerator.fromJson(json);
      case GeneratorType.randomNumber:
        return RandomNumberGenerator.fromJson(json);
      case GeneratorType.counter:
        return CounterGenerator.fromJson(json);
      case GeneratorType.boolean:
        return BoolGenerator.fromJson(json);
      case GeneratorType.valueList:
        return ValueListGenerator.fromJson(json);
      case GeneratorType.randomWalk:
        return RandomWalkGenerator.fromJson(json);
      case GeneratorType.wave:
        return WaveGenerator.fromJson(json);
      case GeneratorType.timestamp:
        return TimestampGenerator.fromJson(json);
      case GeneratorType.gpsTrack:
        return GpsTrackGenerator.fromJson(json);
      case GeneratorType.randomImage:
        return RandomImageGenerator.fromJson(json);
      case GeneratorType.template:
        return TemplateGenerator.fromJson(json);
      case null:
        throw FormatException('Unknown generator type ${json['type']}');
    }
  }

  static Map<String, dynamic> toJsonStatic(PayloadGenerator generator) => generator.toJson();

  // the generator with its default parameters
  static PayloadGenerator defaultOf(GeneratorType type) {
    switch (type) {
      case GeneratorType.randomString:
        return const RandomStringGenerator();
      case GeneratorType.randomNumber:
        return const RandomNumberGenerator();
      case GeneratorType.counter:
        return const CounterGenerator();
      case GeneratorType.boolean:
        return const BoolGenerator();
      case GeneratorType.valueList:
        return const ValueListGenerator();
      case GeneratorType.randomWalk:
        return const RandomWalkGenerator();
      case GeneratorType.wave:
        return const WaveGenerator();
      case GeneratorType.timestamp:
        return const TimestampGenerator();
      case GeneratorType.gpsTrack:
        return const GpsTrackGenerator();
      case GeneratorType.randomImage:
        return const RandomImageGenerator();
      case GeneratorType.template:
        return TemplateGenerator.example();
    }
  }
}

Map<String, dynamic> _withType(GeneratorType type, Map<String, dynamic> json) => {'type': type.key, ...json};

@JsonSerializable()
class RandomStringGenerator extends PayloadGenerator {
  static const String defaultCharSet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  final int minLength;
  final int maxLength;
  final String charSet;
  final String prefix;
  final String postfix;

  const RandomStringGenerator(
      {this.minLength = 3,
      this.maxLength = 10,
      this.charSet = RandomStringGenerator.defaultCharSet,
      this.prefix = '',
      this.postfix = ''});

  @override
  GeneratorType get type => GeneratorType.randomString;

  factory RandomStringGenerator.fromJson(Map<String, dynamic> json) => _$RandomStringGeneratorFromJson(json);
  @override
  Map<String, dynamic> toJson() => _withType(type, _$RandomStringGeneratorToJson(this));
}

@JsonSerializable()
class RandomNumberGenerator extends PayloadGenerator {
  final double min;
  final double max;
  final int decimals;
  final String prefix;
  final String postfix;

  const RandomNumberGenerator({this.min = 0, this.max = 100, this.decimals = 0, this.prefix = '', this.postfix = ''});

  @override
  GeneratorType get type => GeneratorType.randomNumber;

  factory RandomNumberGenerator.fromJson(Map<String, dynamic> json) => _$RandomNumberGeneratorFromJson(json);
  @override
  Map<String, dynamic> toJson() => _withType(type, _$RandomNumberGeneratorToJson(this));
}

@JsonSerializable()
class CounterGenerator extends PayloadGenerator {
  final double start;
  final double step;
  final int decimals;
  // number of values before the counter starts again, null counts forever
  final int? resetAfter;
  final String prefix;
  final String postfix;

  const CounterGenerator(
      {this.start = 1, this.step = 1, this.decimals = 0, this.resetAfter, this.prefix = '', this.postfix = ''});

  @override
  GeneratorType get type => GeneratorType.counter;

  factory CounterGenerator.fromJson(Map<String, dynamic> json) => _$CounterGeneratorFromJson(json);
  @override
  Map<String, dynamic> toJson() => _withType(type, _$CounterGeneratorToJson(this));
}

@JsonSerializable()
class BoolGenerator extends PayloadGenerator {
  final double trueProbability;
  final String trueText;
  final String falseText;

  const BoolGenerator({this.trueProbability = 0.5, this.trueText = 'true', this.falseText = 'false'});

  @override
  GeneratorType get type => GeneratorType.boolean;

  factory BoolGenerator.fromJson(Map<String, dynamic> json) => _$BoolGeneratorFromJson(json);
  @override
  Map<String, dynamic> toJson() => _withType(type, _$BoolGeneratorToJson(this));
}

@JsonSerializable()
class ValueListGenerator extends PayloadGenerator {
  final List<String> values;
  final PickOrder order;

  const ValueListGenerator({this.values = const ['A', 'B', 'C'], this.order = PickOrder.random});

  @override
  GeneratorType get type => GeneratorType.valueList;

  factory ValueListGenerator.fromJson(Map<String, dynamic> json) => _$ValueListGeneratorFromJson(json);
  @override
  Map<String, dynamic> toJson() => _withType(type, _$ValueListGeneratorToJson(this));
}

@JsonSerializable()
class RandomWalkGenerator extends PayloadGenerator {
  final double start;
  final double min;
  final double max;
  // spread per square root of a second, so the drift over time does not depend on the publish interval
  final double volatility;
  final int decimals;
  final String prefix;
  final String postfix;

  const RandomWalkGenerator(
      {this.start = 20,
      this.min = 0,
      this.max = 40,
      this.volatility = 0.5,
      this.decimals = 1,
      this.prefix = '',
      this.postfix = ''});

  @override
  GeneratorType get type => GeneratorType.randomWalk;

  factory RandomWalkGenerator.fromJson(Map<String, dynamic> json) => _$RandomWalkGeneratorFromJson(json);
  @override
  Map<String, dynamic> toJson() => _withType(type, _$RandomWalkGeneratorToJson(this));
}

@JsonSerializable()
class WaveGenerator extends PayloadGenerator {
  final WaveShape shape;
  final double offset;
  final double amplitude;
  final double periodSeconds;
  final double phaseDegrees;
  final double noise;
  final int decimals;
  final String prefix;
  final String postfix;

  const WaveGenerator(
      {this.shape = WaveShape.sine,
      this.offset = 0,
      this.amplitude = 1,
      this.periodSeconds = 60,
      this.phaseDegrees = 0,
      this.noise = 0,
      this.decimals = 2,
      this.prefix = '',
      this.postfix = ''});

  @override
  GeneratorType get type => GeneratorType.wave;

  factory WaveGenerator.fromJson(Map<String, dynamic> json) => _$WaveGeneratorFromJson(json);
  @override
  Map<String, dynamic> toJson() => _withType(type, _$WaveGeneratorToJson(this));
}

@JsonSerializable()
class TimestampGenerator extends PayloadGenerator {
  final TimestampFormat format;
  // intl DateFormat pattern, used with TimestampFormat.pattern
  final String pattern;
  final bool utc;

  const TimestampGenerator({this.format = TimestampFormat.iso8601, this.pattern = 'yyyy-MM-dd HH:mm:ss', this.utc = true});

  @override
  GeneratorType get type => GeneratorType.timestamp;

  factory TimestampGenerator.fromJson(Map<String, dynamic> json) => _$TimestampGeneratorFromJson(json);
  @override
  Map<String, dynamic> toJson() => _withType(type, _$TimestampGeneratorToJson(this));
}

@JsonSerializable()
class GpsPoint {
  final double lat;
  final double lon;

  const GpsPoint(this.lat, this.lon);

  factory GpsPoint.fromJson(Map<String, dynamic> json) => _$GpsPointFromJson(json);
  Map<String, dynamic> toJson() => _$GpsPointToJson(this);
}

@JsonSerializable(explicitToJson: true)
class GpsTrackGenerator extends PayloadGenerator {
  final GpsMode mode;
  final double centerLat;
  final double centerLon;
  final double radiusMeters;
  final double turnRateDegPerSecond;
  // route mode: the track runs along these points and starts over at the first one
  final List<GpsPoint> waypoints;
  final double speedMps;
  final int decimals;
  final GpsFormat format;

  const GpsTrackGenerator(
      {this.mode = GpsMode.wander,
      this.centerLat = 48.137154,
      this.centerLon = 11.576124,
      this.radiusMeters = 1000,
      this.turnRateDegPerSecond = 15,
      this.waypoints = const [],
      this.speedMps = 10,
      this.decimals = 6,
      this.format = GpsFormat.latLon});

  @override
  GeneratorType get type => GeneratorType.gpsTrack;

  factory GpsTrackGenerator.fromJson(Map<String, dynamic> json) => _$GpsTrackGeneratorFromJson(json);
  @override
  Map<String, dynamic> toJson() => _withType(type, _$GpsTrackGeneratorToJson(this));
}

@JsonSerializable()
class RandomImageGenerator extends PayloadGenerator {
  // larger files are skipped, the same limit as publishing a file
  static const int maxFileSize = 500000;

  final String folderPath;
  final List<String> extensions;
  final PickOrder order;

  const RandomImageGenerator(
      {this.folderPath = '', this.extensions = const ['.jpg', '.jpeg', '.png'], this.order = PickOrder.random});

  @override
  GeneratorType get type => GeneratorType.randomImage;

  factory RandomImageGenerator.fromJson(Map<String, dynamic> json) => _$RandomImageGeneratorFromJson(json);
  @override
  Map<String, dynamic> toJson() => _withType(type, _$RandomImageGeneratorToJson(this));
}

@JsonSerializable(explicitToJson: true)
class TemplateGenerator extends PayloadGenerator {
  final String template;
  @JsonKey(fromJson: _fieldsFromJson, toJson: _fieldsToJson)
  final Map<String, PayloadGenerator> fields;
  final bool validateJson;

  const TemplateGenerator({this.template = '', this.fields = const {}, this.validateJson = true});

  factory TemplateGenerator.example() => TemplateGenerator(
        template: '{\n  "value": {{value}},\n  "ts": "{{ts}}"\n}',
        fields: {'value': const RandomWalkGenerator(), 'ts': const TimestampGenerator()},
      );

  @override
  GeneratorType get type => GeneratorType.template;

  factory TemplateGenerator.fromJson(Map<String, dynamic> json) => _$TemplateGeneratorFromJson(json);
  @override
  Map<String, dynamic> toJson() => _withType(type, _$TemplateGeneratorToJson(this));
}

Map<String, PayloadGenerator> _fieldsFromJson(Map<String, dynamic>? json) =>
    (json ?? {}).map((name, value) => MapEntry(name, PayloadGenerator.fromJson(value as Map<String, dynamic>)));

Map<String, dynamic> _fieldsToJson(Map<String, PayloadGenerator> fields) =>
    fields.map((name, generator) => MapEntry(name, generator.toJson()));
