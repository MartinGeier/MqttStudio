import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/simulator/engine/generator_instances.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';

final DateTime start = DateTime.utc(2026, 10, 24, 12);

GeneratorInstance instanceOf(PayloadGenerator generator, {int seed = 1, int instance = 1, String device = 'Dev'}) =>
    createGeneratorInstance(generator,
        GeneratorContext(random: Random(seed), instanceNumber: instance, deviceName: device, startedAt: start));

// texts of count messages, one every interval
List<String> run(GeneratorInstance instance, int count, {Duration interval = const Duration(seconds: 1)}) {
  var now = start;
  return [
    for (var i = 0; i < count; i++) instance.next(now = now.add(interval), interval).text!,
  ];
}

void main() {
  group('formatNumber', () {
    test('prints integers without decimals and rounds to the given decimals', () {
      expect(formatNumber(42.4, 0), '42');
      expect(formatNumber(42.0, 0), '42');
      expect(formatNumber(1.005, 2), anyOf('1.00', '1.01'));
      expect(formatNumber(21.44, 1), '21.4');
    });

    test('does not print a negative zero', () {
      expect(formatNumber(-0.001, 2), '0.00');
    });
  });

  group('RandomStringGenerator', () {
    test('lengths include both bounds, characters come from the set', () {
      var values = run(instanceOf(const RandomStringGenerator(minLength: 2, maxLength: 3, charSet: 'ab', prefix: '<', postfix: '>')), 300);
      var lengths = values.map((v) => v.length - 2).toSet();
      expect(lengths, {2, 3});
      expect(values.every((v) => v.startsWith('<') && v.endsWith('>')), isTrue);
      expect(values.every((v) => RegExp(r'^<[ab]+>$').hasMatch(v)), isTrue);
    });

    test('works when min equals max and when min is larger than max', () {
      expect(run(instanceOf(const RandomStringGenerator(minLength: 4, maxLength: 4)), 20).every((v) => v.length == 4),
          isTrue);
      var swapped = run(instanceOf(const RandomStringGenerator(minLength: 5, maxLength: 2)), 100);
      expect(swapped.every((v) => v.length >= 2 && v.length <= 5), isTrue);
    });
  });

  group('RandomNumberGenerator', () {
    test('stays in the range and uses the decimals', () {
      var values = run(instanceOf(const RandomNumberGenerator(min: 5, max: 15, decimals: 2, postfix: ' °C')), 200);
      for (var v in values) {
        expect(v, endsWith(' °C'));
        var number = double.parse(v.replaceAll(' °C', ''));
        expect(number, inInclusiveRange(5, 15));
        expect(v.split('.')[1].length, 2 + ' °C'.length);
      }
    });
  });

  group('CounterGenerator', () {
    test('counts up with prefix and starts over after resetAfter values', () {
      expect(run(instanceOf(const CounterGenerator(start: 10, step: 5, prefix: 'ORD-', resetAfter: 3)), 7),
          ['ORD-10', 'ORD-15', 'ORD-20', 'ORD-10', 'ORD-15', 'ORD-20', 'ORD-10']);
    });

    test('counts forever without resetAfter, also with decimals', () {
      expect(run(instanceOf(const CounterGenerator(start: 0.5, step: 0.25, decimals: 2)), 3), ['0.50', '0.75', '1.00']);
    });

    test('each instance has its own counter', () {
      var a = instanceOf(const CounterGenerator(), instance: 1);
      var b = instanceOf(const CounterGenerator(), instance: 2);
      run(a, 5);
      expect(run(b, 1), ['1']);
    });
  });

  group('BoolGenerator', () {
    test('uses the texts and the probability', () {
      expect(run(instanceOf(const BoolGenerator(trueProbability: 1, trueText: 'ON')), 10).toSet(), {'ON'});
      expect(run(instanceOf(const BoolGenerator(trueProbability: 0, falseText: '0')), 10).toSet(), {'0'});
      expect(run(instanceOf(const BoolGenerator()), 200).toSet(), {'true', 'false'});
    });
  });

  group('ValueListGenerator', () {
    test('sequential order cycles through the values', () {
      expect(run(instanceOf(const ValueListGenerator(values: ['a', 'b', 'c'], order: PickOrder.sequential)), 5),
          ['a', 'b', 'c', 'a', 'b']);
    });

    test('random order only returns listed values, an empty list returns an empty text', () {
      expect(run(instanceOf(const ValueListGenerator(values: ['x', 'y'])), 100).toSet(), {'x', 'y'});
      expect(run(instanceOf(const ValueListGenerator(values: [])), 2), ['', '']);
    });
  });

  group('RandomWalkGenerator', () {
    test('stays in the range and starts near the start value', () {
      var values = run(instanceOf(const RandomWalkGenerator(start: 20, min: 15, max: 25, volatility: 3)), 500)
          .map(double.parse)
          .toList();
      expect(values.every((v) => v >= 15 && v <= 25), isTrue);
      expect((values.first - 20).abs(), lessThanOrEqualTo(3.05));
    });

    test('a start outside the range is clamped', () {
      var first = double.parse(run(instanceOf(const RandomWalkGenerator(start: 100, min: 0, max: 10, volatility: 0)), 1).first);
      expect(first, 10);
    });

    test('the spread over a minute does not depend on the interval', () {
      double spreadAfterOneMinute(Duration interval) {
        var deviations = <double>[];
        for (var seed = 0; seed < 300; seed++) {
          var instance = instanceOf(const RandomWalkGenerator(start: 500, min: 0, max: 1000, volatility: 1, decimals: 4),
              seed: seed);
          var steps = const Duration(minutes: 1).inMilliseconds ~/ interval.inMilliseconds;
          var last = run(instance, steps, interval: interval).last;
          deviations.add(pow(double.parse(last) - 500, 2).toDouble());
        }
        return sqrt(deviations.reduce((a, b) => a + b) / deviations.length);
      }

      var fast = spreadAfterOneMinute(const Duration(milliseconds: 100));
      var slow = spreadAfterOneMinute(const Duration(seconds: 10));
      expect(fast / slow, inInclusiveRange(0.75, 1.33));
    });
  });

  group('WaveGenerator', () {
    test('a sine wave follows the time since the start', () {
      var wave = instanceOf(const WaveGenerator(amplitude: 2, offset: 1, periodSeconds: 60, decimals: 3));
      expect(wave.next(start.add(const Duration(seconds: 15)), Duration.zero).text, '3.000');
      expect(wave.next(start.add(const Duration(seconds: 45)), Duration.zero).text, '-1.000');
      expect(wave.next(start.add(const Duration(seconds: 60)), Duration.zero).text, '1.000');
    });

    test('square, triangle and sawtooth shapes', () {
      double at(WaveShape shape, int seconds) =>
          double.parse(instanceOf(WaveGenerator(shape: shape, periodSeconds: 4, decimals: 3))
              .next(start.add(Duration(seconds: seconds)), Duration.zero)
              .text!);
      expect(at(WaveShape.square, 1), 1);
      expect(at(WaveShape.square, 3), -1);
      expect(at(WaveShape.triangle, 1), 1);
      expect(at(WaveShape.triangle, 3), -1);
      expect(at(WaveShape.sawtooth, 2), closeTo(0, 0.001));
    });
  });

  group('TimestampGenerator', () {
    var now = DateTime.utc(2026, 10, 24, 14, 5, 31, 204);

    test('formats', () {
      expect(instanceOf(const TimestampGenerator()).next(now, Duration.zero).text, '2026-10-24T14:05:31.204Z');
      expect(instanceOf(const TimestampGenerator(format: TimestampFormat.epochMillis)).next(now, Duration.zero).text,
          '${now.millisecondsSinceEpoch}');
      expect(instanceOf(const TimestampGenerator(format: TimestampFormat.epochSeconds)).next(now, Duration.zero).text,
          '${now.millisecondsSinceEpoch ~/ 1000}');
      expect(
          instanceOf(const TimestampGenerator(format: TimestampFormat.pattern, pattern: 'yyyy-MM-dd HH:mm'))
              .next(now, Duration.zero)
              .text,
          '2026-10-24 14:05');
    });
  });

  group('GpsTrackGenerator', () {
    const center = GpsPoint(48.137154, 11.576124);

    test('wander stays inside the radius and gives lat,lon text and parts', () {
      var instance = instanceOf(const GpsTrackGenerator(radiusMeters: 500, speedMps: 30));
      var now = start;
      for (var i = 0; i < 500; i++) {
        var value = instance.next(now = now.add(const Duration(seconds: 2)), const Duration(seconds: 2));
        var parts = value.text!.split(',');
        var point = GpsPoint(double.parse(parts[0]), double.parse(parts[1]));
        expect(GeoMath.distance(center, point), lessThanOrEqualTo(501));
        expect(value.parts['lat'], parts[0]);
        expect(value.parts['lon'], parts[1]);
      }
    });

    test('json format', () {
      var text = instanceOf(const GpsTrackGenerator(format: GpsFormat.json)).next(start, Duration.zero).text!;
      var decoded = jsonDecode(text) as Map<String, dynamic>;
      expect(decoded.keys, ['lat', 'lon']);
    });

    test('route moves along the waypoints at the given speed, whatever the interval', () {
      const waypoints = [GpsPoint(48.0, 11.0), GpsPoint(48.01, 11.0)];
      double travelled(Duration interval) {
        var instance = instanceOf(const GpsTrackGenerator(mode: GpsMode.route, waypoints: waypoints, speedMps: 2));
        var first = instance.next(start, Duration.zero).parts;
        var steps = 60000 ~/ interval.inMilliseconds;
        var now = start;
        Map<String, String> last = first;
        for (var i = 0; i < steps; i++) {
          last = instance.next(now = now.add(interval), interval).parts;
        }
        return GeoMath.distance(GpsPoint(double.parse(first['lat']!), double.parse(first['lon']!)),
            GpsPoint(double.parse(last['lat']!), double.parse(last['lon']!)));
      }

      // 120 m along a 1.1 km segment; at a turn the straight distance can be shorter, so allow a margin
      expect(travelled(const Duration(milliseconds: 500)), closeTo(120, 15));
      expect(travelled(const Duration(seconds: 10)), closeTo(120, 15));
    });

    test('a route with fewer than 2 waypoints cannot start', () {
      expect(() => instanceOf(const GpsTrackGenerator(mode: GpsMode.route, waypoints: [GpsPoint(1, 1)])),
          throwsA(isA<GeneratorException>().having((e) => e.error, 'error', GeneratorError.routeTooShort)));
    });
  });

  group('RandomImageGenerator', () {
    late Directory folder;

    setUp(() {
      folder = Directory.systemTemp.createTempSync('sim_images');
    });

    tearDown(() {
      folder.deleteSync(recursive: true);
    });

    test('publishes the bytes of matching files with their content type', () {
      File('${folder.path}/a.png').writeAsBytesSync([1, 2, 3]);
      File('${folder.path}/b.JPG').writeAsBytesSync([4, 5]);
      File('${folder.path}/notes.txt').writeAsStringSync('skip');
      var instance = instanceOf(RandomImageGenerator(folderPath: folder.path, order: PickOrder.sequential));
      var first = instance.next(start, Duration.zero);
      var second = instance.next(start, Duration.zero);
      expect(first.bytes, [1, 2, 3]);
      expect(first.contentType, 'image/png');
      expect(first.describe(), '<binary 0.0 KB> a.png');
      expect(second.bytes, [4, 5]);
      expect(second.contentType, 'image/jpeg');
      expect(instance.next(start, Duration.zero).bytes, [1, 2, 3]);
    });

    test('skips files larger than the limit', () {
      File('${folder.path}/big.jpg').writeAsBytesSync(List.filled(RandomImageGenerator.maxFileSize + 1, 0));
      expect(() => instanceOf(RandomImageGenerator(folderPath: folder.path)),
          throwsA(isA<GeneratorException>().having((e) => e.error, 'error', GeneratorError.noUsableImages)));
    });

    test('a missing folder is a start error', () {
      expect(() => instanceOf(RandomImageGenerator(folderPath: '${folder.path}/missing')),
          throwsA(isA<GeneratorException>().having((e) => e.error, 'error', GeneratorError.imageFolderNotFound)));
    });
  });

  group('TemplateGenerator', () {
    test('inserts fields, parts and placeholders, each field once per message', () {
      var template = TemplateGenerator(
        template: '{"id":"dev-{n:3}","name":"{device}","count":{{count}},"lat":{{pos.lat}},"lon":{{pos.lon}},'
            '"again":{{count}}}',
        fields: {'count': const CounterGenerator(), 'pos': const GpsTrackGenerator()},
      );
      var value = instanceOf(template, instance: 7, device: 'Line/1').next(start, const Duration(seconds: 1));
      var decoded = jsonDecode(value.text!) as Map<String, dynamic>;
      expect(decoded['id'], 'dev-007');
      expect(decoded['name'], 'Line_1');
      expect(decoded['count'], 1);
      expect(decoded['again'], 1);
      expect(decoded['lat'], isA<double>());
      expect(value.contentType, 'application/json');
    });

    test('a field called n is not taken for the placeholder {n}', () {
      var template = TemplateGenerator(template: '{{n}} of {n}', fields: {'n': const CounterGenerator(start: 5)});
      expect(instanceOf(template, instance: 2).next(start, Duration.zero).text, '5 of 2');
    });

    test('unknown references stay as written, without validateJson there is no content type', () {
      var value = instanceOf(const TemplateGenerator(template: 'x={{missing}}', validateJson: false)).next(start, Duration.zero);
      expect(value.text, 'x={{missing}}');
      expect(value.contentType, isNull);
    });

    test('templates and images are not allowed as fields', () {
      expect(
          () => instanceOf(TemplateGenerator(template: '{{t}}', fields: {'t': const TemplateGenerator()})),
          throwsA(isA<GeneratorException>().having((e) => e.error, 'error', GeneratorError.invalidTemplateField)));
    });
  });
}
