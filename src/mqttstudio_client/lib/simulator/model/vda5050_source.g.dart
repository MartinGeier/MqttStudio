// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vda5050_source.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Vda5050Source _$Vda5050SourceFromJson(Map<String, dynamic> json) =>
    Vda5050Source(
      version:
          $enumDecodeNullable(_$VdaVersionEnumMap, json['version']) ??
          VdaVersion.v3,
      interfaceName:
          json['interfaceName'] as String? ?? Vda5050Source.defaultInterfaceV3,
      manufacturer: json['manufacturer'] as String? ?? 'MQTTStudio',
      serialNumber: json['serialNumber'] as String? ?? 'SIM-{n}',
      mapId: json['mapId'] as String? ?? 'sim-map',
      columns: (json['columns'] as num?)?.toInt() ?? 6,
      rows: (json['rows'] as num?)?.toInt() ?? 4,
      spacing: (json['spacing'] as num?)?.toDouble() ?? 5,
      chargingStations: (json['chargingStations'] as num?)?.toInt() ?? 1,
      speed: (json['speed'] as num?)?.toDouble() ?? 1,
      batteryPerHour: (json['batteryPerHour'] as num?)?.toDouble() ?? 20,
      chargePerHour: (json['chargePerHour'] as num?)?.toDouble() ?? 120,
      stateHeartbeatSec: (json['stateHeartbeatSec'] as num?)?.toInt() ?? 30,
      visualizationMs: (json['visualizationMs'] as num?)?.toInt() ?? 500,
      factsheet: json['factsheet'] as bool? ?? true,
      minOrderNodes: (json['minOrderNodes'] as num?)?.toInt() ?? 4,
      maxOrderNodes: (json['maxOrderNodes'] as num?)?.toInt() ?? 10,
      horizonNodes: (json['horizonNodes'] as num?)?.toInt() ?? 2,
      actionProbability: (json['actionProbability'] as num?)?.toDouble() ?? 0.3,
      minActionSec: (json['minActionSec'] as num?)?.toInt() ?? 2,
      maxActionSec: (json['maxActionSec'] as num?)?.toInt() ?? 8,
      minIdleSec: (json['minIdleSec'] as num?)?.toInt() ?? 0,
      maxIdleSec: (json['maxIdleSec'] as num?)?.toInt() ?? 10,
      zones: json['zones'] as bool? ?? true,
      requests: json['requests'] as bool? ?? true,
      randomFaultsPerHour:
          (json['randomFaultsPerHour'] as num?)?.toDouble() ?? 0,
      seed: (json['seed'] as num?)?.toInt(),
    );

Map<String, dynamic> _$Vda5050SourceToJson(Vda5050Source instance) =>
    <String, dynamic>{
      'version': _$VdaVersionEnumMap[instance.version]!,
      'interfaceName': instance.interfaceName,
      'manufacturer': instance.manufacturer,
      'serialNumber': instance.serialNumber,
      'mapId': instance.mapId,
      'columns': instance.columns,
      'rows': instance.rows,
      'spacing': instance.spacing,
      'chargingStations': instance.chargingStations,
      'speed': instance.speed,
      'batteryPerHour': instance.batteryPerHour,
      'chargePerHour': instance.chargePerHour,
      'stateHeartbeatSec': instance.stateHeartbeatSec,
      'visualizationMs': instance.visualizationMs,
      'factsheet': instance.factsheet,
      'minOrderNodes': instance.minOrderNodes,
      'maxOrderNodes': instance.maxOrderNodes,
      'horizonNodes': instance.horizonNodes,
      'actionProbability': instance.actionProbability,
      'minActionSec': instance.minActionSec,
      'maxActionSec': instance.maxActionSec,
      'minIdleSec': instance.minIdleSec,
      'maxIdleSec': instance.maxIdleSec,
      'zones': instance.zones,
      'requests': instance.requests,
      'randomFaultsPerHour': instance.randomFaultsPerHour,
      'seed': instance.seed,
    };

const _$VdaVersionEnumMap = {VdaVersion.v2: 'v2', VdaVersion.v3: 'v3'};
