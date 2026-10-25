import 'package:mqttstudio/documentation/engine/doc_path.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';

class DocMatch {
  final DocNode node;
  final Map<String, String> parameters;

  DocMatch(this.node, this.parameters);
}

class _TrieLevel {
  final Map<String, _TrieLevel> literals = {};
  final List<(DocSegment, _TrieLevel)> parameters = [];
  final List<(DocPath, DocNode, Map<String, RegExp>)> ends = [];

  _TrieLevel childFor(DocSegment segment) {
    if (!segment.isParameter) {
      return literals.putIfAbsent(segment.prefix, _TrieLevel.new);
    }
    for (var (existing, level) in parameters) {
      if (existing.sameShape(segment)) {
        return level;
      }
    }
    var level = _TrieLevel();
    parameters.add((segment, level));
    return level;
  }
}

// Finds the documented topic of a concrete topic: the matching template with the most literal segments (§4.3).
// Built once per documentation state, so a match costs one walk down the levels of the topic.
class DocIndex {
  final _root = _TrieLevel();

  // without patterns, a parameter matches any value; the check uses it to tell a broken pattern from an undocumented
  // topic
  DocIndex(Iterable<DocNode> nodes, {bool patterns = true}) {
    for (var node in nodes.where((node) => node.isTopic)) {
      var path = DocPath.tryParse(node.path);
      if (path == null) {
        continue;
      }
      var level = _root;
      for (var segment in path.segments) {
        level = level.childFor(segment);
      }
      level.ends.add((path, node, patterns ? _patternsOf(node) : const <String, RegExp>{}));
    }
  }

  static Map<String, RegExp> _patternsOf(DocNode node) {
    var patterns = <String, RegExp>{};
    for (var parameter in node.parameters) {
      var pattern = parameter.pattern;
      if (pattern == null || pattern.isEmpty) {
        continue;
      }
      try {
        patterns[parameter.name] = RegExp(pattern);
      } on FormatException {
        // an invalid pattern restricts nothing; the editor shows it as an error
      }
    }
    return patterns;
  }

  DocMatch? match(String topic) {
    DocMatch? best;
    DocPath? bestPath;
    void visit(_TrieLevel level, List<String> levels, int index) {
      if (index == levels.length) {
        for (var (path, node, patterns) in level.ends) {
          if (bestPath != null && path.compareSpecificity(bestPath!) <= 0) {
            continue;
          }
          var parameters = path.match(levels.join('/'), patterns);
          if (parameters != null) {
            best = DocMatch(node, parameters);
            bestPath = path;
          }
        }
        return;
      }
      var literal = level.literals[levels[index]];
      if (literal != null) {
        visit(literal, levels, index + 1);
      }
      for (var (segment, child) in level.parameters) {
        if (DocPath.matchSegment(segment, levels[index]) != null) {
          visit(child, levels, index + 1);
        }
      }
    }

    visit(_root, topic.split('/'), 0);
    return best;
  }
}
