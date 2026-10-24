// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payload_generators.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RandomStringGenerator _$RandomStringGeneratorFromJson(
  Map<String, dynamic> json,
) => RandomStringGenerator(
  minLength: (json['minLength'] as num?)?.toInt() ?? 3,
  maxLength: (json['maxLength'] as num?)?.toInt() ?? 10,
  charSet: json['charSet'] as String? ?? RandomStringGenerator.defaultCharSet,
  prefix: json['prefix'] as String? ?? '',
  postfix: json['postfix'] as String? ?? '',
);

Map<String, dynamic> _$RandomStringGeneratorToJson(
  RandomStringGenerator instance,
) => <String, dynamic>{
  'minLength': instance.minLength,
  'maxLength': instance.maxLength,
  'charSet': instance.charSet,
  'prefix': instance.prefix,
  'postfix': instance.postfix,
};

RandomNumberGenerator _$RandomNumberGeneratorFromJson(
  Map<String, dynamic> json,
) => RandomNumberGenerator(
  min: (json['min'] as num?)?.toDouble() ?? 0,
  max: (json['max'] as num?)?.toDouble() ?? 100,
  decimals: (json['decimals'] as num?)?.toInt() ?? 0,
  prefix: json['prefix'] as String? ?? '',
  postfix: json['postfix'] as String? ?? '',
);

Map<String, dynamic> _$RandomNumberGeneratorToJson(
  RandomNumberGenerator instance,
) => <String, dynamic>{
  'min': instance.min,
  'max': instance.max,
  'decimals': instance.decimals,
  'prefix': instance.prefix,
  'postfix': instance.postfix,
};

CounterGenerator _$CounterGeneratorFromJson(Map<String, dynamic> json) =>
    CounterGenerator(
      start: (json['start'] as num?)?.toDouble() ?? 1,
      step: (json['step'] as num?)?.toDouble() ?? 1,
      decimals: (json['decimals'] as num?)?.toInt() ?? 0,
      resetAfter: (json['resetAfter'] as num?)?.toInt(),
      prefix: json['prefix'] as String? ?? '',
      postfix: json['postfix'] as String? ?? '',
    );

Map<String, dynamic> _$CounterGeneratorToJson(CounterGenerator instance) =>
    <String, dynamic>{
      'start': instance.start,
      'step': instance.step,
      'decimals': instance.decimals,
      'resetAfter': instance.resetAfter,
      'prefix': instance.prefix,
      'postfix': instance.postfix,
    };

BoolGenerator _$BoolGeneratorFromJson(Map<String, dynamic> json) =>
    BoolGenerator(
      trueProbability: (json['trueProbability'] as num?)?.toDouble() ?? 0.5,
      trueText: json['trueText'] as String? ?? 'true',
      falseText: json['falseText'] as String? ?? 'false',
    );

Map<String, dynamic> _$BoolGeneratorToJson(BoolGenerator instance) =>
    <String, dynamic>{
      'trueProbability': instance.trueProbability,
      'trueText': instance.trueText,
      'falseText': instance.falseText,
    };

ValueListGenerator _$ValueListGeneratorFromJson(Map<String, dynamic> json) =>
    ValueListGenerator(
      values:
          (json['values'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const ['A', 'B', 'C'],
      order:
          $enumDecodeNullable(_$PickOrderEnumMap, json['order']) ??
          PickOrder.random,
    );

Map<String, dynamic> _$ValueListGeneratorToJson(ValueListGenerator instance) =>
    <String, dynamic>{
      'values': instance.values,
      'order': _$PickOrderEnumMap[instance.order]!,
    };

const _$PickOrderEnumMap = {
  PickOrder.random: 'random',
  PickOrder.sequential: 'sequential',
};

RandomWalkGenerator _$RandomWalkGeneratorFromJson(Map<String, dynamic> json) =>
    RandomWalkGenerator(
      start: (json['start'] as num?)?.toDouble() ?? 20,
      min: (json['min'] as num?)?.toDouble() ?? 0,
      max: (json['max'] as num?)?.toDouble() ?? 40,
      volatility: (json['volatility'] as num?)?.toDouble() ?? 0.5,
      decimals: (json['decimals'] as num?)?.toInt() ?? 1,
      prefix: json['prefix'] as String? ?? '',
      postfix: json['postfix'] as String? ?? '',
    );

Map<String, dynamic> _$RandomWalkGeneratorToJson(
  RandomWalkGenerator instance,
) => <String, dynamic>{
  'start': instance.start,
  'min': instance.min,
  'max': instance.max,
  'volatility': instance.volatility,
  'decimals': instance.decimals,
  'prefix': instance.prefix,
  'postfix': instance.postfix,
};

WaveGenerator _$WaveGeneratorFromJson(Map<String, dynamic> json) =>
    WaveGenerator(
      shape:
          $enumDecodeNullable(_$WaveShapeEnumMap, json['shape']) ??
          WaveShape.sine,
      offset: (json['offset'] as num?)?.toDouble() ?? 0,
      amplitude: (json['amplitude'] as num?)?.toDouble() ?? 1,
      periodSeconds: (json['periodSeconds'] as num?)?.toDouble() ?? 60,
      phaseDegrees: (json['phaseDegrees'] as num?)?.toDouble() ?? 0,
      noise: (json['noise'] as num?)?.toDouble() ?? 0,
      decimals: (json['decimals'] as num?)?.toInt() ?? 2,
      prefix: json['prefix'] as String? ?? '',
      postfix: json['postfix'] as String? ?? '',
    );

Map<String, dynamic> _$WaveGeneratorToJson(WaveGenerator instance) =>
    <String, dynamic>{
      'shape': _$WaveShapeEnumMap[instance.shape]!,
      'offset': instance.offset,
      'amplitude': instance.amplitude,
      'periodSeconds': instance.periodSeconds,
      'phaseDegrees': instance.phaseDegrees,
      'noise': instance.noise,
      'decimals': instance.decimals,
      'prefix': instance.prefix,
      'postfix': instance.postfix,
    };

const _$WaveShapeEnumMap = {
  WaveShape.sine: 'sine',
  WaveShape.square: 'square',
  WaveShape.triangle: 'triangle',
  WaveShape.sawtooth: 'sawtooth',
};

TimestampGenerator _$TimestampGeneratorFromJson(Map<String, dynamic> json) =>
    TimestampGenerator(
      format:
          $enumDecodeNullable(_$TimestampFormatEnumMap, json['format']) ??
          TimestampFormat.iso8601,
      pattern: json['pattern'] as String? ?? 'yyyy-MM-dd HH:mm:ss',
      utc: json['utc'] as bool? ?? true,
    );

Map<String, dynamic> _$TimestampGeneratorToJson(TimestampGenerator instance) =>
    <String, dynamic>{
      'format': _$TimestampFormatEnumMap[instance.format]!,
      'pattern': instance.pattern,
      'utc': instance.utc,
    };

const _$TimestampFormatEnumMap = {
  TimestampFormat.iso8601: 'iso8601',
  TimestampFormat.epochMillis: 'epochMillis',
  TimestampFormat.epochSeconds: 'epochSeconds',
  TimestampFormat.pattern: 'pattern',
};

GpsPoint _$GpsPointFromJson(Map<String, dynamic> json) =>
    GpsPoint((json['lat'] as num).toDouble(), (json['lon'] as num).toDouble());

Map<String, dynamic> _$GpsPointToJson(GpsPoint instance) => <String, dynamic>{
  'lat': instance.lat,
  'lon': instance.lon,
};

GpsTrackGenerator _$GpsTrackGeneratorFromJson(Map<String, dynamic> json) =>
    GpsTrackGenerator(
      mode:
          $enumDecodeNullable(_$GpsModeEnumMap, json['mode']) ?? GpsMode.wander,
      centerLat: (json['centerLat'] as num?)?.toDouble() ?? 48.137154,
      centerLon: (json['centerLon'] as num?)?.toDouble() ?? 11.576124,
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 1000,
      turnRateDegPerSecond:
          (json['turnRateDegPerSecond'] as num?)?.toDouble() ?? 15,
      waypoints:
          (json['waypoints'] as List<dynamic>?)
              ?.map((e) => GpsPoint.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      speedMps: (json['speedMps'] as num?)?.toDouble() ?? 10,
      decimals: (json['decimals'] as num?)?.toInt() ?? 6,
      format:
          $enumDecodeNullable(_$GpsFormatEnumMap, json['format']) ??
          GpsFormat.latLon,
    );

Map<String, dynamic> _$GpsTrackGeneratorToJson(GpsTrackGenerator instance) =>
    <String, dynamic>{
      'mode': _$GpsModeEnumMap[instance.mode]!,
      'centerLat': instance.centerLat,
      'centerLon': instance.centerLon,
      'radiusMeters': instance.radiusMeters,
      'turnRateDegPerSecond': instance.turnRateDegPerSecond,
      'waypoints': instance.waypoints.map((e) => e.toJson()).toList(),
      'speedMps': instance.speedMps,
      'decimals': instance.decimals,
      'format': _$GpsFormatEnumMap[instance.format]!,
    };

const _$GpsModeEnumMap = {GpsMode.wander: 'wander', GpsMode.route: 'route'};

const _$GpsFormatEnumMap = {GpsFormat.latLon: 'latLon', GpsFormat.json: 'json'};

RandomImageGenerator _$RandomImageGeneratorFromJson(
  Map<String, dynamic> json,
) => RandomImageGenerator(
  folderPath: json['folderPath'] as String? ?? '',
  extensions:
      (json['extensions'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const ['.jpg', '.jpeg', '.png'],
  order:
      $enumDecodeNullable(_$PickOrderEnumMap, json['order']) ??
      PickOrder.random,
);

Map<String, dynamic> _$RandomImageGeneratorToJson(
  RandomImageGenerator instance,
) => <String, dynamic>{
  'folderPath': instance.folderPath,
  'extensions': instance.extensions,
  'order': _$PickOrderEnumMap[instance.order]!,
};

TemplateGenerator _$TemplateGeneratorFromJson(Map<String, dynamic> json) =>
    TemplateGenerator(
      template: json['template'] as String? ?? '',
      fields: json['fields'] == null
          ? const {}
          : _fieldsFromJson(json['fields'] as Map<String, dynamic>?),
      validateJson: json['validateJson'] as bool? ?? true,
    );

Map<String, dynamic> _$TemplateGeneratorToJson(TemplateGenerator instance) =>
    <String, dynamic>{
      'template': instance.template,
      'fields': _fieldsToJson(instance.fields),
      'validateJson': instance.validateJson,
    };
