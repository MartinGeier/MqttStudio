// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recording_header.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RecorderFilter _$RecorderFilterFromJson(Map<String, dynamic> json) =>
    RecorderFilter(
      json['filter'] as String,
      exclude: json['exclude'] as bool? ?? false,
      qos:
          $enumDecodeNullable(_$MqttQosEnumMap, json['qos']) ??
          MqttQos.exactlyOnce,
      color: json['color'] == null
          ? null
          : TopicColor.fromJson(json['color'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$RecorderFilterToJson(RecorderFilter instance) =>
    <String, dynamic>{
      'filter': instance.filter,
      'exclude': instance.exclude,
      'qos': _$MqttQosEnumMap[instance.qos]!,
      'color': instance.color?.toJson(),
    };

const _$MqttQosEnumMap = {
  MqttQos.atMostOnce: 'atMostOnce',
  MqttQos.atLeastOnce: 'atLeastOnce',
  MqttQos.exactlyOnce: 'exactlyOnce',
  MqttQos.reserved1: 'reserved1',
  MqttQos.failure: 'failure',
};

RecordingHeader _$RecordingHeaderFromJson(Map<String, dynamic> json) =>
    RecordingHeader(
      id: json['id'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      filters: (json['filters'] as List<dynamic>)
          .map((e) => RecorderFilter.fromJson(e as Map<String, dynamic>))
          .toList(),
      broker: json['broker'] as String,
      protocol: $enumDecode(_$MqttProtocolVersionEnumMap, json['protocol']),
      clientId: json['clientId'] as String,
      projectName: json['projectName'] as String?,
      appVersion: json['appVersion'] as String,
      origin:
          $enumDecodeNullable(_$RecordingOriginEnumMap, json['origin']) ??
          RecordingOrigin.live,
      sourceRecordingIds:
          (json['sourceRecordingIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );

Map<String, dynamic> _$RecordingHeaderToJson(RecordingHeader instance) =>
    <String, dynamic>{
      'id': instance.id,
      'startedAt': instance.startedAt.toIso8601String(),
      'filters': instance.filters.map((e) => e.toJson()).toList(),
      'broker': instance.broker,
      'protocol': _$MqttProtocolVersionEnumMap[instance.protocol]!,
      'clientId': instance.clientId,
      'projectName': instance.projectName,
      'appVersion': instance.appVersion,
      'origin': _$RecordingOriginEnumMap[instance.origin]!,
      'sourceRecordingIds': instance.sourceRecordingIds,
    };

const _$MqttProtocolVersionEnumMap = {
  MqttProtocolVersion.v311: 'v311',
  MqttProtocolVersion.v5: 'v5',
};

const _$RecordingOriginEnumMap = {
  RecordingOrigin.live: 'live',
  RecordingOrigin.flightRecorder: 'flightRecorder',
  RecordingOrigin.viewerBuffer: 'viewerBuffer',
  RecordingOrigin.edit: 'edit',
  RecordingOrigin.import: 'import',
};

Bookmark _$BookmarkFromJson(Map<String, dynamic> json) =>
    Bookmark((json['offsetMicros'] as num).toInt(), json['label'] as String);

Map<String, dynamic> _$BookmarkToJson(Bookmark instance) => <String, dynamic>{
  'offsetMicros': instance.offsetMicros,
  'label': instance.label,
};

SeekEntry _$SeekEntryFromJson(Map<String, dynamic> json) => SeekEntry(
  (json['offsetMicros'] as num).toInt(),
  (json['position'] as num).toInt(),
  (json['index'] as num).toInt(),
);

Map<String, dynamic> _$SeekEntryToJson(SeekEntry instance) => <String, dynamic>{
  'offsetMicros': instance.offsetMicros,
  'position': instance.position,
  'index': instance.index,
};

RecordingFooter _$RecordingFooterFromJson(Map<String, dynamic> json) =>
    RecordingFooter(
      name: json['name'] as String,
      notes: json['notes'] as String? ?? '',
      durationMicros: (json['durationMicros'] as num).toInt(),
      recovered: json['recovered'] as bool? ?? false,
      bookmarks: (json['bookmarks'] as List<dynamic>?)
          ?.map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
          .toList(),
      topics: (json['topics'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      summary: json['summary'] == null
          ? null
          : RecordingSummary.fromJson(json['summary'] as Map<String, dynamic>),
      seekIndex: (json['seekIndex'] as List<dynamic>?)
          ?.map((e) => SeekEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$RecordingFooterToJson(RecordingFooter instance) =>
    <String, dynamic>{
      'name': instance.name,
      'notes': instance.notes,
      'durationMicros': instance.durationMicros,
      'recovered': instance.recovered,
      'bookmarks': instance.bookmarks.map((e) => e.toJson()).toList(),
      'topics': instance.topics,
      'summary': instance.summary.toJson(),
      'seekIndex': instance.seekIndex.map((e) => e.toJson()).toList(),
    };
