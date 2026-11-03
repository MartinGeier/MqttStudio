// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sparkplug_source.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SparkplugMetricSpec _$SparkplugMetricSpecFromJson(Map<String, dynamic> json) =>
    SparkplugMetricSpec(
      name: json['name'] as String,
      type: $enumDecode(_$SpbDataTypeEnumMap, json['type']),
      generator: PayloadGenerator.fromJson(
        json['generator'] as Map<String, dynamic>,
      ),
      unit: json['unit'] as String?,
      deadband: (json['deadband'] as num?)?.toDouble() ?? 0,
      writable: json['writable'] as bool? ?? false,
    );

Map<String, dynamic> _$SparkplugMetricSpecToJson(
  SparkplugMetricSpec instance,
) => <String, dynamic>{
  'name': instance.name,
  'type': _$SpbDataTypeEnumMap[instance.type]!,
  'generator': PayloadGenerator.toJsonStatic(instance.generator),
  'unit': instance.unit,
  'deadband': instance.deadband,
  'writable': instance.writable,
};

const _$SpbDataTypeEnumMap = {
  SpbDataType.unknown: 'unknown',
  SpbDataType.int8: 'int8',
  SpbDataType.int16: 'int16',
  SpbDataType.int32: 'int32',
  SpbDataType.int64: 'int64',
  SpbDataType.uInt8: 'uInt8',
  SpbDataType.uInt16: 'uInt16',
  SpbDataType.uInt32: 'uInt32',
  SpbDataType.uInt64: 'uInt64',
  SpbDataType.float: 'float',
  SpbDataType.double: 'double',
  SpbDataType.boolean: 'boolean',
  SpbDataType.string: 'string',
  SpbDataType.dateTime: 'dateTime',
  SpbDataType.text: 'text',
  SpbDataType.uuid: 'uuid',
  SpbDataType.dataSet: 'dataSet',
  SpbDataType.bytes: 'bytes',
  SpbDataType.file: 'file',
  SpbDataType.template: 'template',
  SpbDataType.propertySet: 'propertySet',
  SpbDataType.propertySetList: 'propertySetList',
  SpbDataType.int8Array: 'int8Array',
  SpbDataType.int16Array: 'int16Array',
  SpbDataType.int32Array: 'int32Array',
  SpbDataType.int64Array: 'int64Array',
  SpbDataType.uInt8Array: 'uInt8Array',
  SpbDataType.uInt16Array: 'uInt16Array',
  SpbDataType.uInt32Array: 'uInt32Array',
  SpbDataType.uInt64Array: 'uInt64Array',
  SpbDataType.floatArray: 'floatArray',
  SpbDataType.doubleArray: 'doubleArray',
  SpbDataType.booleanArray: 'booleanArray',
  SpbDataType.stringArray: 'stringArray',
  SpbDataType.dateTimeArray: 'dateTimeArray',
};

SparkplugDeviceSpec _$SparkplugDeviceSpecFromJson(Map<String, dynamic> json) =>
    SparkplugDeviceSpec(
      id: json['id'] as String? ?? 'Device{d}',
      count: (json['count'] as num?)?.toInt() ?? 1,
      metrics: (json['metrics'] as List<dynamic>?)
          ?.map((e) => SparkplugMetricSpec.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$SparkplugDeviceSpecToJson(
  SparkplugDeviceSpec instance,
) => <String, dynamic>{
  'id': instance.id,
  'count': instance.count,
  'metrics': instance.metrics.map((e) => e.toJson()).toList(),
};

SparkplugSource _$SparkplugSourceFromJson(Map<String, dynamic> json) =>
    SparkplugSource(
      groupId: json['groupId'] as String? ?? 'Plant1',
      edgeNodeId: json['edgeNodeId'] as String? ?? 'Edge{n}',
      nodeMetrics: (json['nodeMetrics'] as List<dynamic>?)
          ?.map((e) => SparkplugMetricSpec.fromJson(e as Map<String, dynamic>))
          .toList(),
      devices: (json['devices'] as List<dynamic>?)
          ?.map((e) => SparkplugDeviceSpec.fromJson(e as Map<String, dynamic>))
          .toList(),
      scanMs: (json['scanMs'] as num?)?.toInt() ?? 1000,
      aliases: json['aliases'] as bool? ?? true,
      primaryHostId: json['primaryHostId'] as String?,
      simulateHost: json['simulateHost'] as bool? ?? true,
      compress: json['compress'] as bool? ?? false,
      seed: (json['seed'] as num?)?.toInt(),
    );

Map<String, dynamic> _$SparkplugSourceToJson(SparkplugSource instance) =>
    <String, dynamic>{
      'groupId': instance.groupId,
      'edgeNodeId': instance.edgeNodeId,
      'nodeMetrics': instance.nodeMetrics.map((e) => e.toJson()).toList(),
      'devices': instance.devices.map((e) => e.toJson()).toList(),
      'scanMs': instance.scanMs,
      'aliases': instance.aliases,
      'primaryHostId': instance.primaryHostId,
      'simulateHost': instance.simulateHost,
      'compress': instance.compress,
      'seed': instance.seed,
    };
