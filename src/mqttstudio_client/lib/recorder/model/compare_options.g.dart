// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'compare_options.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CompareOptions _$CompareOptionsFromJson(Map<String, dynamic> json) =>
    CompareOptions(
      remaps: (json['remaps'] as List<dynamic>?)
          ?.map((e) => TopicRemap.fromJson(e as Map<String, dynamic>))
          .toList(),
      counts: json['counts'] as bool? ?? true,
      countTolerance: (json['countTolerance'] as num?)?.toDouble() ?? 0,
      payloads: json['payloads'] as bool? ?? true,
      ignorePaths: (json['ignorePaths'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      numberTolerance: (json['numberTolerance'] as num?)?.toDouble() ?? 0,
      timing: json['timing'] as bool? ?? true,
      timingTolerance: (json['timingTolerance'] as num?)?.toDouble() ?? 10,
      rangeAFromMicros: (json['rangeAFromMicros'] as num?)?.toInt(),
      rangeAToMicros: (json['rangeAToMicros'] as num?)?.toInt(),
      rangeBFromMicros: (json['rangeBFromMicros'] as num?)?.toInt(),
      rangeBToMicros: (json['rangeBToMicros'] as num?)?.toInt(),
    );

Map<String, dynamic> _$CompareOptionsToJson(CompareOptions instance) =>
    <String, dynamic>{
      'remaps': instance.remaps.map((e) => e.toJson()).toList(),
      'counts': instance.counts,
      'countTolerance': instance.countTolerance,
      'payloads': instance.payloads,
      'ignorePaths': instance.ignorePaths,
      'numberTolerance': instance.numberTolerance,
      'timing': instance.timing,
      'timingTolerance': instance.timingTolerance,
      'rangeAFromMicros': instance.rangeAFromMicros,
      'rangeAToMicros': instance.rangeAToMicros,
      'rangeBFromMicros': instance.rangeBFromMicros,
      'rangeBToMicros': instance.rangeBToMicros,
    };

PayloadDifference _$PayloadDifferenceFromJson(Map<String, dynamic> json) =>
    PayloadDifference(
      (json['index'] as num).toInt(),
      (json['offsetAMicros'] as num).toInt(),
      (json['offsetBMicros'] as num).toInt(),
      json['payloadA'] as String?,
      json['payloadB'] as String?,
      json['path'] as String?,
    );

Map<String, dynamic> _$PayloadDifferenceToJson(PayloadDifference instance) =>
    <String, dynamic>{
      'index': instance.index,
      'offsetAMicros': instance.offsetAMicros,
      'offsetBMicros': instance.offsetBMicros,
      'payloadA': instance.payloadA,
      'payloadB': instance.payloadB,
      'path': instance.path,
    };

TopicComparison _$TopicComparisonFromJson(Map<String, dynamic> json) =>
    TopicComparison(
      json['topic'] as String,
      status:
          $enumDecodeNullable(_$TopicCompareStatusEnumMap, json['status']) ??
          TopicCompareStatus.equal,
      countA: (json['countA'] as num?)?.toInt() ?? 0,
      countB: (json['countB'] as num?)?.toInt() ?? 0,
      medianIntervalAMicros: (json['medianIntervalAMicros'] as num?)?.toInt(),
      medianIntervalBMicros: (json['medianIntervalBMicros'] as num?)?.toInt(),
      countDiffers: json['countDiffers'] as bool? ?? false,
      timingDiffers: json['timingDiffers'] as bool? ?? false,
      payloadsDiffer: json['payloadsDiffer'] as bool? ?? false,
      firstDifference: json['firstDifference'] == null
          ? null
          : PayloadDifference.fromJson(
              json['firstDifference'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$TopicComparisonToJson(TopicComparison instance) =>
    <String, dynamic>{
      'topic': instance.topic,
      'status': _$TopicCompareStatusEnumMap[instance.status]!,
      'countA': instance.countA,
      'countB': instance.countB,
      'medianIntervalAMicros': instance.medianIntervalAMicros,
      'medianIntervalBMicros': instance.medianIntervalBMicros,
      'countDiffers': instance.countDiffers,
      'timingDiffers': instance.timingDiffers,
      'payloadsDiffer': instance.payloadsDiffer,
      'firstDifference': instance.firstDifference?.toJson(),
    };

const _$TopicCompareStatusEnumMap = {
  TopicCompareStatus.equal: 'equal',
  TopicCompareStatus.different: 'different',
  TopicCompareStatus.onlyInA: 'onlyInA',
  TopicCompareStatus.onlyInB: 'onlyInB',
};

CompareResult _$CompareResultFromJson(Map<String, dynamic> json) =>
    CompareResult(
      json['recordingA'] as String,
      json['recordingB'] as String,
      CompareOptions.fromJson(json['options'] as Map<String, dynamic>),
      (json['topics'] as List<dynamic>)
          .map((e) => TopicComparison.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$CompareResultToJson(CompareResult instance) =>
    <String, dynamic>{
      'recordingA': instance.recordingA,
      'recordingB': instance.recordingB,
      'options': instance.options.toJson(),
      'topics': instance.topics.map((e) => e.toJson()).toList(),
    };
