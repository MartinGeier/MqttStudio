import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/documentation/engine/doc_index.dart';
import 'package:mqttstudio/documentation/engine/doc_path.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';

DocNode topic(String path, {Map<String, String> patterns = const {}}) => DocNode(
    path: path,
    topic: TopicSpec(),
    parameters: [for (var name in DocPath.parameterNames(path)) DocParameter(name: name, pattern: patterns[name])]);

void main() {
  group('DocPath.validate', () {
    test('accepts literals and parameters with prefix and suffix', () {
      expect(DocPath.validate('plant/line1/temp'), isNull);
      expect(DocPath.validate('plant/{line}/m{machine}/temp'), isNull);
      expect(DocPath.validate('files/{name}.json'), isNull);
      expect(DocPath.validate('/leading/slash'), isNull);
      expect(DocPath.validate(r'$SYS/broker/uptime'), isNull);
    });

    test('rejects empty paths, wildcards and broken parameters', () {
      expect(DocPath.validate(''), DocPathError.empty);
      expect(DocPath.validate('plant/+/temp'), DocPathError.wildcard);
      expect(DocPath.validate('plant/#'), DocPathError.wildcard);
      expect(DocPath.validate('plant/{line'), DocPathError.invalidParameter);
      expect(DocPath.validate('plant/{}'), DocPathError.invalidParameter);
      expect(DocPath.validate('plant/{1line}'), DocPathError.invalidParameter);
      expect(DocPath.validate('plant/{a}{b}'), DocPathError.invalidParameter);
      expect(DocPath.validate('plant/{id}/x/{id}'), DocPathError.duplicateParameter);
    });

    test('lists the parameter names in path order', () {
      expect(DocPath.parameterNames('a/{x}/m{y}/c'), ['x', 'y']);
      expect(DocPath.parameterNames('a/b'), isEmpty);
    });
  });

  group('DocPath.match', () {
    test('captures parameter values without prefix and suffix', () {
      var path = DocPath.parse('plant/area{area}/m{machine}/temp');
      expect(path.match('plant/area1/m12/temp'), {'area': '1', 'machine': '12'});
      expect(path.match('plant/area1/m12/speed'), isNull);
      expect(path.match('plant/area1/m12'), isNull);
      expect(path.match('plant/area1/x12/temp'), isNull);
    });

    test('a parameter matches one non-empty level', () {
      var path = DocPath.parse('a/m{id}');
      expect(path.match('a/m'), isNull);
      expect(path.match('a/m1/b'), isNull);
    });

    test('a pattern must match the whole value', () {
      var path = DocPath.parse('a/m{id}');
      expect(path.match('a/m12', {'id': RegExp(r'\d+')}), {'id': '12'});
      expect(path.match('a/m12x', {'id': RegExp(r'\d+')}), isNull);
    });

    test('sameShape ignores the parameter names', () {
      expect(DocPath.parse('a/{x}/c').sameShape(DocPath.parse('a/{y}/c')), isTrue);
      expect(DocPath.parse('a/m{x}').sameShape(DocPath.parse('a/{x}')), isFalse);
      expect(DocPath.parse('a/b').sameShape(DocPath.parse('a/{b}')), isFalse);
    });
  });

  group('DocIndex', () {
    test('finds the template with the most literal segments', () {
      var exact = topic('plant/line1/m12/temp');
      var machine = topic('plant/line1/{machine}/temp');
      var any = topic('plant/{line}/{machine}/temp');
      var index = DocIndex([any, machine, exact]);
      expect(index.match('plant/line1/m12/temp')!.node, exact);
      expect(index.match('plant/line1/m51/temp')!.node, machine);
      expect(index.match('plant/line2/m51/temp')!.parameters, {'line': 'line2', 'machine': 'm51'});
      expect(index.match('plant/line2/m51/speed'), isNull);
    });

    test('a prefix beats a bare parameter, then the earlier literal wins', () {
      var prefixed = topic('a/m{id}');
      var bare = topic('a/{x}');
      expect(DocIndex([bare, prefixed]).match('a/m1')!.node, prefixed);
      var earlyLiteral = topic('a/b/{x}');
      var lateLiteral = topic('a/{y}/c');
      expect(DocIndex([lateLiteral, earlyLiteral]).match('a/b/c')!.node, earlyLiteral);
    });

    test('patterns restrict a match and fall through to other templates', () {
      var numbered = topic('a/{id}', patterns: {'id': r'\d+'});
      var named = topic('a/{name}/x');
      var index = DocIndex([numbered, named]);
      expect(index.match('a/12')!.node, numbered);
      expect(index.match('a/abc'), isNull);
    });

    test('namespace nodes and invalid paths are not matched', () {
      var index = DocIndex([DocNode(path: 'a/b'), DocNode(path: 'a/{x', topic: TopicSpec())]);
      expect(index.match('a/b'), isNull);
    });
  });
}
