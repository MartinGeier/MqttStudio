import 'package:json_annotation/json_annotation.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';

// use 'dart run build_runner build' to run the code generator
part 'topic_documentation.g.dart';

enum DocStatus { draft, stable, deprecated }

// marks of the last discovery in the tree, until the user opens the node (§4.4)
enum DocReviewState { none, added, changed, notSeen }

// The documentation of the project's broker namespace (doc/documentation-design.md §4)
@JsonSerializable(explicitToJson: true)
class TopicDocumentation {
  static const int currentFormatVersion = 1;

  int formatVersion;
  // +1 on every applied discovery and import
  int revision;
  String title;
  // Markdown
  String description;
  String owner;
  // sorted by path
  List<DocNode> nodes;
  DiscoverySettings discoverySettings;
  // topic filters discovery leaves out, e.g. after a rejected topic in the review
  List<String> ignoreFilters;
  DateTime? lastDiscoveryAt;

  TopicDocumentation(
      {this.formatVersion = TopicDocumentation.currentFormatVersion,
      this.revision = 0,
      this.title = '',
      this.description = '',
      this.owner = '',
      List<DocNode>? nodes,
      DiscoverySettings? discoverySettings,
      List<String>? ignoreFilters,
      this.lastDiscoveryAt})
      : nodes = nodes ?? [],
        discoverySettings = discoverySettings ?? DiscoverySettings(),
        ignoreFilters = ignoreFilters ?? [];

  // projects saved before the documentation existed have none
  static TopicDocumentation fromJsonOrEmpty(Map<String, dynamic>? json) =>
      json == null ? TopicDocumentation() : TopicDocumentation.fromJson(json);

  DocNode? nodeAt(String path) {
    for (var node in nodes) {
      if (node.path == path) {
        return node;
      }
    }
    return null;
  }

  Iterable<DocNode> get topics => nodes.where((node) => node.isTopic);

  void sortNodes() => nodes.sort((a, b) => a.path.compareTo(b.path));

  factory TopicDocumentation.fromJson(Map<String, dynamic> json) => _$TopicDocumentationFromJson(json);
  Map<String, dynamic> toJson() => _$TopicDocumentationToJson(this);
}

// A namespace node (topic == null) or a topic node. Its path is a template, see DocPath.
@JsonSerializable(explicitToJson: true)
class DocNode {
  String path;
  String title;
  // Markdown
  String description;
  DocStatus status;
  // the path of the node that replaces a deprecated one
  String? replacedBy;
  String owner;
  List<String> tags;
  List<DocLink> links;
  // one per parameter of the path, in path order
  List<DocParameter> parameters;
  TopicSpec? topic;
  ObservedTopic? observed;
  DocReviewState review;
  // keys of the fields the user changed; discovery never overwrites them (T5)
  Set<String> editedFields;

  DocNode(
      {required this.path,
      this.title = '',
      this.description = '',
      this.status = DocStatus.draft,
      this.replacedBy,
      this.owner = '',
      List<String>? tags,
      List<DocLink>? links,
      List<DocParameter>? parameters,
      this.topic,
      this.observed,
      this.review = DocReviewState.none,
      Set<String>? editedFields})
      : tags = tags ?? [],
        links = links ?? [],
        parameters = parameters ?? [],
        editedFields = editedFields ?? {};

  bool get isTopic => topic != null;

  bool get isUndocumented => description.trim().isEmpty;

  DocNode copy() => DocNode.fromJson(toJson());

  factory DocNode.fromJson(Map<String, dynamic> json) => _$DocNodeFromJson(json);
  Map<String, dynamic> toJson() => _$DocNodeToJson(this);
}

@JsonSerializable()
class DocLink {
  String label;
  String url;

  DocLink({this.label = '', this.url = ''});

  factory DocLink.fromJson(Map<String, dynamic> json) => _$DocLinkFromJson(json);
  Map<String, dynamic> toJson() => _$DocLinkToJson(this);
}

@JsonSerializable()
class DocParameter {
  String name;
  String description;
  // a regular expression the value must match completely
  String? pattern;
  List<String> examples;

  DocParameter({required this.name, this.description = '', this.pattern, List<String>? examples})
      : examples = examples ?? [];

  factory DocParameter.fromJson(Map<String, dynamic> json) => _$DocParameterFromJson(json);
  Map<String, dynamic> toJson() => _$DocParameterToJson(this);
}
