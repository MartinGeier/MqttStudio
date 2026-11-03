// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'topic_documentation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TopicDocumentation _$TopicDocumentationFromJson(Map<String, dynamic> json) => TopicDocumentation(
      formatVersion: (json['formatVersion'] as num?)?.toInt() ?? TopicDocumentation.currentFormatVersion,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      owner: json['owner'] as String? ?? '',
      nodes: (json['nodes'] as List<dynamic>?)?.map((e) => DocNode.fromJson(e as Map<String, dynamic>)).toList(),
      discoverySettings: json['discoverySettings'] == null
          ? null
          : DiscoverySettings.fromJson(
              json['discoverySettings'] as Map<String, dynamic>,
            ),
      ignoreFilters: (json['ignoreFilters'] as List<dynamic>?)?.map((e) => e as String).toList(),
      lastDiscoveryAt: json['lastDiscoveryAt'] == null ? null : DateTime.parse(json['lastDiscoveryAt'] as String),
    );

Map<String, dynamic> _$TopicDocumentationToJson(TopicDocumentation instance) => <String, dynamic>{
      'formatVersion': instance.formatVersion,
      'revision': instance.revision,
      'title': instance.title,
      'description': instance.description,
      'owner': instance.owner,
      'nodes': instance.nodes.map((e) => e.toJson()).toList(),
      'discoverySettings': instance.discoverySettings.toJson(),
      'ignoreFilters': instance.ignoreFilters,
      'lastDiscoveryAt': instance.lastDiscoveryAt?.toIso8601String(),
    };

DocNode _$DocNodeFromJson(Map<String, dynamic> json) => DocNode(
      path: json['path'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: $enumDecodeNullable(_$DocStatusEnumMap, json['status']) ?? DocStatus.draft,
      replacedBy: json['replacedBy'] as String?,
      owner: json['owner'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
      links: (json['links'] as List<dynamic>?)?.map((e) => DocLink.fromJson(e as Map<String, dynamic>)).toList(),
      parameters:
          (json['parameters'] as List<dynamic>?)?.map((e) => DocParameter.fromJson(e as Map<String, dynamic>)).toList(),
      topic: json['topic'] == null ? null : TopicSpec.fromJson(json['topic'] as Map<String, dynamic>),
      observed: json['observed'] == null ? null : ObservedTopic.fromJson(json['observed'] as Map<String, dynamic>),
      review: $enumDecodeNullable(_$DocReviewStateEnumMap, json['review']) ?? DocReviewState.none,
      editedFields: (json['editedFields'] as List<dynamic>?)?.map((e) => e as String).toSet(),
    );

Map<String, dynamic> _$DocNodeToJson(DocNode instance) => <String, dynamic>{
      'path': instance.path,
      'title': instance.title,
      'description': instance.description,
      'status': _$DocStatusEnumMap[instance.status]!,
      'replacedBy': instance.replacedBy,
      'owner': instance.owner,
      'tags': instance.tags,
      'links': instance.links.map((e) => e.toJson()).toList(),
      'parameters': instance.parameters.map((e) => e.toJson()).toList(),
      'topic': instance.topic?.toJson(),
      'observed': instance.observed?.toJson(),
      'review': _$DocReviewStateEnumMap[instance.review]!,
      'editedFields': instance.editedFields.toList(),
    };

const _$DocStatusEnumMap = {
  DocStatus.draft: 'draft',
  DocStatus.stable: 'stable',
  DocStatus.deprecated: 'deprecated',
};

const _$DocReviewStateEnumMap = {
  DocReviewState.none: 'none',
  DocReviewState.added: 'added',
  DocReviewState.changed: 'changed',
  DocReviewState.notSeen: 'notSeen',
};

DocLink _$DocLinkFromJson(Map<String, dynamic> json) => DocLink(
      label: json['label'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );

Map<String, dynamic> _$DocLinkToJson(DocLink instance) => <String, dynamic>{
      'label': instance.label,
      'url': instance.url,
    };

DocParameter _$DocParameterFromJson(Map<String, dynamic> json) => DocParameter(
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      pattern: json['pattern'] as String?,
      examples: (json['examples'] as List<dynamic>?)?.map((e) => e as String).toList(),
    );

Map<String, dynamic> _$DocParameterToJson(DocParameter instance) => <String, dynamic>{
      'name': instance.name,
      'description': instance.description,
      'pattern': instance.pattern,
      'examples': instance.examples,
    };
