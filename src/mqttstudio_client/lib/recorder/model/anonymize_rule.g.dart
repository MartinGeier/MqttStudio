// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'anonymize_rule.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AnonymizeRule _$AnonymizeRuleFromJson(Map<String, dynamic> json) =>
    AnonymizeRule(
      json['topicFilter'] as String,
      $enumDecode(_$AnonymizeTargetEnumMap, json['target']),
      $enumDecode(_$AnonymizeActionEnumMap, json['action']),
      jsonPath: json['jsonPath'] as String?,
      level: (json['level'] as num?)?.toInt(),
      value: json['value'] as String?,
      percent: (json['percent'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$AnonymizeRuleToJson(AnonymizeRule instance) =>
    <String, dynamic>{
      'topicFilter': instance.topicFilter,
      'target': _$AnonymizeTargetEnumMap[instance.target]!,
      'jsonPath': instance.jsonPath,
      'level': instance.level,
      'action': _$AnonymizeActionEnumMap[instance.action]!,
      'value': instance.value,
      'percent': instance.percent,
    };

const _$AnonymizeTargetEnumMap = {
  AnonymizeTarget.jsonPath: 'jsonPath',
  AnonymizeTarget.wholePayload: 'wholePayload',
  AnonymizeTarget.topicLevel: 'topicLevel',
};

const _$AnonymizeActionEnumMap = {
  AnonymizeAction.hash: 'hash',
  AnonymizeAction.mask: 'mask',
  AnonymizeAction.fixed: 'fixed',
  AnonymizeAction.remove: 'remove',
  AnonymizeAction.jitterNumber: 'jitterNumber',
};
