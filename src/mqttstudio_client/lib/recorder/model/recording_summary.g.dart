// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recording_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TopicSummary _$TopicSummaryFromJson(Map<String, dynamic> json) => TopicSummary()
  ..count = (json['count'] as num).toInt()
  ..firstOffsetMicros = (json['firstOffsetMicros'] as num).toInt()
  ..lastOffsetMicros = (json['lastOffsetMicros'] as num).toInt()
  ..retainedCount = (json['retainedCount'] as num).toInt()
  ..snapshotCount = (json['snapshotCount'] as num).toInt()
  ..truncatedCount = (json['truncatedCount'] as num).toInt()
  ..payloadMin = (json['payloadMin'] as num).toInt()
  ..payloadMax = (json['payloadMax'] as num).toInt()
  ..payloadTotal = (json['payloadTotal'] as num).toInt()
  ..kinds = Map<String, int>.from(json['kinds'] as Map)
  ..intervalMinMicros = (json['intervalMinMicros'] as num?)?.toInt()
  ..intervalMaxMicros = (json['intervalMaxMicros'] as num?)?.toInt()
  ..intervalSumMicros = (json['intervalSumMicros'] as num).toInt()
  ..histogram = (json['histogram'] as List<dynamic>)
      .map((e) => (e as num).toInt())
      .toList()
  ..numericMin = (json['numericMin'] as num?)?.toDouble()
  ..numericMax = (json['numericMax'] as num?)?.toDouble()
  ..numericSum = (json['numericSum'] as num).toDouble()
  ..numericCount = (json['numericCount'] as num).toInt()
  ..consecutiveDuplicates = (json['consecutiveDuplicates'] as num).toInt()
  ..peakRatePerSecond = (json['peakRatePerSecond'] as num).toInt();

Map<String, dynamic> _$TopicSummaryToJson(TopicSummary instance) =>
    <String, dynamic>{
      'count': instance.count,
      'firstOffsetMicros': instance.firstOffsetMicros,
      'lastOffsetMicros': instance.lastOffsetMicros,
      'retainedCount': instance.retainedCount,
      'snapshotCount': instance.snapshotCount,
      'truncatedCount': instance.truncatedCount,
      'payloadMin': instance.payloadMin,
      'payloadMax': instance.payloadMax,
      'payloadTotal': instance.payloadTotal,
      'kinds': instance.kinds,
      'intervalMinMicros': instance.intervalMinMicros,
      'intervalMaxMicros': instance.intervalMaxMicros,
      'intervalSumMicros': instance.intervalSumMicros,
      'histogram': instance.histogram,
      'numericMin': instance.numericMin,
      'numericMax': instance.numericMax,
      'numericSum': instance.numericSum,
      'numericCount': instance.numericCount,
      'consecutiveDuplicates': instance.consecutiveDuplicates,
      'peakRatePerSecond': instance.peakRatePerSecond,
    };

RecordingSummary _$RecordingSummaryFromJson(Map<String, dynamic> json) =>
    RecordingSummary()
      ..messages = (json['messages'] as num).toInt()
      ..payloadBytes = (json['payloadBytes'] as num).toInt()
      ..peakRatePerSecond = (json['peakRatePerSecond'] as num).toInt()
      ..markers = Map<String, int>.from(json['markers'] as Map)
      ..perTopic = (json['perTopic'] as Map<String, dynamic>).map(
        (k, e) => MapEntry(k, TopicSummary.fromJson(e as Map<String, dynamic>)),
      );

Map<String, dynamic> _$RecordingSummaryToJson(RecordingSummary instance) =>
    <String, dynamic>{
      'messages': instance.messages,
      'payloadBytes': instance.payloadBytes,
      'peakRatePerSecond': instance.peakRatePerSecond,
      'markers': instance.markers,
      'perTopic': instance.perTopic.map((k, e) => MapEntry(k, e.toJson())),
    };
