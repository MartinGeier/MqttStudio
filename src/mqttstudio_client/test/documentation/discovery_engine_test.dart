import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/engine/doc_path.dart';
import 'package:mqttstudio/documentation/engine/documentation_analyzer.dart';
import 'package:mqttstudio/documentation/engine/schema_inferrer.dart';
import 'package:mqttstudio/documentation/engine/template_detector.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';

final DateTime start = DateTime.utc(2026, 10, 24, 9);

RecordedMessage at(double seconds, String topic, String payload,
        {MqttQos qos = MqttQos.atLeastOnce, bool retain = false, bool snapshot = false}) =>
    RecordedMessage(
        offsetMicros: (seconds * 1000000).round(),
        topic: topic,
        payload: Uint8List.fromList(utf8.encode(payload)),
        qos: qos,
        retain: retain,
        snapshot: snapshot);

void feed(DocumentationAnalyzer analyzer, List<RecordedMessage> messages) {
  for (var message in messages) {
    analyzer.add(message, start.add(message.offset));
  }
}

void main() {
  group('ClassifiedPayload', () {
    PayloadFormat format(String text) => ClassifiedPayload.of(Uint8List.fromList(utf8.encode(text))).format;

    test('detects the payload formats', () {
      expect(format(''), PayloadFormat.empty);
      expect(format('75.6'), PayloadFormat.number);
      expect(format('TRUE'), PayloadFormat.boolean);
      expect(format('{"a":1}'), PayloadFormat.json);
      expect(format('[1,2]'), PayloadFormat.json);
      expect(format('{broken'), PayloadFormat.string);
      expect(format('46.49,11.33'), PayloadFormat.gnss);
      expect(format('running'), PayloadFormat.string);
      expect(ClassifiedPayload.of(Uint8List.fromList([0xff, 0xfe, 0x00])).format, PayloadFormat.binary);
      expect(ClassifiedPayload.of(Uint8List.fromList([137, 80, 78, 71, 1])).format, PayloadFormat.image);
    });
  });

  group('SchemaInferrer', () {
    test('required, integer, date-time, mixed and nested arrays', () {
      var inferrer = SchemaInferrer();
      inferrer.add({
        'state': 'running',
        'speed': 100,
        'ts': '2026-10-24T07:12:03Z',
        'x': 1,
        'alarms': [
          {'code': 3}
        ]
      });
      inferrer.add({'state': 'idle', 'speed': 120, 'ts': '2026-10-24T07:12:13Z', 'x': 'a', 'tool': 'T1', 'alarms': []});
      var schema = inferrer.build();
      expect(schema.required, {'state', 'speed', 'ts', 'x', 'alarms'});
      expect(schema.properties['speed']!.type, SchemaType.integer);
      expect(schema.properties['speed']!.minimum, 100);
      expect(schema.properties['speed']!.maximum, 120);
      expect(schema.properties['ts']!.format, 'date-time');
      expect(schema.properties['x']!.type, SchemaType.mixed);
      expect(schema.properties['alarms']!.items!.properties['code']!.type, SchemaType.integer);
      expect(inferrer.presence()[r'$.tool'], 0.5);
    });

    test('a few distinct strings over enough samples become an enum', () {
      var inferrer = SchemaInferrer();
      for (var i = 0; i < 20; i++) {
        inferrer.add({
          'state': ['running', 'idle', 'setup'][i % 3],
          'id': 'id-$i'
        });
      }
      var schema = inferrer.build();
      expect(schema.properties['state']!.enumValues, ['idle', 'running', 'setup']);
      expect(schema.properties['id']!.enumValues, isEmpty);
    });

    test('merging keeps the union of what both saw', () {
      var a = SchemaInferrer()..add({'a': 1.5});
      var b = SchemaInferrer()..add({'a': 3, 'b': true});
      a.merge(b);
      var schema = a.build();
      expect(schema.properties['a']!.type, SchemaType.number);
      expect(schema.properties['a']!.maximum, 3);
      expect(schema.required, {'a'});
    });
  });

  group('DocumentationAnalyzer', () {
    test('a regular topic is periodic, with its rate, QoS and sizes', () {
      var analyzer = DocumentationAnalyzer();
      feed(analyzer, [for (var i = 0; i < 10; i++) at(i * 1.0 + (i.isEven ? 0.02 : 0), 'plant/temp', '${20 + i}')]);
      analyzer.finish(start.add(Duration(seconds: 10)));
      var observed = analyzer.observe(['plant/temp']);
      expect(observed.messages, 10);
      expect(observed.interval.kind, IntervalKind.periodic);
      expect(observed.interval.medianMs, closeTo(1000, 30));
      expect(observed.interval.rate, closeTo(1.0, 0.01));
      expect(observed.mainQos, 1);
      expect(observed.mainFormat, PayloadFormat.number);
      expect(observed.numericMin, 20);
      expect(observed.numericMax, 29);
      expect(observed.sizeMin, 2);
      expect(observed.lastPayload, '29');
    });

    test('irregular changing values are on change, repeated values are events', () {
      var analyzer = DocumentationAnalyzer();
      feed(analyzer, [
        for (var (i, t) in [0.0, 0.3, 5.0, 5.1, 20.0, 31.0].indexed) at(t, 'a/state', 'v$i'),
        for (var t in [0.0, 0.3, 5.0, 5.1, 20.0, 31.0]) at(t, 'a/alarm', 'on'),
      ]);
      expect(analyzer.observe(['a/state']).interval.kind, IntervalKind.onChange);
      expect(analyzer.observe(['a/alarm']).interval.kind, IntervalKind.event);
    });

    test('retained snapshot messages count as retained but are no intervals', () {
      var analyzer = DocumentationAnalyzer();
      feed(analyzer, [
        at(0, 'a/config', '{"v":1}', retain: true, snapshot: true),
        at(0.1, 'a/status', '1', retain: true, snapshot: true),
        at(10, 'a/status', '0', retain: true),
        at(20, 'a/status', '1', retain: true),
      ]);
      var config = analyzer.observe(['a/config']);
      expect(config.retainedSnapshot, 1);
      expect(config.interval.kind, IntervalKind.unknown);
      var status = analyzer.observe(['a/status']);
      expect(status.retainedLive, 2);
      expect(status.interval.medianMs, 10000);
    });

    test('a template merges its instances and lists the parameter values', () {
      var analyzer = DocumentationAnalyzer();
      feed(analyzer, [
        at(0, 'p/m12/temp', '{"t":1}'),
        at(0.5, 'p/m51/temp', '{"t":2,"x":"a"}'),
      ]);
      var observed = analyzer.observe(['p/m12/temp', 'p/m51/temp'], template: DocPath.parse('p/m{machine}/temp'));
      expect(observed.instanceCount, 2);
      expect(observed.parameterValues, {
        'machine': ['12', '51']
      });
      expect(observed.schema!.required, {'t'});
      expect(observed.fieldPresence[r'$.x'], 0.5);
      expect(observed.lastTopic, 'p/m51/temp');
    });

    test('numbers that are only 0 and 1 are booleans', () {
      var analyzer = DocumentationAnalyzer();
      feed(analyzer, [for (var i = 0; i < 12; i++) at(i * 1.0, 'a/on', '${i % 2}')]);
      expect(analyzer.observe(['a/on']).mainFormat, PayloadFormat.boolean);
    });

    test('topics beyond the limit are skipped', () {
      var analyzer = DocumentationAnalyzer(maxTopics: 2);
      feed(analyzer, [at(0, 'a', '1'), at(0, 'b', '1'), at(0, 'c', '1'), at(1, 'a', '2')]);
      expect(analyzer.topicCount, 2);
      expect(analyzer.topicLimitReached, isTrue);
      expect(analyzer.messages, 3);
    });
  });

  group('TemplateDetector', () {
    Map<String, int> detect(List<String> topics) =>
        {for (var topic in TemplateDetector.detect(topics)) topic.path: topic.topics.length};

    test('machines with the same topics become a parameter, the topics of one machine stay literal', () {
      var topics = [
        for (var machine in ['m12', 'm51', 'm33'])
          for (var leaf in ['temp', 'speed', 'state']) 'plant/line1/$machine/$leaf',
        'plant/line1/status',
      ];
      expect(detect(topics), {
        'plant/line1/m{id}/speed': 3,
        'plant/line1/m{id}/state': 3,
        'plant/line1/m{id}/temp': 3,
        'plant/line1/status': 1,
      });
      var temp = TemplateDetector.detect(topics).firstWhere((topic) => topic.path.endsWith('temp'));
      expect(temp.patterns, {'id': r'\d+'});
    });

    test('two numbered levels with the same topics become a parameter too, several levels at once', () {
      var topics = [
        for (var area in ['area1', 'area2'])
          for (var machine in ['m1', 'm2', 'm3']) 'f/$area/$machine/temp',
      ];
      expect(detect(topics), {'f/area{area}/m{id}/temp': 6});
    });

    test('different leaf topics and unrelated namespaces stay literal', () {
      expect(detect(['a/temp', 'a/speed', 'a/state', 'b/x/y', 'c/z']).keys,
          ['a/speed', 'a/state', 'a/temp', 'b/x/y', 'c/z']);
    });

    test('numbered leaves become a parameter, uuids too', () {
      expect(detect(['meters/1', 'meters/2', 'meters/3']), {'meters/{meter}': 3});
      var ids = [
        '0b6f5a4e-1c2d-4e5f-8a9b-0c1d2e3f4a5b',
        '1c7a6b5f-2d3e-4f60-9b0c-1d2e3f4a5b6c',
        '2d8b7c60-3e4f-5061-0c1d-2e3f4a5b6c7d'
      ];
      var detected = TemplateDetector.detect([for (var id in ids) 'devices/$id/state']).single;
      expect(detected.path, 'devices/{device}/state');
      expect(detected.patterns['device'], isNotNull);
    });

    test('words as instances become a parameter when their subtrees match', () {
      expect(detect(['home/kitchen/temp', 'home/garage/temp', 'home/attic/temp']), {'home/{id}/temp': 3});
    });
  });
}
