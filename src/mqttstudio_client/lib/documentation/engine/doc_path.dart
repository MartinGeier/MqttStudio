import 'dart:convert';

enum DocPathError { empty, wildcard, invalidParameter, duplicateParameter, tooLong }

// One level of a documented path: a literal, or one parameter with an optional literal prefix and suffix (m{machine})
class DocSegment {
  final String prefix;
  // null for a literal segment
  final String? parameter;
  final String suffix;

  const DocSegment.literal(String text)
      : prefix = text,
        parameter = null,
        suffix = '';

  const DocSegment.parameter(this.prefix, String this.parameter, this.suffix);

  bool get isParameter => parameter != null;

  String get text => isParameter ? '$prefix{$parameter}$suffix' : prefix;

  // the literal part of a parameter segment, to rank templates
  int get literalLength => prefix.length + suffix.length;

  // whether two segments match the same values, whatever the parameters are called
  bool sameShape(DocSegment other) =>
      isParameter == other.isParameter && prefix == other.prefix && suffix == other.suffix;
}

// A topic template, e.g. plant/{line}/m{machine}/temp (doc/documentation-design.md §4.3)
class DocPath {
  static const int maxLength = 65535;
  static final RegExp _parameterName = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$');
  static final RegExp _segmentPattern = RegExp(r'^([^{}]*)\{([^{}]*)\}([^{}]*)$');

  final String path;
  final List<DocSegment> segments;

  DocPath._(this.path, this.segments);

  // null when the path is invalid, see validate
  static DocPath? tryParse(String path) => validate(path) == null ? _parse(path) : null;

  static DocPath parse(String path) {
    var error = validate(path);
    if (error != null) {
      throw FormatException('Invalid documented path ($error)', path);
    }
    return _parse(path);
  }

  static DocPath _parse(String path) => DocPath._(path, [for (var text in path.split('/')) _parseSegment(text)!]);

  static DocSegment? _parseSegment(String text) {
    if (!text.contains('{') && !text.contains('}')) {
      return DocSegment.literal(text);
    }
    var match = _segmentPattern.firstMatch(text);
    if (match == null || !_parameterName.hasMatch(match.group(2)!)) {
      return null;
    }
    return DocSegment.parameter(match.group(1)!, match.group(2)!, match.group(3)!);
  }

  static DocPathError? validate(String path) {
    if (path.isEmpty) {
      return DocPathError.empty;
    }
    if (utf8.encode(path).length > maxLength) {
      return DocPathError.tooLong;
    }
    if (path.contains('+') || path.contains('#')) {
      return DocPathError.wildcard;
    }
    var names = <String>{};
    for (var text in path.split('/')) {
      var segment = _parseSegment(text);
      if (segment == null) {
        return DocPathError.invalidParameter;
      }
      if (segment.isParameter && !names.add(segment.parameter!)) {
        return DocPathError.duplicateParameter;
      }
    }
    return null;
  }

  // the parameter names in path order
  static List<String> parameterNames(String path) =>
      tryParse(path)?.segments.where((segment) => segment.isParameter).map((segment) => segment.parameter!).toList() ??
      [];

  static String parentOf(String path) {
    var index = path.lastIndexOf('/');
    return index < 0 ? '' : path.substring(0, index);
  }

  static String lastSegmentOf(String path) => path.substring(path.lastIndexOf('/') + 1);

  // true for the path itself and every path below it
  static bool isAtOrBelow(String path, String ancestor) => path == ancestor || path.startsWith('$ancestor/');

  int get literalCount => segments.where((segment) => !segment.isParameter).length;

  int get parameterLiteralLength => segments.fold(0, (sum, segment) => sum + segment.literalLength);

  bool get hasParameters => segments.any((segment) => segment.isParameter);

  // a template that matches exactly the same topics, parameter names aside
  bool sameShape(DocPath other) {
    if (segments.length != other.segments.length) {
      return false;
    }
    for (var i = 0; i < segments.length; i++) {
      if (!segments[i].sameShape(other.segments[i])) {
        return false;
      }
    }
    return true;
  }

  // the parameter values when the concrete topic matches, otherwise null. patterns restrict parameters by name.
  Map<String, String>? match(String topic, [Map<String, RegExp> patterns = const {}]) {
    var levels = topic.split('/');
    if (levels.length != segments.length) {
      return null;
    }
    var values = <String, String>{};
    for (var i = 0; i < segments.length; i++) {
      var value = matchSegment(segments[i], levels[i], patterns);
      if (value == null) {
        return null;
      }
      if (segments[i].isParameter) {
        values[segments[i].parameter!] = value;
      }
    }
    return values;
  }

  // the matched value: the level itself for a literal, the parameter value otherwise; null when it doesn't match
  static String? matchSegment(DocSegment segment, String level, [Map<String, RegExp> patterns = const {}]) {
    if (!segment.isParameter) {
      return level == segment.prefix ? level : null;
    }
    if (level.length <= segment.literalLength || !level.startsWith(segment.prefix) || !level.endsWith(segment.suffix)) {
      return null;
    }
    var value = level.substring(segment.prefix.length, level.length - segment.suffix.length);
    var pattern = patterns[segment.parameter];
    if (pattern != null) {
      var match = pattern.matchAsPrefix(value);
      if (match == null || match.end != value.length) {
        return null;
      }
    }
    return value;
  }

  // > 0 when this template is more specific than other: more literal segments, then longer literal parts of
  // parameter segments, then the first literal earlier
  int compareSpecificity(DocPath other) {
    var byLiterals = literalCount.compareTo(other.literalCount);
    if (byLiterals != 0) {
      return byLiterals;
    }
    var byLiteralLength = parameterLiteralLength.compareTo(other.parameterLiteralLength);
    if (byLiteralLength != 0) {
      return byLiteralLength;
    }
    for (var i = 0; i < segments.length && i < other.segments.length; i++) {
      if (segments[i].isParameter != other.segments[i].isParameter) {
        return segments[i].isParameter ? -1 : 1;
      }
    }
    return 0;
  }

  @override
  String toString() => path;
}
