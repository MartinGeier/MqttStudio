import 'package:json_annotation/json_annotation.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;

// use 'dart run build_runner build' to run the code generator
part 'topic_spec.g.dart';

enum PayloadFormat { unknown, json, number, boolean, string, binary, image, gnss, empty }

enum RetainMode { unknown, never, always, mixed }

enum IntervalKind { unknown, periodic, event, onChange, periodicAndOnChange }

enum Sensitivity { none, personal, confidential, safety }

enum SchemaType { object, array, string, number, integer, boolean, nullValue, mixed }

// What a topic carries and how it is delivered (doc/documentation-design.md §4.2)
@JsonSerializable(explicitToJson: true)
class TopicSpec {
  PayloadSpec payload;
  // the intended QoS, null = not documented
  MqttQos? qos;
  RetainMode retain;
  IntervalSpec interval;
  Mqtt5Spec mqtt5;
  List<String> producers;
  List<String> consumers;
  String accessNotes;
  Sensitivity sensitivity;
  // the topic carries a client's last will
  bool lastWill;

  TopicSpec(
      {PayloadSpec? payload,
      this.qos,
      this.retain = RetainMode.unknown,
      IntervalSpec? interval,
      Mqtt5Spec? mqtt5,
      List<String>? producers,
      List<String>? consumers,
      this.accessNotes = '',
      this.sensitivity = Sensitivity.none,
      this.lastWill = false})
      : payload = payload ?? PayloadSpec(),
        interval = interval ?? IntervalSpec(),
        mqtt5 = mqtt5 ?? Mqtt5Spec(),
        producers = producers ?? [],
        consumers = consumers ?? [];

  factory TopicSpec.fromJson(Map<String, dynamic> json) => _$TopicSpecFromJson(json);
  Map<String, dynamic> toJson() => _$TopicSpecToJson(this);
}

@JsonSerializable(explicitToJson: true)
class PayloadSpec {
  PayloadFormat format;
  // number payloads; JSON fields carry their own unit
  String? unit;
  double? min;
  double? max;
  List<String> allowedValues;
  String? encoding;
  // JSON payloads only
  SchemaNode? schema;
  List<DocExample> examples;

  PayloadSpec(
      {this.format = PayloadFormat.unknown,
      this.unit,
      this.min,
      this.max,
      List<String>? allowedValues,
      this.encoding,
      this.schema,
      List<DocExample>? examples})
      : allowedValues = allowedValues ?? [],
        examples = examples ?? [];

  factory PayloadSpec.fromJson(Map<String, dynamic> json) => _$PayloadSpecFromJson(json);
  Map<String, dynamic> toJson() => _$PayloadSpecToJson(this);
}

// The JSON Schema subset of doc/documentation-design.md §5.4
@JsonSerializable(explicitToJson: true)
class SchemaNode {
  SchemaType type;
  String description;
  // x-unit
  String? unit;
  // date-time, uri, email, uuid
  String? format;
  double? minimum;
  double? maximum;
  List<String> enumValues;
  Map<String, SchemaNode> properties;
  Set<String> required;
  SchemaNode? items;

  SchemaNode(
      {this.type = SchemaType.object,
      this.description = '',
      this.unit,
      this.format,
      this.minimum,
      this.maximum,
      List<String>? enumValues,
      Map<String, SchemaNode>? properties,
      Set<String>? required,
      this.items})
      : enumValues = enumValues ?? [],
        properties = properties ?? {},
        required = required ?? {};

  factory SchemaNode.fromJson(Map<String, dynamic> json) => _$SchemaNodeFromJson(json);
  Map<String, dynamic> toJson() => _$SchemaNodeToJson(this);
}

@JsonSerializable()
class IntervalSpec {
  IntervalKind kind;
  int? nominalMs;
  // a topic without a message for this long is stale
  int? staleAfterMs;

  IntervalSpec({this.kind = IntervalKind.unknown, this.nominalMs, this.staleAfterMs});

  factory IntervalSpec.fromJson(Map<String, dynamic> json) => _$IntervalSpecFromJson(json);
  Map<String, dynamic> toJson() => _$IntervalSpecToJson(this);
}

@JsonSerializable(explicitToJson: true)
class Mqtt5Spec {
  String? contentType;
  // payload format indicator: true = UTF-8, null = not documented
  bool? utf8Payload;
  int? messageExpirySeconds;
  String? responseTopic;
  String? correlationData;
  List<DocUserProperty> userProperties;

  Mqtt5Spec(
      {this.contentType,
      this.utf8Payload,
      this.messageExpirySeconds,
      this.responseTopic,
      this.correlationData,
      List<DocUserProperty>? userProperties})
      : userProperties = userProperties ?? [];

  factory Mqtt5Spec.fromJson(Map<String, dynamic> json) => _$Mqtt5SpecFromJson(json);
  Map<String, dynamic> toJson() => _$Mqtt5SpecToJson(this);
}

@JsonSerializable()
class DocUserProperty {
  String key;
  String description;
  String example;

  DocUserProperty({this.key = '', this.description = '', this.example = ''});

  factory DocUserProperty.fromJson(Map<String, dynamic> json) => _$DocUserPropertyFromJson(json);
  Map<String, dynamic> toJson() => _$DocUserPropertyToJson(this);
}

@JsonSerializable()
class DocExample {
  // the payload as text
  String payload;
  // the concrete topic it was published on, if known
  String? topic;
  DateTime? capturedAt;
  String note;

  DocExample({this.payload = '', this.topic, this.capturedAt, this.note = ''});

  factory DocExample.fromJson(Map<String, dynamic> json) => _$DocExampleFromJson(json);
  Map<String, dynamic> toJson() => _$DocExampleToJson(this);
}
