import 'package:json_annotation/json_annotation.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/vda5050_source.dart';
import 'package:uuid/uuid.dart';

// use 'dart run build_runner build' to run the code generator
part 'simulation.g.dart';

const _uuid = Uuid();

// The simulation of a project: devices, each with topics that publish generated payloads.
@JsonSerializable(explicitToJson: true)
class Simulation {
  static const int currentSchemaVersion = 1;

  int schemaVersion;
  List<SimulatedDevice> devices;

  Simulation({this.schemaVersion = Simulation.currentSchemaVersion, List<SimulatedDevice>? devices}) : devices = devices ?? [];

  // a new simulation starts with one device, every topic belongs to a device
  factory Simulation.withDefaultDevice() => Simulation(devices: [SimulatedDevice(name: SimulatedDevice.defaultName)]);

  // projects saved before the simulator existed have no simulation
  static Simulation fromJsonOrEmpty(Map<String, dynamic>? json) =>
      json == null ? Simulation.withDefaultDevice() : Simulation.fromJson(json);

  SimulatedDevice? deviceById(String id) {
    for (var device in devices) {
      if (device.id == id) {
        return device;
      }
    }
    return null;
  }

  SimulatedDevice? deviceOfTopic(String topicId) {
    for (var device in devices) {
      if (device.topics.any((topic) => topic.id == topicId)) {
        return device;
      }
    }
    return null;
  }

  Iterable<SimulatedTopic> get allTopics => devices.expand((device) => device.topics);

  factory Simulation.fromJson(Map<String, dynamic> json) => _$SimulationFromJson(json);
  Map<String, dynamic> toJson() => _$SimulationToJson(this);
}

@JsonSerializable(explicitToJson: true)
class SimulatedDevice {
  static const String defaultName = 'Default';

  String id;
  String name;
  int instanceCount;
  // value of {n} for the first instance
  int firstInstance;
  // devices saved before recorded devices existed are generated ones
  @JsonKey(defaultValue: DeviceKind.generated)
  DeviceKind kind;
  // the recording a recorded device plays; its topics list stays empty
  RecordedSource? recorded;
  // the settings of a VDA 5050 device; its topics list stays empty (D26)
  Vda5050Source? vda5050;
  List<SimulatedTopic> topics;

  SimulatedDevice(
      {String? id,
      required this.name,
      this.instanceCount = 1,
      this.firstInstance = 1,
      this.kind = DeviceKind.generated,
      this.recorded,
      this.vda5050,
      List<SimulatedTopic>? topics})
      : id = id ?? _uuid.v4(),
        topics = topics ?? [];

  bool get isRecorded => kind == DeviceKind.recorded;

  bool get isVda5050 => kind == DeviceKind.vda5050;

  // a device with topics of its own
  bool get isGenerated => kind == DeviceKind.generated;

  int get lastInstance => firstInstance + instanceCount - 1;

  Iterable<int> get instanceNumbers => Iterable.generate(instanceCount, (index) => firstInstance + index);

  SimulatedDevice copy({bool newIds = false}) => SimulatedDevice(
        id: newIds ? null : id,
        name: name,
        instanceCount: instanceCount,
        firstInstance: firstInstance,
        kind: kind,
        recorded: recorded == null ? null : RecordedSource.fromJson(recorded!.toJson()),
        vda5050: vda5050?.copy(),
        topics: topics.map((topic) => topic.copy(newId: newIds)).toList(),
      );

  factory SimulatedDevice.fromJson(Map<String, dynamic> json) => _$SimulatedDeviceFromJson(json);
  Map<String, dynamic> toJson() => _$SimulatedDeviceToJson(this);
}

// generated devices publish payloads of generators, recorded ones play a recording (doc/simulator-design.md D22),
// VDA 5050 devices simulate robots and their fleet control (D26)
enum DeviceKind { generated, recorded, vda5050 }

// When the instances of a recorded device start (D24)
enum InstanceStart {
  // each one after a random part of the median interval, like the start of generated topics
  staggered,
  // all at the same time
  aligned,
  // each one at a random position in the range; needs loop
  randomPosition,
}

// The recording a recorded device plays and how (doc/simulator-design.md §4.5)
@JsonSerializable(explicitToJson: true)
class RecordedSource {
  // RecordingHeader.id in the recordings library (D23)
  String recordingId;
  // found by this when the id is not, e.g. after a copy
  String fileName;
  // the recording's name when it was chosen, shown when it is missing
  String recordingName;
  // remap targets may contain {n}, {n:3} and {device}; Max speed is not allowed (D25)
  PlaybackOptions playback;
  InstanceStart instanceStart;

  RecordedSource(
      {required this.recordingId,
      required this.fileName,
      required this.recordingName,
      PlaybackOptions? playback,
      this.instanceStart = InstanceStart.staggered})
      : playback = playback ?? PlaybackOptions();

  factory RecordedSource.fromJson(Map<String, dynamic> json) => _$RecordedSourceFromJson(json);
  Map<String, dynamic> toJson() => _$RecordedSourceToJson(this);
}

@JsonSerializable(explicitToJson: true)
class SimulatedTopic {
  String id;
  // may contain the placeholders {n}, {n:3} and {device}
  String topic;
  MqttQos qos;
  bool retain;
  PublishInterval interval;
  Mqtt5PublishProperties mqtt5;
  @JsonKey(fromJson: PayloadGenerator.fromJson, toJson: PayloadGenerator.toJsonStatic)
  PayloadGenerator generator;

  SimulatedTopic(
      {String? id,
      required this.topic,
      required this.generator,
      this.qos = MqttQos.atMostOnce,
      this.retain = false,
      PublishInterval? interval,
      Mqtt5PublishProperties? mqtt5})
      : id = id ?? _uuid.v4(),
        interval = interval ?? PublishInterval(),
        mqtt5 = mqtt5 ?? Mqtt5PublishProperties();

  SimulatedTopic copy({bool newId = false}) => SimulatedTopic.fromJson(toJson())..id = newId ? _uuid.v4() : id;

  factory SimulatedTopic.fromJson(Map<String, dynamic> json) => _$SimulatedTopicFromJson(json);
  Map<String, dynamic> toJson() => _$SimulatedTopicToJson(this);
}

@JsonSerializable()
class PublishInterval {
  int minMs;
  // equal to minMs for a fixed interval
  int maxMs;

  PublishInterval({this.minMs = 1000, int? maxMs}) : maxMs = maxMs ?? minMs;

  bool get isRandom => maxMs > minMs;

  double get averageMs => (minMs + maxMs) / 2;

  factory PublishInterval.fromJson(Map<String, dynamic> json) => _$PublishIntervalFromJson(json);
  Map<String, dynamic> toJson() => _$PublishIntervalToJson(this);
}

@JsonSerializable()
class SimulatedUserProperty {
  String key;
  // may contain placeholders
  String value;

  SimulatedUserProperty(this.key, this.value);

  factory SimulatedUserProperty.fromJson(Map<String, dynamic> json) => _$SimulatedUserPropertyFromJson(json);
  Map<String, dynamic> toJson() => _$SimulatedUserPropertyToJson(this);
}

// MQTT 5 properties sent with every message of a simulated topic, ignored for MQTT 3.1.1 projects
@JsonSerializable(explicitToJson: true)
class Mqtt5PublishProperties {
  // null: chosen from the generator (application/json for JSON templates, the image type for images)
  String? contentType;
  int? messageExpirySeconds;
  List<SimulatedUserProperty> userProperties;

  Mqtt5PublishProperties({this.contentType, this.messageExpirySeconds, List<SimulatedUserProperty>? userProperties})
      : userProperties = userProperties ?? [];

  bool get isEmpty =>
      (contentType == null || contentType!.isEmpty) && messageExpirySeconds == null && userProperties.isEmpty;

  factory Mqtt5PublishProperties.fromJson(Map<String, dynamic> json) => _$Mqtt5PublishPropertiesFromJson(json);
  Map<String, dynamic> toJson() => _$Mqtt5PublishPropertiesToJson(this);
}
