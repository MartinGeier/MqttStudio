import 'package:event/event.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/documentation/engine/doc_path.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/project/project_manager.dart';

enum DocPathConflict { exists, sameShape }

// Domain service of the documentation tab: edits the documentation of the current project
// (doc/documentation-design.md §6). Every change marks the project as changed through its hash.
class DocumentationService {
  final _projectManager = GetIt.I.get<ProjectManager>();

  // nodes were added, changed, moved or deleted
  final documentationChangedEvent = Event();

  TopicDocumentation? get documentation => _projectManager.currentProject?.documentation;

  List<DocNode> get nodes => documentation?.nodes ?? [];

  DocNode? nodeAt(String path) => documentation?.nodeAt(path);

  List<DocNode> nodesAtOrBelow(String path) =>
      path.isEmpty ? List.of(nodes) : nodes.where((node) => DocPath.isAtOrBelow(node.path, path)).toList();

  // a node with the same path, or one that matches exactly the same topics. ignore leaves out the nodes being moved.
  DocPathConflict? conflictOf(String path, {Set<String> ignore = const {}}) {
    var parsed = DocPath.tryParse(path);
    for (var node in nodes) {
      if (ignore.contains(node.path)) {
        continue;
      }
      if (node.path == path) {
        return DocPathConflict.exists;
      }
      var other = DocPath.tryParse(node.path);
      if (parsed != null && other != null && parsed.sameShape(other)) {
        return DocPathConflict.sameShape;
      }
    }
    return null;
  }

  void notifyChanged() => documentationChangedEvent.broadcast();

  void addNode(DocNode node) {
    syncParameters(node);
    documentation!.nodes.add(node);
    documentation!.sortNodes();
    notifyChanged();
  }

  // the node of a path that only exists implicitly in the tree, created when its text is edited
  DocNode ensureNode(String path) {
    var node = nodeAt(path);
    if (node != null) {
      return node;
    }
    node = DocNode(path: path);
    addNode(node);
    return node;
  }

  // moves the node at from and every node below it. Returns the moved nodes' new paths, or throws ArgumentError
  // when a new path is invalid or taken.
  List<String> movePath(String from, String to) {
    var moved = nodesAtOrBelow(from);
    var movedPaths = moved.map((node) => node.path).toSet();
    var targets = <DocNode, String>{for (var node in moved) node: to + node.path.substring(from.length)};
    for (var target in targets.values) {
      if (DocPath.validate(target) != null || conflictOf(target, ignore: movedPaths) != null) {
        throw ArgumentError.value(target, 'to');
      }
    }
    for (var entry in targets.entries) {
      var oldPath = entry.key.path;
      entry.key.path = entry.value;
      syncParameters(entry.key, oldPath: oldPath);
    }
    for (var node in nodes) {
      var replacedBy = node.replacedBy;
      if (replacedBy != null && DocPath.isAtOrBelow(replacedBy, from)) {
        node.replacedBy = to + replacedBy.substring(from.length);
      }
    }
    documentation!.sortNodes();
    notifyChanged();
    return targets.values.toList();
  }

  // deletes the node at path and every node below it
  int deletePath(String path) {
    var doomed = nodesAtOrBelow(path).toSet();
    documentation!.nodes.removeWhere(doomed.contains);
    notifyChanged();
    return doomed.length;
  }

  DocNode duplicate(DocNode node) {
    var copy = node.copy()..path = uniquePath('${node.path}_copy');
    addNode(copy);
    return copy;
  }

  String uniquePath(String path) {
    var candidate = path;
    for (var i = 2; conflictOf(candidate) != null; i++) {
      candidate = '$path$i';
    }
    return candidate;
  }

  // a namespace node becomes a topic node and back
  void setTopic(DocNode node, bool isTopic) {
    if (node.isTopic == isTopic) {
      return;
    }
    node.topic = isTopic ? TopicSpec() : null;
    notifyChanged();
  }

  // keeps one DocParameter per parameter of the path. After a move the parameters are carried over by position
  // when their number stays the same, so renaming a parameter keeps its description.
  static void syncParameters(DocNode node, {String? oldPath}) {
    var names = DocPath.parameterNames(node.path);
    var oldNames = oldPath == null ? null : DocPath.parameterNames(oldPath);
    var byName = {for (var parameter in node.parameters) parameter.name: parameter};
    var byPosition =
        oldNames != null && oldNames.length == names.length ? [for (var name in oldNames) byName[name]] : null;
    node.parameters = [
      for (var i = 0; i < names.length; i++)
        (byPosition?[i] ?? byName[names[i]] ?? DocParameter(name: names[i]))..name = names[i]
    ];
  }
}
