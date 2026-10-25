import 'package:json_annotation/json_annotation.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';

// use 'dart run build_runner build' to run the code generator
part 'vda5050_source.g.dart';

// The settings of a device that simulates VDA 5050 robots (doc/vda5050-design.md §10.2, simulator D26-D27). The
// device's instanceCount is the number of robots, {n} in the serial number the instance number.
@JsonSerializable()
class Vda5050Source {
  static const String defaultInterfaceV2 = 'uagv';
  static const String defaultInterfaceV3 = 'vda5050';

  VdaVersion version;
  String interfaceName;
  String manufacturer;
  String serialNumber;
  String mapId;

  // the layout: a grid of nodes
  int columns;
  int rows;
  // meters between two neighbouring nodes
  double spacing;
  int chargingStations;

  // m/s
  double speed;
  // % of charge used per hour of driving
  double batteryPerHour;
  // % of charge gained per hour on a charging station
  double chargePerHour;

  // state is sent on every event and at least this often
  int stateHeartbeatSec;
  // 0 = no visualization messages
  int visualizationMs;
  bool factsheet;

  // orders: nodes per order, unreleased nodes after the base, the chance of an action at a node and its duration,
  // the time a robot stands idle before the next order
  int minOrderNodes;
  int maxOrderNodes;
  int horizonNodes;
  double actionProbability;
  int minActionSec;
  int maxActionSec;
  int minIdleSec;
  int maxIdleSec;

  // 3.0 only: a zone set with a blocked, a speed limit and a release zone
  bool zones;
  // 3.0 only: robots request the release zone and the fleet control answers
  bool requests;

  // warnings and fatal errors per robot and hour, cleared again after a while; 0 = off
  double randomFaultsPerHour;
  // null: a new random run on every start
  int? seed;

  Vda5050Source({
    this.version = VdaVersion.v3,
    this.interfaceName = Vda5050Source.defaultInterfaceV3,
    this.manufacturer = 'MQTTStudio',
    this.serialNumber = 'SIM-{n}',
    this.mapId = 'sim-map',
    this.columns = 6,
    this.rows = 4,
    this.spacing = 5,
    this.chargingStations = 1,
    this.speed = 1,
    this.batteryPerHour = 20,
    this.chargePerHour = 120,
    this.stateHeartbeatSec = 30,
    this.visualizationMs = 500,
    this.factsheet = true,
    this.minOrderNodes = 4,
    this.maxOrderNodes = 10,
    this.horizonNodes = 2,
    this.actionProbability = 0.3,
    this.minActionSec = 2,
    this.maxActionSec = 8,
    this.minIdleSec = 0,
    this.maxIdleSec = 10,
    this.zones = true,
    this.requests = true,
    this.randomFaultsPerHour = 0,
    this.seed,
  });

  // the topics of one robot start with this, e.g. vda5050/v3/MQTTStudio/SIM-{n}
  String get topicPrefix => '$interfaceName/${version.topicLevel}/$manufacturer/$serialNumber';

  bool get usesZones => version.isV3 && zones;

  bool get usesRequests => usesZones && requests;

  Vda5050Source copy() => Vda5050Source.fromJson(toJson());

  factory Vda5050Source.fromJson(Map<String, dynamic> json) => _$Vda5050SourceFromJson(json);
  Map<String, dynamic> toJson() => _$Vda5050SourceToJson(this);
}
