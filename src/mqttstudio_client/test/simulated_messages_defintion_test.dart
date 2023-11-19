import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqttstudio/simulator/model/simulated_messages_definition.dart';

void main() {
  group('RandomStringSimulatedMessageDefinition', () {
    test('constructor initializes fields correctly', () {
      var messageDefinition = RandomStringSimulatedMessageDefinition('topicPath',
          minLength: 5, maxLength: 15, charSet: 'abc', qos: MqttQos.atLeastOnce, retained: true, prefix: 'pre', postfix: 'post');

      expect(messageDefinition.topicPath, equals('topicPath'));
      expect(messageDefinition.minLength, equals(5));
      expect(messageDefinition.maxLength, equals(15));
      expect(messageDefinition.charSet, equals('abc'));
      expect(messageDefinition.qos, equals(MqttQos.atLeastOnce));
      expect(messageDefinition.retained, equals(true));
      expect(messageDefinition.prefix, equals('pre'));
      expect(messageDefinition.postfix, equals('post'));
    });

    test('generatePayload returns string of correct length and with correct prefix and postfix', () {
      var messageDefinition = RandomStringSimulatedMessageDefinition('topicPath',
          minLength: 5, maxLength: 15, charSet: 'abc', qos: MqttQos.atLeastOnce, retained: true, prefix: 'pre', postfix: 'post');

      var payload = messageDefinition.generatePayload();
      expect(payload.length, greaterThanOrEqualTo(5 + 'pre'.length + 'post'.length));
      expect(payload.length, lessThanOrEqualTo(15 + 'pre'.length + 'post'.length));
      expect(payload.startsWith('pre'), equals(true));
      expect(payload.endsWith('post'), equals(true));
      expect(payload.substring('pre'.length, payload.length - 'post'.length).split('').every((x) => 'abc'.contains(x)), equals(true));
    });

    test('getPayloadDefintionString returns correct definition string', () {
      var messageDefinition = RandomStringSimulatedMessageDefinition('topicPath',
          minLength: 5, maxLength: 15, charSet: 'abc', qos: MqttQos.atLeastOnce, retained: true, prefix: 'pre', postfix: 'post');

      var definitionString = messageDefinition.getPayloadDefintionString();
      expect(definitionString, equals('type=rs; prefix=pre; postfix=post; minLength=5; maxLength=15; charSet=abc'));
    });
  });

  group('RandomNumberSimulatedMessageDefinition', () {
    // Write tests for the RandomNumberSimulatedMessageDefinition class.
    test('constructor initializes fields correctly', () {
      var messageDefinition = RandomNumberSimulatedMessageDefinition('topicPath',
          minValue: 5, maxValue: 15, qos: MqttQos.atLeastOnce, retained: true, prefix: 'pre', postfix: 'post');

      expect(messageDefinition.topicPath, equals('topicPath'));
      expect(messageDefinition.minValue, equals(5));
      expect(messageDefinition.maxValue, equals(15));
      expect(messageDefinition.qos, equals(MqttQos.atLeastOnce));
      expect(messageDefinition.retained, equals(true));
      expect(messageDefinition.prefix, equals('pre'));
      expect(messageDefinition.postfix, equals('post'));
    });

    test('generatePayload returns string of correct length and with correct prefix and postfix', () {
      var messageDefinition = RandomNumberSimulatedMessageDefinition('topicPath',
          minValue: 5, maxValue: 15, digitsAfterDecimalPoint: 2, qos: MqttQos.atLeastOnce, retained: true, prefix: 'pre', postfix: 'post');

      var payload = messageDefinition.generatePayload();
      // test number is between 5 and 15 by remioving prefix and postfix
      var number = double.parse(payload.substring('pre'.length, payload.length - 'post'.length));
      expect(number, greaterThanOrEqualTo(5));
      expect(number, lessThanOrEqualTo(15));
      expect(payload.startsWith('pre'), equals(true));
      expect(payload.endsWith('post'), equals(true));
    });

    test('getPayloadDefintionString returns correct definition string', () {
      var messageDefinition = RandomNumberSimulatedMessageDefinition('topicPath',
          minValue: 5, maxValue: 15, digitsAfterDecimalPoint: 2, qos: MqttQos.atLeastOnce, retained: true, prefix: 'pre', postfix: 'post');

      var definitionString = messageDefinition.getPayloadDefintionString();
      expect(definitionString, equals('type=rn; prefix=pre; postfix=post; minValue=5.0; maxValue=15.0; digitsAfterDecimalPoint=2'));
    });
  });

  group('IncrementingNumberSimulatedMessageDefinition', () {
    // Write tests for the IncrementalNumberSimulatedMessageDefinition class.
    test('constructor initializes fields correctly', () {
      var messageDefinition = IncrementingNumberSimulatedMessageDefinition('topicPath',
          nextValue: 1, increment: 2, digitsAfterDecimalPoint: 0, qos: MqttQos.atLeastOnce, retained: true);

      expect(messageDefinition.topicPath, equals('topicPath'));
      expect(messageDefinition.increment, equals(2));
      expect(messageDefinition.qos, equals(MqttQos.atLeastOnce));
      expect(messageDefinition.retained, equals(true));
      expect(messageDefinition.digitsAfterDecimalPoint, equals(0));
    });

    test('generatePayload returns string of correct length and with correct prefix and postfix', () {
      var messageDefinition = IncrementingNumberSimulatedMessageDefinition('topicPath',
          nextValue: 5, increment: 2, digitsAfterDecimalPoint: 0, qos: MqttQos.atLeastOnce, retained: true);

      var firstNumber = messageDefinition.generatePayload();
      // test number is between 5 and 15 by remioving prefix and postfix
      expect(firstNumber, greaterThanOrEqualTo(5));
      expect(firstNumber, lessThanOrEqualTo(15));

      var nextNumber = messageDefinition.generatePayload();
      // test number is between 5 and 15 by remioving prefix and postfix
      expect(nextNumber, equals(firstNumber + 2));
    });

    test('getPayloadDefintionString returns correct definition string', () {
      var messageDefinition = IncrementingNumberSimulatedMessageDefinition('topicPath',
          nextValue: 5, increment: 2, digitsAfterDecimalPoint: 0, qos: MqttQos.atLeastOnce, retained: true);

      var definitionString = messageDefinition.getPayloadDefintionString();
      expect(definitionString, equals('type=in; nextValue=5.0; increment=2.0; digitsAfterDecimalPoint=0'));
    });
  });

  group('IncrementingCodeSimulatedMessageDefinition', () {
    // write tests for IncrementingCodeSimulatedMessageDefinition class
    test('constructor initializes fields correctly', () {
      var messageDefinition = IncrementingCodeSimulatedMessageDefinition('topicPath',
          nextValue: 1, increment: 2, qos: MqttQos.atLeastOnce, retained: true, prefix: 'pre', postfix: 'post');

      expect(messageDefinition.topicPath, equals('topicPath'));
      expect(messageDefinition.increment, equals(2));
      expect(messageDefinition.qos, equals(MqttQos.atLeastOnce));
      expect(messageDefinition.retained, equals(true));
      expect(messageDefinition.prefix, equals('pre'));
      expect(messageDefinition.postfix, equals('post'));
    });

    test('generatePayload returns string of correct length and with correct prefix and postfix', () {
      var messageDefinition = IncrementingCodeSimulatedMessageDefinition('topicPath',
          nextValue: 5, increment: 2, qos: MqttQos.atLeastOnce, retained: true, prefix: 'pre', postfix: 'post');

      var firstCode = messageDefinition.generatePayload();
      // test number is between 5 and 15 by removing prefix and postfix from code
      var firstNumber = int.parse(firstCode.substring('pre'.length, firstCode.length - 'post'.length));
      expect(firstNumber, greaterThanOrEqualTo(5));
      expect(firstNumber, lessThanOrEqualTo(15));

      var nextCode = messageDefinition.generatePayload();
      // test number is between 5 and 15 by remioving prefix and postfix
      var nextNumber = int.parse(nextCode.substring('pre'.length, firstCode.length - 'post'.length));
      expect(nextNumber, equals(firstNumber + 2));
    });

    test('getPayloadDefintionString returns correct definition string', () {
      var messageDefinition = IncrementingCodeSimulatedMessageDefinition('topicPath',
          nextValue: 5, increment: 2, qos: MqttQos.atLeastOnce, retained: true, prefix: 'pre', postfix: 'post');

      var definitionString = messageDefinition.getPayloadDefintionString();
      expect(definitionString, equals('type=ic; prefix=pre; postfix=post; nextValue=5; increment=2'));
    });
  });
}
