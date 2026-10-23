import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/simulator/model/simulated_messages_definition.dart';

void main() {
  group('Parsing payload definition strings', () {
    test('random string', () {
      var definition = RandomStringSimulatedMessageDefinition.fromPayloadDefinitionString(
          'a/b', 'type=rs;minLength=2;maxLength=4;charSet=xy;prefix=<;postfix=>');

      expect(definition.minLength, 2);
      expect(definition.maxLength, 4);
      expect(definition.charSet, 'xy');
      expect(definition.prefix, '<');
      expect(definition.postfix, '>');
    });

    test('random number', () {
      var definition = RandomNumberSimulatedMessageDefinition.fromPayloadDefinitionString(
          'a/b', 'type=rn;minValue=1.5;maxValue=2.5;digitsAfterDecimalPoint=1;prefix=;postfix= °C');

      expect(definition.minValue, 1.5);
      expect(definition.maxValue, 2.5);
      expect(definition.digitsAfterDecimalPoint, 1);
      expect(definition.postfix, ' °C');
    });

    test('incrementing number and code', () {
      var number = IncrementingNumberSimulatedMessageDefinition.fromPayloadDefinitionString(
          'a/b', 'type=in;nextValue=10;increment=0.5;digitsAfterDecimalPoint=1');
      var code = IncrementingCodeSimulatedMessageDefinition.fromPayloadDefinitionString(
          'a/b', 'type=ic;nextValue=100;increment=5;prefix=ID-;postfix=');

      expect([number.generatePayload(), number.generatePayload()], [10.0, 10.5]);
      expect([code.generatePayload(), code.generatePayload()], ['ID-100', 'ID-105']);
    });

    test('discrete strings and numbers', () {
      var strings = DiscreteStringsSimulatedMessageDefinition.fromPayloadDefinitionString(
          'a/b', 'type=ds;strings=on,off;prefix=;postfix=');
      var numbers = DiscreteNumbersSimulatedMessageDefinition.fromPayloadDefinitionString(
          'a/b', 'type=dn;numbers=1,2.5;prefix=;postfix=');

      expect(strings.strings, ['on', 'off']);
      expect(numbers.numbers, [1, 2.5]);
    });

    test('random bool', () {
      var definition = RandomBoolSimulatedMessageDefinition.fromPayloadDefinitionString('a/b', 'type=rb');
      expect(definition.generatePayload(), isA<bool>());
    });

    test('rejects a definition of another type', () {
      expect(
          () => RandomStringSimulatedMessageDefinition.fromPayloadDefinitionString('a/b', 'type=rn'), throwsException);
    });

    test('rejects unknown keys and malformed parts', () {
      expect(() => RandomStringSimulatedMessageDefinition.fromPayloadDefinitionString('a/b', 'type=rs;color=red'),
          throwsException);
      expect(() => RandomStringSimulatedMessageDefinition.fromPayloadDefinitionString('a/b', 'type=rs;minLength'),
          throwsException);
    });
  });

  group('Definition strings round trip', () {
    test('random string',
        skip:
            'Known bug: getPayloadDefintionString separates the parts with "; ", the parser does not accept the space',
        () {
      var original = RandomStringSimulatedMessageDefinition('a/b', minLength: 2, maxLength: 4, charSet: 'xy');

      var copy = RandomStringSimulatedMessageDefinition.fromPayloadDefinitionString(
          'a/b', original.getPayloadDefintionString());

      expect(copy.minLength, 2);
      expect(copy.maxLength, 4);
    });

    test('discrete strings',
        skip:
            'Known bug: getPayloadDefintionString separates the parts with "; ", the parser does not accept the space',
        () {
      var original = DiscreteStringsSimulatedMessageDefinition('a/b', ['on', 'off']);

      var copy = DiscreteStringsSimulatedMessageDefinition.fromPayloadDefinitionString(
          'a/b', original.getPayloadDefintionString());

      expect(copy.strings, ['on', 'off']);
    });

    test('random bool',
        skip:
            'Known bug: getPayloadDefintionString of random bool writes "type=rb qos:=...", which is no valid definition',
        () {
      var original = RandomBoolSimulatedMessageDefinition('a/b');

      expect(
          () => RandomBoolSimulatedMessageDefinition.fromPayloadDefinitionString(
              'a/b', original.getPayloadDefintionString()),
          returnsNormally);
    });
  });

  group('Generated payloads', () {
    test('discrete strings and numbers pick one of the values', () {
      var strings = DiscreteStringsSimulatedMessageDefinition('a/b', ['on', 'off'], prefix: '[', postfix: ']');
      var numbers = DiscreteNumbersSimulatedMessageDefinition('a/b', [1, 2]);

      for (var i = 0; i < 20; i++) {
        expect(['[on]', '[off]'], contains(strings.generatePayload()));
        expect(['1.0', '2.0'], contains(numbers.generatePayload()));
      }
    });

    test('random number without decimals is an integer', () {
      var definition = RandomNumberSimulatedMessageDefinition('a/b', minValue: 1, maxValue: 3);

      for (var i = 0; i < 20; i++) {
        expect(int.tryParse(definition.generatePayload()), isNotNull);
      }
    });

    test('random string can reach the maximum length',
        skip: 'Known bug: generatePayload uses nextInt(maxLength - minLength), so maxLength is never reached', () {
      var definition = RandomStringSimulatedMessageDefinition('a/b', minLength: 1, maxLength: 2, charSet: 'x');

      var lengths = {for (var i = 0; i < 50; i++) (definition.generatePayload() as String).length};

      expect(lengths, {1, 2});
    });

    test('random string with equal minimum and maximum length',
        skip: 'Known bug: generatePayload calls nextInt(0), which throws', () {
      var definition = RandomStringSimulatedMessageDefinition('a/b', minLength: 3, maxLength: 3, charSet: 'x');

      expect(definition.generatePayload(), 'xxx');
    });

    test('random image returns one of the images of the folder', () async {
      var dir = await Directory.systemTemp.createTemp('mqttstudio_images');
      addTearDown(() => dir.delete(recursive: true));
      File('${dir.path}/a.png').writeAsBytesSync([0]);
      File('${dir.path}/b.txt').writeAsBytesSync([0]);

      var definition = RandomImageSimulatedMessageDefinition('a/b', dir.path);

      expect(definition.generatePayload(), endsWith('a.png'));
    });

    test('json template replaces the fields',
        skip: 'Known bug: generatePayload discards the result of replaceAllMapped and returns the template unchanged',
        () {
      var definition = JsonSimulatedMessageDefintion('a/b',
          '{"code": "{{type=ic;nextValue=7;increment=1;prefix=;postfix=}}", "state": "{{type=ds;strings=on;prefix=;postfix=}}"}');

      var payload = jsonDecode(definition.generatePayload());

      expect(payload['code'], '7');
      expect(payload['state'], 'on');
    });
  });
}
