// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_condition.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MessageCondition _$MessageConditionFromJson(Map<String, dynamic> json) =>
    MessageCondition(
      json['topicFilter'] as String,
      jsonPath: json['jsonPath'] as String?,
      op: $enumDecodeNullable(_$ConditionOpEnumMap, json['op']),
      value: json['value'] as String?,
    );

Map<String, dynamic> _$MessageConditionToJson(MessageCondition instance) =>
    <String, dynamic>{
      'topicFilter': instance.topicFilter,
      'jsonPath': instance.jsonPath,
      'op': _$ConditionOpEnumMap[instance.op],
      'value': instance.value,
    };

const _$ConditionOpEnumMap = {
  ConditionOp.equals: 'equals',
  ConditionOp.notEquals: 'notEquals',
  ConditionOp.greater: 'greater',
  ConditionOp.greaterOrEqual: 'greaterOrEqual',
  ConditionOp.less: 'less',
  ConditionOp.lessOrEqual: 'lessOrEqual',
  ConditionOp.contains: 'contains',
  ConditionOp.regex: 'regex',
};
