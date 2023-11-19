import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:mqtt_client/mqtt_client.dart';
import 'dart:math';

class SimulatedMessageDefinition {
  late String topicPath;
  MqttQos qos;
  bool retained;

  SimulatedMessageDefinition(this.topicPath, {this.qos = MqttQos.atLeastOnce, this.retained = false});

  SimulatedMessageDefinition.fromPayloadDefinitionString(this.topicPath, String defintion,
      {this.qos = MqttQos.atLeastOnce, this.retained = false});

  // generate the message payload
  dynamic generatePayload() {
    throw Exception("not implemented");
  }

  String getPayloadDefintionString() {
    throw Exception("not implemented");
  }
}

class SimulatedMessageDefintionWithPrefixPostfix extends SimulatedMessageDefinition {
  late String prefix;
  late String postfix;

  SimulatedMessageDefintionWithPrefixPostfix(String topicPath,
      {MqttQos qos = MqttQos.atLeastOnce, bool retained = false, this.prefix = "", this.postfix = ""})
      : super(topicPath, qos: qos, retained: retained);

  SimulatedMessageDefintionWithPrefixPostfix.fromPayloadDefinitionString(String topicPath, String definition,
      {MqttQos qos = MqttQos.atLeastOnce, bool retained = false})
      : super.fromPayloadDefinitionString(topicPath, definition, qos: qos, retained: retained);
}

class RandomStringSimulatedMessageDefinition extends SimulatedMessageDefintionWithPrefixPostfix {
  late int minLength;
  late int maxLength;
  late String charSet;

  RandomStringSimulatedMessageDefinition(String topicPath,
      {this.minLength = 3,
      this.maxLength = 10,
      this.charSet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
      MqttQos qos = MqttQos.atLeastOnce,
      bool retained = false,
      String prefix = "",
      String postfix = ""})
      : super(topicPath, qos: qos, retained: retained, prefix: prefix, postfix: postfix);

  RandomStringSimulatedMessageDefinition.fromPayloadDefinitionString(String topicPath, String definition,
      {MqttQos qos = MqttQos.atLeastOnce, bool retained = false})
      : super.fromPayloadDefinitionString(topicPath, definition, qos: qos, retained: retained) {
    var parts = definition.split(";");
    for (var part in parts) {
      var keyValue = part.split("=");
      if (keyValue.length != 2) {
        throw Exception("Invalid definition string");
      }
      switch (keyValue[0]) {
        case "minLength":
          minLength = int.parse(keyValue[1]);
          break;
        case "maxLength":
          maxLength = int.parse(keyValue[1]);
          break;
        case "charSet":
          charSet = keyValue[1];
          break;
        case "type":
          if (keyValue[1] != "rs") {
            throw Exception("Invalid definition string");
          }
          break;
        case "prefix":
          prefix = keyValue[1];
          break;
        case "postfix":
          postfix = keyValue[1];
          break;
        default:
          throw Exception("Invalid definition string");
      }
    }
  }

  // generate payload considering minLength, maxLength, charSet, prefix and postfix
  @override
  dynamic generatePayload() {
    int length = Random().nextInt(maxLength - minLength) + minLength;
    String payload = prefix;
    for (int i = 0; i < length; i++) {
      payload += charSet[Random().nextInt(charSet.length)];
    }
    payload += postfix;
    return payload;
  }

  @override
  String getPayloadDefintionString() {
    return "type=rs; prefix=$prefix; postfix=$postfix; minLength=$minLength; maxLength=$maxLength; charSet=$charSet";
  }
}

class RandomNumberSimulatedMessageDefinition extends SimulatedMessageDefintionWithPrefixPostfix {
  late double minValue;
  late double maxValue;
  late int digitsAfterDecimalPoint;

  RandomNumberSimulatedMessageDefinition(String topicPath,
      {this.minValue = 1,
      this.maxValue = 100,
      this.digitsAfterDecimalPoint = 0,
      MqttQos qos = MqttQos.atLeastOnce,
      bool retained = false,
      String prefix = "",
      String postfix = ""})
      : super(topicPath, qos: qos, retained: retained, prefix: prefix, postfix: postfix);

  RandomNumberSimulatedMessageDefinition.fromPayloadDefinitionString(String topicPath, String definition,
      {MqttQos qos = MqttQos.atLeastOnce, bool retained = false})
      : super.fromPayloadDefinitionString(topicPath, definition, qos: qos, retained: retained) {
    var parts = definition.split(";");
    for (var part in parts) {
      var keyValue = part.split("=");
      if (keyValue.length != 2) {
        throw Exception("Invalid definition string");
      }
      switch (keyValue[0]) {
        case "minValue":
          minValue = double.parse(keyValue[1]);
          break;
        case "maxValue":
          maxValue = double.parse(keyValue[1]);
          break;
        case "type":
          if (keyValue[1] != "rn") {
            throw Exception("Invalid definition string");
          }
          break;
        case "prefix":
          prefix = keyValue[1];
          break;
        case "postfix":
          postfix = keyValue[1];
          break;
        case "digitsAfterDecimalPoint":
          digitsAfterDecimalPoint = int.parse(keyValue[1]);
          break;
        default:
          throw Exception("Invalid definition string");
      }
    }
  }

  @override
  dynamic generatePayload() {
    // round double to 2 decimal places
    double number = (Random().nextDouble() * (maxValue - minValue) + minValue);
    var roundedNumber = digitsAfterDecimalPoint > 0
        ? double.parse(number.toStringAsFixed(digitsAfterDecimalPoint))
        : int.parse(number.toStringAsFixed(digitsAfterDecimalPoint));
    return prefix + roundedNumber.toString() + postfix;
  }

  @override
  String getPayloadDefintionString() {
    return "type=rn; prefix=$prefix; postfix=$postfix; minValue=$minValue; maxValue=$maxValue; digitsAfterDecimalPoint=$digitsAfterDecimalPoint";
  }
}

class IncrementingNumberSimulatedMessageDefinition extends SimulatedMessageDefinition {
  late double nextValue;
  late double increment;
  late int digitsAfterDecimalPoint;

  IncrementingNumberSimulatedMessageDefinition(String topicPath,
      {this.nextValue = 1, this.increment = 1, this.digitsAfterDecimalPoint = 0, MqttQos qos = MqttQos.atLeastOnce, bool retained = false})
      : super(topicPath, qos: qos, retained: retained);

  IncrementingNumberSimulatedMessageDefinition.fromPayloadDefinitionString(String topicPath, String definition,
      {MqttQos qos = MqttQos.atLeastOnce, bool retained = false})
      : super.fromPayloadDefinitionString(topicPath, definition, qos: qos, retained: retained) {
    var parts = definition.split(";");
    for (var part in parts) {
      var keyValue = part.split("=");
      if (keyValue.length != 2) {
        throw Exception("Invalid definition string");
      }
      switch (keyValue[0]) {
        case "nextValue":
          nextValue = double.parse(keyValue[1]);
          break;
        case "increment":
          increment = double.parse(keyValue[1]);
          break;
        case "digitsAfterDecimalPoint":
          digitsAfterDecimalPoint = int.parse(keyValue[1]);
          break;
        case "type":
          if (keyValue[1] != "in") {
            throw Exception("Invalid definition string");
          }
          break;
        default:
          throw Exception("Invalid definition string");
      }
    }
  }

  @override
  dynamic generatePayload() {
    double payload = nextValue;
    nextValue += increment;
    // round to digitsAfterDecimalPoint decimal places
    var payloadRounded = digitsAfterDecimalPoint > 0
        ? double.parse(payload.toStringAsFixed(digitsAfterDecimalPoint))
        : int.parse(payload.toStringAsFixed(digitsAfterDecimalPoint));
    return payloadRounded;
  }

  @override
  String getPayloadDefintionString() {
    return "type=in; nextValue=$nextValue; increment=$increment; digitsAfterDecimalPoint=$digitsAfterDecimalPoint";
  }
}

class IncrementingCodeSimulatedMessageDefinition extends SimulatedMessageDefintionWithPrefixPostfix {
  int nextValue = 1;
  int increment = 1;

  IncrementingCodeSimulatedMessageDefinition(String topicPath,
      {this.nextValue = 1,
      this.increment = 1,
      MqttQos qos = MqttQos.atLeastOnce,
      bool retained = false,
      String prefix = "",
      String postfix = ""})
      : super(topicPath, qos: qos, retained: retained, prefix: prefix, postfix: postfix);

  IncrementingCodeSimulatedMessageDefinition.fromPayloadDefinitionString(String topicPath, String definition,
      {MqttQos qos = MqttQos.atLeastOnce, bool retained = false})
      : super.fromPayloadDefinitionString(topicPath, definition, qos: qos, retained: retained) {
    var parts = definition.split(";");
    for (var part in parts) {
      var keyValue = part.split("=");
      if (keyValue.length != 2) {
        throw Exception("Invalid definition string");
      }
      switch (keyValue[0]) {
        case "nextValue":
          nextValue = int.parse(keyValue[1]);
          break;
        case "increment":
          increment = int.parse(keyValue[1]);
          break;
        case "type":
          if (keyValue[1] != "ic") {
            throw Exception("Invalid definition string");
          }
          break;
        case "prefix":
          prefix = keyValue[1];
          break;
        case "postfix":
          postfix = keyValue[1];
          break;
        default:
          throw Exception("Invalid definition string");
      }
    }
  }

  @override
  dynamic generatePayload() {
    int payload = nextValue;
    nextValue += increment;
    return prefix + payload.toString() + postfix;
  }

  @override
  String getPayloadDefintionString() {
    return "type=ic; prefix=$prefix; postfix=$postfix; nextValue=$nextValue; increment=$increment";
  }
}

class RandomBoolSimulatedMessageDefinition extends SimulatedMessageDefinition {
  RandomBoolSimulatedMessageDefinition(String topicPath, {MqttQos qos = MqttQos.atLeastOnce, bool retained = false})
      : super(topicPath, qos: qos, retained: retained);

  RandomBoolSimulatedMessageDefinition.fromPayloadDefinitionString(String topicPath, String definition,
      {MqttQos qos = MqttQos.atLeastOnce, bool retained = false})
      : super.fromPayloadDefinitionString(topicPath, definition, qos: qos, retained: retained) {
    var parts = definition.split(";");
    for (var part in parts) {
      var keyValue = part.split("=");
      if (keyValue.length != 2) {
        throw Exception("Invalid definition string");
      }
      switch (keyValue[0]) {
        case "type":
          if (keyValue[1] != "rb") {
            throw Exception("Invalid definition string");
          }
          break;
        default:
          throw Exception("Invalid definition string");
      }
    }
  }

  @override
  dynamic generatePayload() {
    return Random().nextBool();
  }

  @override
  String getPayloadDefintionString() {
    return "type=rb qos:=$qos; retained=$retained";
  }
}

class DiscreteStringsSimulatedMessageDefinition extends SimulatedMessageDefintionWithPrefixPostfix {
  List<String> strings = ["String 1", "String 2", "String 3"];

  DiscreteStringsSimulatedMessageDefinition(String topicPath, this.strings,
      {MqttQos qos = MqttQos.atLeastOnce, bool retained = false, String prefix = "", String postfix = ""})
      : super(topicPath, qos: qos, retained: retained, prefix: prefix, postfix: postfix);

  DiscreteStringsSimulatedMessageDefinition.fromPayloadDefinitionString(String topicPath, String definition,
      {MqttQos qos = MqttQos.atLeastOnce, bool retained = false})
      : super.fromPayloadDefinitionString(topicPath, definition, qos: qos, retained: retained) {
    var parts = definition.split(";");
    for (var part in parts) {
      var keyValue = part.split("=");
      if (keyValue.length != 2) {
        throw Exception("Invalid definition string");
      }
      switch (keyValue[0]) {
        case "strings":
          strings = keyValue[1].split(",");
          break;
        case "type":
          if (keyValue[1] != "ds") {
            throw Exception("Invalid definition string");
          }
          break;
        case "prefix":
          prefix = keyValue[1];
          break;
        case "postfix":
          postfix = keyValue[1];
          break;
        default:
          throw Exception("Invalid definition string");
      }
    }
  }

  @override
  dynamic generatePayload() {
    return prefix + strings[Random().nextInt(strings.length)] + postfix;
  }

  @override
  String getPayloadDefintionString() {
    // escape , in strings when joining
    var escapedStrings = strings.map((e) => e.replaceAll(",", "\\,")).toList();
    return "type=ds; prefix=$prefix; postfix=$postfix; strings=${escapedStrings.join(",")}";
  }
}

class DiscreteNumbersSimulatedMessageDefinition extends SimulatedMessageDefintionWithPrefixPostfix {
  List<double> numbers = [1, 2, 3];

  DiscreteNumbersSimulatedMessageDefinition(String topicPath, this.numbers,
      {MqttQos qos = MqttQos.atLeastOnce, bool retained = false, String prefix = "", String postfix = ""})
      : super(topicPath, qos: qos, retained: retained, prefix: prefix, postfix: postfix);

  DiscreteNumbersSimulatedMessageDefinition.fromPayloadDefinitionString(String topicPath, String definition,
      {MqttQos qos = MqttQos.atLeastOnce, bool retained = false})
      : super.fromPayloadDefinitionString(topicPath, definition, qos: qos, retained: retained) {
    var parts = definition.split(";");
    for (var part in parts) {
      var keyValue = part.split("=");
      if (keyValue.length != 2) {
        throw Exception("Invalid definition string");
      }
      switch (keyValue[0]) {
        case "numbers":
          numbers = keyValue[1].split(",").map((e) => double.parse(e)).toList();
          break;
        case "type":
          if (keyValue[1] != "dn") {
            throw Exception("Invalid definition string");
          }
          break;
        case "prefix":
          prefix = keyValue[1];
          break;
        case "postfix":
          postfix = keyValue[1];
          break;
        default:
          throw Exception("Invalid definition string");
      }
    }
  }

  @override
  dynamic generatePayload() {
    return prefix + numbers[Random().nextInt(numbers.length)].toString() + postfix;
  }

  @override
  String getPayloadDefintionString() {
    var escapedNumbers = numbers.map((e) => e.toString().replaceAll(",", "\\,")).toList();
    return "type=dn; prefix=$prefix; postfix=$postfix; numbers=${escapedNumbers.join(",")}";
  }
}

class RandomImageSimulatedMessageDefinition extends SimulatedMessageDefinition {
  late String imagesFolderPath;

  RandomImageSimulatedMessageDefinition(String topicPath, this.imagesFolderPath, {MqttQos qos = MqttQos.atLeastOnce, bool retained = false})
      : super(topicPath, qos: qos, retained: retained);

  RandomImageSimulatedMessageDefinition.fromPayloadDefinitionString(String topicPath, String definition,
      {MqttQos qos = MqttQos.atLeastOnce, bool retained = false})
      : super.fromPayloadDefinitionString(topicPath, definition, qos: qos, retained: retained) {
    var parts = definition.split(";");
    for (var part in parts) {
      var keyValue = part.split("=");
      if (keyValue.length != 2) {
        throw Exception("Invalid definition string");
      }
      switch (keyValue[0]) {
        case "imagesFolderPath":
          imagesFolderPath = keyValue[1];
          break;
        case "type":
          if (keyValue[1] != "ri") {
            throw Exception("Invalid definition string");
          }
          break;
        default:
          throw Exception("Invalid definition string");
      }
    }
  }

  @override
  dynamic generatePayload() {
    // get a list of images from imagesFolderPath folder
    var images = Directory(imagesFolderPath)
        .listSync()
        .where((x) => x is File && ['.jpg', '.jpeg', '.png'].contains(path.extension(x.path)))
        .toList();

    // return a random image
    return images[Random().nextInt(images.length)].path;
  }

  @override
  String getPayloadDefintionString() {
    return "type=ri; imagesFolderPath=$imagesFolderPath";
  }
}

class JsonSimulatedMessageDefintion extends SimulatedMessageDefinition {
  String jsonTemplate;

  JsonSimulatedMessageDefintion(String topicPath, this.jsonTemplate, {MqttQos qos = MqttQos.atLeastOnce, bool retained = false})
      : super(topicPath, qos: qos, retained: retained);

  @override
  dynamic generatePayload() {
    // search the template for fields denoted by {{definition}}, take the content of the field as definition string and generate the payload
    var payload = jsonTemplate;
    payload.replaceAllMapped(RegExp(r"\{\{.*?\}\}"), (match) {
      var field = match.group(0);
      var definition = field!.substring(2, field.length - 2);
      var definitionParts = definition.split(";");
      var type = definitionParts.where((x) => x.startsWith("type=")).first.split("=")[1];
      switch (type) {
        case "rs":
          var minLength = int.parse(definitionParts.where((x) => x.startsWith("minLength=")).first.split("=")[1]);
          var maxLength = int.parse(definitionParts.where((x) => x.startsWith("maxLength=")).first.split("=")[1]);
          var charSet = definitionParts.where((x) => x.startsWith("charSet=")).first.split("=")[1];
          var prefix = definitionParts.where((x) => x.startsWith("prefix=")).first.split("=")[1];
          var postfix = definitionParts.where((x) => x.startsWith("postfix=")).first.split("=")[1];
          var value = RandomStringSimulatedMessageDefinition("",
                  minLength: minLength, maxLength: maxLength, charSet: charSet, prefix: prefix, postfix: postfix)
              .generatePayload();
          return value;

        case "rn":
          var minValue = double.parse(definitionParts.where((x) => x.startsWith("minValue=")).first.split("=")[1]);
          var maxValue = double.parse(definitionParts.where((x) => x.startsWith("maxValue=")).first.split("=")[1]);
          var prefix = definitionParts.where((x) => x.startsWith("prefix=")).first.split("=")[1];
          var postfix = definitionParts.where((x) => x.startsWith("postfix=")).first.split("=")[1];
          var value = RandomNumberSimulatedMessageDefinition("", minValue: minValue, maxValue: maxValue, prefix: prefix, postfix: postfix)
              .generatePayload();
          return value;

        case "in":
          var nextValue = double.parse(definitionParts.where((x) => x.startsWith("nextValue=")).first.split("=")[1]);
          var increment = double.parse(definitionParts.where((x) => x.startsWith("increment=")).first.split("=")[1]);
          var value = IncrementingNumberSimulatedMessageDefinition("", nextValue: nextValue, increment: increment).generatePayload();
          return value;

        case "ic":
          var nextValue = int.parse(definitionParts.where((x) => x.startsWith("nextValue=")).first.split("=")[1]);
          var increment = int.parse(definitionParts.where((x) => x.startsWith("increment=")).first.split("=")[1]);
          var prefix = definitionParts.where((x) => x.startsWith("prefix=")).first.split("=")[1];
          var postfix = definitionParts.where((x) => x.startsWith("postfix=")).first.split("=")[1];
          var value =
              IncrementingCodeSimulatedMessageDefinition("", nextValue: nextValue, increment: increment, prefix: prefix, postfix: postfix)
                  .generatePayload();
          return value;

        case "rb":
          var value = RandomBoolSimulatedMessageDefinition("").generatePayload();
          return value;

        case "ds":
          var strings = definitionParts.where((x) => x.startsWith("strings=")).first.split("=")[1].split(",");
          // unescape strings
          strings = strings.map((e) => e.replaceAll("\\,", ",")).toList();
          var prefix = definitionParts.where((x) => x.startsWith("prefix=")).first.split("=")[1];
          var postfix = definitionParts.where((x) => x.startsWith("postfix=")).first.split("=")[1];
          var value = DiscreteStringsSimulatedMessageDefinition("", strings, prefix: prefix, postfix: postfix).generatePayload();
          return value;

        case "dn":
          var escapedNumbers = definitionParts.where((x) => x.startsWith("numbers=")).first.split("=")[1].split(",");
          // unescape numbers
          var numbers = escapedNumbers.map((e) => double.parse(e.replaceAll("\\,", ","))).toList();
          var prefix = definitionParts.where((x) => x.startsWith("prefix=")).first.split("=")[1];
          var postfix = definitionParts.where((x) => x.startsWith("postfix=")).first.split("=")[1];
          var value = DiscreteNumbersSimulatedMessageDefinition("", numbers, prefix: prefix, postfix: postfix).generatePayload();
          return value;

        case "ri":
          var imagesFolderPath = definitionParts.where((x) => x.startsWith("imagesFolderPath=")).first.split("=")[1];
          var value = RandomImageSimulatedMessageDefinition("", imagesFolderPath).generatePayload();
          return value;

        default:
          throw Exception("Invalid definition string");
      }
    });
    return payload;
  }
}
