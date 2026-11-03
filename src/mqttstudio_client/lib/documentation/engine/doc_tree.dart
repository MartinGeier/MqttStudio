import 'package:mqttstudio/documentation/model/topic_documentation.dart';

// One level of the documentation tree. Levels without a node of their own are namespaces that exist only because
// nodes below them do.
class DocTreeEntry {
  // null for the root, which stands for the documentation as a whole
  final String? path;
  final String segment;
  DocNode? node;
  final List<DocTreeEntry> children = [];
  int topicCount = 0;
  int undocumentedCount = 0;

  DocTreeEntry(this.path, this.segment);

  bool get isRoot => path == null;

  bool get isTopic => node?.isTopic ?? false;

  String childPath(String segment) => path == null ? segment : '$path/$segment';

  Iterable<DocTreeEntry> get descendants sync* {
    for (var child in children) {
      yield child;
      yield* child.descendants;
    }
  }

  static DocTreeEntry build(Iterable<DocNode> nodes) {
    var root = DocTreeEntry(null, '');
    var byPath = <String, DocTreeEntry>{};
    for (var node in nodes) {
      var entry = root;
      for (var segment in node.path.split('/')) {
        var path = entry.childPath(segment);
        entry = byPath.putIfAbsent(path, () {
          var child = DocTreeEntry(path, segment);
          entry.children.add(child);
          return child;
        });
      }
      entry.node = node;
    }
    root._finish();
    return root;
  }

  void _finish() {
    children.sort((a, b) => a.segment.toLowerCase().compareTo(b.segment.toLowerCase()));
    topicCount = isTopic ? 1 : 0;
    undocumentedCount = isTopic && node!.isUndocumented ? 1 : 0;
    for (var child in children) {
      child._finish();
      topicCount += child.topicCount;
      undocumentedCount += child.undocumentedCount;
    }
  }
}

class DocTreeRow {
  final DocTreeEntry entry;
  final int depth;

  DocTreeRow(this.entry, this.depth);
}

// The visible rows of the tree: the root, then the expanded levels. With a filter, the levels that match and their
// ancestors, all expanded.
List<DocTreeRow> visibleDocRows(DocTreeEntry root,
    {required bool Function(String path) isExpanded, bool Function(DocTreeEntry entry)? matches}) {
  var rows = <DocTreeRow>[DocTreeRow(root, 0)];
  bool visible(DocTreeEntry entry) => matches == null || matches(entry) || entry.descendants.any(matches);
  void add(DocTreeEntry entry, int depth) {
    for (var child in entry.children) {
      if (!visible(child)) {
        continue;
      }
      rows.add(DocTreeRow(child, depth));
      if (matches != null || isExpanded(child.path!)) {
        add(child, depth + 1);
      }
    }
  }

  add(root, 0);
  return rows;
}
