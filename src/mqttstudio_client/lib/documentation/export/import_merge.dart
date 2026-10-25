import 'dart:convert';
import 'package:mqttstudio/documentation/engine/doc_path.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';

enum ImportState { added, changed, same, conflict }

class ImportItem {
  final DocNode imported;
  // the documented node with the same path, or the one that matches the same topics (conflict)
  final DocNode? existing;
  final ImportState state;
  bool accept;

  ImportItem(this.imported, this.existing, this.state)
      : accept = state == ImportState.added || state == ImportState.changed;
}

// What an import would change (doc/documentation-design.md §9.3): new topics, documented ones whose texts differ,
// unchanged ones and ones whose template another documented topic already covers
class ImportPlan {
  final TopicDocumentation imported;
  final List<ImportItem> items;

  ImportPlan(this.imported, this.items);

  int countOf(ImportState state) => items.where((item) => item.state == state).length;

  static ImportPlan of(TopicDocumentation current, TopicDocumentation imported) {
    var items = <ImportItem>[];
    for (var node in imported.nodes) {
      var existing = current.nodeAt(node.path);
      if (existing != null) {
        items.add(ImportItem(
            node, existing, _documented(existing) == _documented(node) ? ImportState.same : ImportState.changed));
        continue;
      }
      var parsed = DocPath.tryParse(node.path);
      var sameShape = current.nodes.where((other) {
        var path = DocPath.tryParse(other.path);
        return parsed != null && path != null && path.sameShape(parsed);
      }).firstOrNull;
      items.add(ImportItem(node, sameShape, sameShape == null ? ImportState.added : ImportState.conflict));
    }
    return ImportPlan(imported, items);
  }

  // the documented texts and values, without what discovery observed and the review marks
  static String _documented(DocNode node) {
    var json = node.toJson()
      ..remove('observed')
      ..remove('review')
      ..remove('editedFields');
    return jsonEncode(json);
  }

  // merge: accepted new topics are added, accepted changed ones take the imported texts and keep what discovery
  // observed. replaceAll: the imported documentation replaces everything; observed values of topics with the same
  // path stay.
  void applyTo(TopicDocumentation current, {bool replaceAll = false}) {
    if (replaceAll) {
      var observed = {for (var node in current.nodes) node.path: node.observed};
      current
        ..title = imported.title
        ..description = imported.description
        ..owner = imported.owner
        ..nodes = [for (var node in imported.nodes) node.copy()..observed ??= observed[node.path]];
    } else {
      if (current.title.isEmpty) {
        current.title = imported.title;
      }
      if (current.description.isEmpty) {
        current.description = imported.description;
      }
      if (current.owner.isEmpty) {
        current.owner = imported.owner;
      }
      for (var item in items.where((item) => item.accept)) {
        switch (item.state) {
          case ImportState.added:
            current.nodes.add(item.imported.copy());
          case ImportState.changed:
            var existing = item.existing!;
            var replacement = item.imported.copy()
              ..observed = existing.observed
              ..editedFields = {...existing.editedFields, ...item.imported.editedFields};
            current.nodes[current.nodes.indexOf(existing)] = replacement;
          case ImportState.same || ImportState.conflict:
            break;
        }
      }
    }
    current
      ..revision += 1
      ..sortNodes();
  }
}
