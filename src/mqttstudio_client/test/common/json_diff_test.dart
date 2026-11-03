import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/common/utils/json_diff.dart';

void main() {
  group('JsonDiff compare', () {
    test('finds added, removed and changed members', () {
      var changes = JsonDiff.compare({'a': 1, 'b': 2, 'c': 3}, {'a': 1, 'b': 5, 'd': 4});

      expect(changes.map((c) => '${c.kind.name} ${c.path}'), ['changed \$.b', 'added \$.d', 'removed \$.c']);
      expect(changes.first.oldValue, 2);
      expect(changes.first.newValue, 5);
    });

    test('compares nested objects and arrays by index', () {
      var changes = JsonDiff.compare({
        'm': {
          'v': [1, 2, 3]
        }
      }, {
        'm': {
          'v': [1, 9]
        }
      });

      expect(changes.map((c) => '${c.kind.name} ${c.path}'), ['changed \$.m.v[1]', 'removed \$.m.v[2]']);
    });

    test('compares numbers by value and counts a type change once', () {
      expect(JsonDiff.compare({'a': 1}, {'a': 1.0}), isEmpty);
      var changes = JsonDiff.compare({
        'a': {'x': 1}
      }, {
        'a': 3
      });
      expect(changes.single.kind, JsonChangeKind.changed);
    });
  });

  group('JsonDiff lines', () {
    var oldJson = {'temp': 80, 'state': 'ok', 'gone': true};
    var newJson = {'temp': 81, 'state': 'ok', 'new': 1};

    test('mark the current side with the removed members struck out', () {
      var lines = JsonDiff.lines(oldJson, newJson, JsonDiffSide.current, withRemoved: true);

      expect(lines.map((l) => l.text), ['{', '"temp": 81,', '"state": "ok",', '"new": 1,', '"gone": true', '}']);
      expect(lines.map((l) => l.kind), [
        null,
        JsonChangeKind.changed,
        null,
        JsonChangeKind.added,
        JsonChangeKind.removed,
        null,
      ]);
      expect(lines[1].otherValue, '80');
    });

    test('mark the old side for side by side', () {
      var lines = JsonDiff.lines(oldJson, newJson, JsonDiffSide.old);

      expect(lines.map((l) => l.text), ['{', '"temp": 80,', '"state": "ok",', '"gone": true', '}']);
      expect(lines[3].kind, JsonChangeKind.removed);
      expect(lines[1].otherValue, '81');
    });

    test('mark everything in an added object', () {
      var lines = JsonDiff.lines({}, {
        'a': {'b': 1}
      }, JsonDiffSide.current);

      expect(lines.map((l) => l.text), ['{', '"a": {', '"b": 1', '}', '}']);
      expect(lines.sublist(1, 4).every((l) => l.kind == JsonChangeKind.added), isTrue);
      expect(lines[2].indent, 2);
    });
  });
}
