import 'package:json_annotation/json_annotation.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';

// use 'dart run build_runner build' to run the code generator
part 'sparkplug_source.g.dart';

// One metric of a simulated edge node or device (doc/sparkplug-design.md §10.3): its value comes from a generator,
// converted to the Sparkplug data type, and is published when it changes by more than the deadband.
@JsonSerializable()
class SparkplugMetricSpec {
  // may contain '/' for folders, e.g. 'Motor/Speed'
  String name;
  SpbDataType type;
  @JsonKey(fromJson: PayloadGenerator.fromJson, toJson: PayloadGenerator.toJsonStatic)
  PayloadGenerator generator;
  // sent as the engUnit property
  String? unit;
  // numbers: a change up to this much isn't published
  double deadband;
  // accepts NCMD or DCMD writes; a written value holds until the next write (Q4)
  bool writable;

  SparkplugMetricSpec({
    required this.name,
    required this.type,
    required this.generator,
    this.unit,
    this.deadband = 0,
    this.writable = false,
  });

  factory SparkplugMetricSpec.fromJson(Map<String, dynamic> json) => _$SparkplugMetricSpecFromJson(json);
  Map<String, dynamic> toJson() => _$SparkplugMetricSpecToJson(this);
}

// The devices of every edge node; {d} in the id is the device number, from 1 to count
@JsonSerializable(explicitToJson: true)
class SparkplugDeviceSpec {
  String id;
  int count;
  List<SparkplugMetricSpec> metrics;

  SparkplugDeviceSpec({this.id = 'Device{d}', this.count = 1, List<SparkplugMetricSpec>? metrics})
    : metrics = metrics ?? [];

  factory SparkplugDeviceSpec.fromJson(Map<String, dynamic> json) => _$SparkplugDeviceSpecFromJson(json);
  Map<String, dynamic> toJson() => _$SparkplugDeviceSpecToJson(this);
}

// The settings of a device that simulates Sparkplug B 3.0 edge nodes (doc/sparkplug-design.md §10). The device's
// instanceCount is the number of edge nodes, {n} in the edge node id the instance number.
@JsonSerializable(explicitToJson: true)
class SparkplugSource {
  String groupId;
  String edgeNodeId;
  // besides bdSeq and Node Control/Rebirth, which every edge node has
  List<SparkplugMetricSpec> nodeMetrics;
  List<SparkplugDeviceSpec> devices;
  // the generators are sampled this often, changed metrics are published
  int scanMs;
  // data and commands by alias instead of name
  bool aliases;
  // the edge nodes wait for this host application's STATE before their birth
  String? primaryHostId;
  // publish the primary host's STATE ourselves, so no host application is needed
  bool simulateHost;
  // payloads as SPBV1.0_COMPRESSED with GZIP
  bool compress;
  // null: a new random run on every start
  int? seed;

  SparkplugSource({
    this.groupId = 'Plant1',
    this.edgeNodeId = 'Edge{n}',
    List<SparkplugMetricSpec>? nodeMetrics,
    List<SparkplugDeviceSpec>? devices,
    this.scanMs = 1000,
    this.aliases = true,
    this.primaryHostId,
    this.simulateHost = true,
    this.compress = false,
    this.seed,
  }) : nodeMetrics = nodeMetrics ?? [],
       devices = devices ?? [];

  // the "Example edge node" a new device starts from (§10.3)
  factory SparkplugSource.example() => SparkplugSource(
    nodeMetrics: [
      SparkplugMetricSpec(
        name: 'Uptime',
        type: SpbDataType.uInt64,
        generator: const CounterGenerator(start: 0, step: 1),
        unit: 's',
      ),
      SparkplugMetricSpec(
        name: 'Firmware',
        type: SpbDataType.string,
        generator: const ValueListGenerator(values: ['3.2.1']),
      ),
    ],
    devices: [
      SparkplugDeviceSpec(
        id: 'Pump',
        metrics: [
          SparkplugMetricSpec(
            name: 'Temperature',
            type: SpbDataType.double,
            generator: const WaveGenerator(offset: 60, amplitude: 15, periodSeconds: 120, decimals: 1),
            unit: '°C',
            deadband: 0.2,
          ),
          SparkplugMetricSpec(
            name: 'Pressure',
            type: SpbDataType.float,
            generator: const RandomWalkGenerator(start: 2.5, min: 1, max: 4, volatility: 0.05, decimals: 2),
            unit: 'bar',
            deadband: 0.05,
          ),
          SparkplugMetricSpec(
            name: 'Running',
            type: SpbDataType.boolean,
            generator: const BoolGenerator(trueProbability: 0.98),
            writable: true,
          ),
          SparkplugMetricSpec(
            name: 'Speed',
            type: SpbDataType.int32,
            generator: const RandomWalkGenerator(start: 1450, min: 1200, max: 1800, volatility: 10),
            unit: 'rpm',
            deadband: 5,
            writable: true,
          ),
          SparkplugMetricSpec(
            name: 'Mode',
            type: SpbDataType.string,
            generator: const ValueListGenerator(values: ['AUTO', 'AUTO', 'AUTO', 'AUTO', 'MANUAL']),
          ),
        ],
      ),
    ],
  );

  SparkplugSource copy() => SparkplugSource.fromJson(toJson());

  factory SparkplugSource.fromJson(Map<String, dynamic> json) => _$SparkplugSourceFromJson(json);
  Map<String, dynamic> toJson() => _$SparkplugSourceToJson(this);
}
