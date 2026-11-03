import 'dart:math';

// A documented topic discovery proposes: a template with parameters, or a single topic
class DetectedTopic {
  final String path;
  // the concrete topics it covers
  final Set<String> topics;
  // parameter name and its pattern, for the parameters that have one
  final Map<String, String> patterns;

  DetectedTopic(this.path, this.topics, this.patterns);

  bool get isTemplate => path.contains('{');
}

class _Parameter {
  final String prefix;
  final String suffix;
  final String? pattern;
  final String name;
  final _Level level;

  _Parameter(this.prefix, this.suffix, this.pattern, this.name, this.level);

  bool sameShape(_Parameter other) => prefix == other.prefix && suffix == other.suffix;
}

class _Level {
  final Map<String, _Level> literals = {};
  final List<_Parameter> parameters = [];
  final Set<String> topics = {};
}

// Proposes parameters for topic levels whose siblings look alike (doc/documentation-design.md §5.5): at least three
// siblings (or two numbered ones like area1, area2) with the same or similar topics below them become one parameter
// level, e.g. plant/line1/m12/temp, plant/line1/m51/temp, plant/line1/m07/temp → plant/line1/m{id}/temp. Levels are
// collapsed bottom-up, so several levels can become parameters.
class TemplateDetector {
  static const int minGroup = 3;
  static const double minSimilarity = 0.8;
  static const String _marker = '\u0001';
  static final RegExp _digits = RegExp(r'^\d+$');
  static final RegExp _hex = RegExp(r'^[0-9a-fA-F]+$');
  static final RegExp _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static final RegExp _letters = RegExp(r'^[A-Za-z]{2,}$');
  static const String _uuidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';

  // topics with { or } can't be documented as literals and are left out
  static List<DetectedTopic> detect(Iterable<String> topics) {
    var root = _Level();
    for (var topic in topics.where((topic) => !topic.contains('{') && !topic.contains('}'))) {
      var level = root;
      for (var segment in topic.split('/')) {
        level = level.literals.putIfAbsent(segment, _Level.new);
      }
      level.topics.add(topic);
    }
    _collapse(root, '');
    var result = <DetectedTopic>[];
    _extract(root, [], {}, {}, result);
    result.sort((a, b) => a.path.compareTo(b.path));
    return result;
  }

  static void _collapse(_Level level, String segment) {
    for (var entry in level.literals.entries) {
      _collapse(entry.value, entry.key);
    }
    for (var parameter in level.parameters) {
      _collapse(parameter.level, parameter.name);
    }
    if (level.literals.length < 2) {
      return;
    }
    var shapes = {for (var entry in level.literals.entries) entry.key: _shape(entry.value)};
    var groups = <List<String>>[];
    for (var name in level.literals.keys) {
      var group =
          groups.where((group) => _similarity(shapes[group.first]!, shapes[name]!) >= minSimilarity).firstOrNull;
      if (group == null) {
        groups.add([name]);
      } else {
        group.add(name);
      }
    }
    groups.sort((a, b) => b.length.compareTo(a.length));
    var siblings = level.literals.length;
    for (var group in groups.where((group) => group.length >= 2)) {
      var naming = _naming(group);
      var identical = group.every((name) => _similarity(shapes[group.first]!, shapes[name]!) == 1);
      var numbered = naming.pattern != null && (naming.prefix.isNotEmpty || naming.suffix.isNotEmpty) && identical;
      if (!numbered && (group.length < minGroup || group.length * 2 < siblings)) {
        continue;
      }
      // sibling topics with names like temp, speed and state are different topics, not instances
      var leaves = shapes[group.first]!.length == 1 && shapes[group.first]!.single.isEmpty;
      if (leaves && naming.pattern == null) {
        continue;
      }
      var parameter =
          _Parameter(naming.prefix, naming.suffix, naming.pattern, _nameFor(naming.prefix, segment), _Level());
      if (level.parameters.any((existing) => existing.sameShape(parameter))) {
        continue;
      }
      for (var name in group) {
        _mergeInto(parameter.level, level.literals.remove(name)!);
      }
      _collapse(parameter.level, parameter.name);
      level.parameters.add(parameter);
    }
  }

  static void _mergeInto(_Level target, _Level source) {
    target.topics.addAll(source.topics);
    for (var entry in source.literals.entries) {
      _mergeInto(target.literals.putIfAbsent(entry.key, _Level.new), entry.value);
    }
    for (var parameter in source.parameters) {
      var existing = target.parameters.where((candidate) => candidate.sameShape(parameter)).firstOrNull;
      if (existing == null) {
        target.parameters
            .add(_Parameter(parameter.prefix, parameter.suffix, parameter.pattern, parameter.name, _Level()));
        existing = target.parameters.last;
      }
      _mergeInto(existing.level, parameter.level);
    }
  }

  // the topic suffixes below a level, with parameters reduced to their literal parts
  static Set<String> _shape(_Level level) {
    var shape = <String>{};
    if (level.topics.isNotEmpty) {
      shape.add('');
    }
    for (var entry in level.literals.entries) {
      for (var suffix in _shape(entry.value)) {
        shape.add('/${entry.key}$suffix');
      }
    }
    for (var parameter in level.parameters) {
      for (var suffix in _shape(parameter.level)) {
        shape.add('/${parameter.prefix}$_marker${parameter.suffix}$suffix');
      }
    }
    return shape;
  }

  static double _similarity(Set<String> a, Set<String> b) {
    var union = a.union(b).length;
    return union == 0 ? 1 : a.intersection(b).length / union;
  }

  // the literal prefix and suffix the names share, and the pattern of the rest; no pattern means the whole segment
  static ({String prefix, String suffix, String? pattern}) _naming(List<String> names) {
    for (var (kind, pattern) in [(_digits, r'\d+'), (_hex, '[0-9a-fA-F]+')]) {
      var prefix = _commonPrefix(names);
      var suffix = _commonSuffix(names.map((name) => name.substring(prefix.length)).toList());
      while (prefix.isNotEmpty && kind.hasMatch(prefix[prefix.length - 1])) {
        prefix = prefix.substring(0, prefix.length - 1);
      }
      while (suffix.isNotEmpty && kind.hasMatch(suffix[0])) {
        suffix = suffix.substring(1);
      }
      var rests = names.map((name) => name.substring(prefix.length, name.length - suffix.length));
      if (rests.every((rest) => rest.isNotEmpty && kind.hasMatch(rest)) &&
          (kind == _digits || rests.every((rest) => rest.contains(RegExp(r'\d'))))) {
        return (prefix: prefix, suffix: suffix, pattern: pattern);
      }
    }
    if (names.every(_uuid.hasMatch)) {
      return (prefix: '', suffix: '', pattern: _uuidPattern);
    }
    return (prefix: '', suffix: '', pattern: null);
  }

  static String _commonPrefix(List<String> names) {
    var prefix = names.first;
    for (var name in names.skip(1)) {
      var length = 0;
      while (length < min(prefix.length, name.length) && prefix[length] == name[length]) {
        length++;
      }
      prefix = prefix.substring(0, length);
    }
    return prefix;
  }

  static String _commonSuffix(List<String> names) {
    var reversed = _commonPrefix([for (var name in names) name.split('').reversed.join()]);
    return reversed.split('').reversed.join();
  }

  // area1, area2 → area; under machines → machine; otherwise id. The user renames it in the review.
  static String _nameFor(String prefix, String parentSegment) {
    var letters = prefix.replaceAll(RegExp(r'[-_.]+$'), '');
    if (_letters.hasMatch(letters)) {
      return letters.toLowerCase();
    }
    if (_letters.hasMatch(parentSegment) && parentSegment.length > 3 && parentSegment.endsWith('s')) {
      return parentSegment.substring(0, parentSegment.length - 1).toLowerCase();
    }
    return 'id';
  }

  static void _extract(_Level level, List<String> segments, Map<String, String> patterns, Set<String> names,
      List<DetectedTopic> result) {
    if (level.topics.isNotEmpty && segments.isNotEmpty) {
      result.add(DetectedTopic(segments.join('/'), Set.of(level.topics), Map.of(patterns)));
    }
    for (var entry in level.literals.entries) {
      _extract(entry.value, [...segments, entry.key], patterns, names, result);
    }
    for (var parameter in level.parameters) {
      var name = parameter.name;
      for (var i = 2; names.contains(name); i++) {
        name = '${parameter.name}$i';
      }
      _extract(parameter.level, [...segments, '${parameter.prefix}{$name}${parameter.suffix}'],
          {...patterns, if (parameter.pattern != null) name: parameter.pattern!}, {...names, name}, result);
    }
  }
}
