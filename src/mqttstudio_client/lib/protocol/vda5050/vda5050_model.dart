// The version-neutral model of VDA 5050 messages (doc/vda5050-design.md §6.6, V15). Names follow VDA 5050 3.0;
// Vda5050Reader and Vda5050Writer map them to the 2.x names. Enum values are strings with the 3.0 spelling, because
// 3.0 enums are extensible and a reader must keep values it doesn't know.

enum VdaVersion {
  v2('2.1.0', 'v2', 2),
  v3('3.0.0', 'v3', 3);

  // the version written into the header
  final String protocolVersion;
  // the version level of the topic
  final String topicLevel;
  final int major;

  const VdaVersion(this.protocolVersion, this.topicLevel, this.major);

  bool get isV3 => this == VdaVersion.v3;

  // 1.x and 2.x are read as 2.x, 3.x and anything newer as 3.0
  static VdaVersion ofMajor(int major) => major >= 3 ? VdaVersion.v3 : VdaVersion.v2;

  // '2.0.0' -> v2; null when the text doesn't start with a number
  static VdaVersion? parse(String? version) {
    var major = int.tryParse((version ?? '').split('.').first.trim().replaceFirst(RegExp(r'^v'), ''));
    return major == null ? null : ofMajor(major);
  }
}

// The topics of VDA 5050, the last level of a VDA 5050 topic
class VdaTopic {
  static const String order = 'order';
  static const String instantActions = 'instantActions';
  static const String state = 'state';
  static const String visualization = 'visualization';
  static const String connection = 'connection';
  static const String factsheet = 'factsheet';
  static const String zoneSet = 'zoneSet';
  static const String responses = 'responses';

  static const List<String> all = [order, instantActions, state, visualization, connection, factsheet, zoneSet, responses];

  // the topics that exist only in 3.0
  static bool isV3Only(String topic) => topic == zoneSet || topic == responses;
}

// Field names that differ between 2.x and 3.0 beyond what the reader and writer handle field by field
class Vda5050Names {
  // factsheet sections, 3.0 name -> 2.x name
  static const Map<String, String> factsheetSections2 = {
    'mobileRobotGeometry': 'agvGeometry',
    'mobileRobotConfiguration': 'vehicleConfig',
  };
}

class VdaConnectionState {
  static const String online = 'ONLINE';
  static const String offline = 'OFFLINE';
  static const String hibernating = 'HIBERNATING';
  static const String connectionBroken = 'CONNECTION_BROKEN';
}

class VdaOperatingMode {
  static const String startup = 'STARTUP';
  static const String automatic = 'AUTOMATIC';
  static const String semiautomatic = 'SEMIAUTOMATIC';
  static const String intervened = 'INTERVENED';
  static const String manual = 'MANUAL';
  static const String service = 'SERVICE';
  static const String teachIn = 'TEACH_IN';
}

class VdaErrorLevel {
  static const String warning = 'WARNING';
  static const String urgent = 'URGENT';
  static const String critical = 'CRITICAL';
  static const String fatal = 'FATAL';
}

class VdaActionStatus {
  static const String waiting = 'WAITING';
  static const String initializing = 'INITIALIZING';
  static const String running = 'RUNNING';
  static const String paused = 'PAUSED';
  static const String retriable = 'RETRIABLE';
  static const String finished = 'FINISHED';
  static const String failed = 'FAILED';
}

class VdaBlockingType {
  static const String none = 'NONE';
  static const String single = 'SINGLE';
  static const String soft = 'SOFT';
  static const String hard = 'HARD';
}

class VdaEmergencyStop {
  static const String manual = 'MANUAL';
  static const String remote = 'REMOTE';
  static const String none = 'NONE';
}

class VdaGrantType {
  static const String granted = 'GRANTED';
  static const String queued = 'QUEUED';
  static const String revoked = 'REVOKED';
  static const String rejected = 'REJECTED';
}

class VdaRequestStatus {
  static const String requested = 'REQUESTED';
  static const String granted = 'GRANTED';
  static const String revoked = 'REVOKED';
  static const String expired = 'EXPIRED';
}

class VdaZoneType {
  static const String blocked = 'BLOCKED';
  static const String release = 'RELEASE';
  static const String speedLimit = 'SPEED_LIMIT';
}

class VdaHeader {
  int headerId;
  DateTime timestamp;
  // as sent, e.g. '2.0.0'
  String version;
  String manufacturer;
  String serialNumber;

  VdaHeader(
      {this.headerId = 0, DateTime? timestamp, this.version = '', this.manufacturer = '', this.serialNumber = ''})
      : timestamp = timestamp ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

// A message of any VDA 5050 topic. extra keeps the top-level fields the reader doesn't know, so they are shown and
// written back unchanged.
abstract class VdaMessage {
  VdaHeader header;
  Map<String, Object?> extra;

  VdaMessage({VdaHeader? header, Map<String, Object?>? extra})
      : header = header ?? VdaHeader(),
        extra = extra ?? {};

  // the last level of the topic the message is sent on
  String get topic;
}

class VdaPoint {
  double x;
  double y;

  VdaPoint(this.x, this.y);
}

class VdaActionParameter {
  String key;
  // any JSON value
  Object? value;

  VdaActionParameter(this.key, this.value);
}

class VdaAction {
  String actionId;
  String actionType;
  String blockingType;
  String? descriptor;
  List<VdaActionParameter> parameters;
  // 3.0
  bool? retriable;

  VdaAction(
      {required this.actionId,
      required this.actionType,
      this.blockingType = VdaBlockingType.none,
      this.descriptor,
      List<VdaActionParameter>? parameters,
      this.retriable})
      : parameters = parameters ?? [];
}

class VdaNodePosition {
  double x;
  double y;
  double? theta;
  String mapId;

  VdaNodePosition({required this.x, required this.y, this.theta, required this.mapId});
}

class VdaNode {
  String nodeId;
  int sequenceId;
  bool released;
  String? descriptor;
  VdaNodePosition? position;
  List<VdaAction> actions;

  VdaNode(
      {required this.nodeId,
      required this.sequenceId,
      required this.released,
      this.descriptor,
      this.position,
      List<VdaAction>? actions})
      : actions = actions ?? [];
}

class VdaEdge {
  String edgeId;
  int sequenceId;
  bool released;
  String? descriptor;
  // 2.x only; 3.0 connects edges and nodes by their sequence ids
  String? startNodeId;
  String? endNodeId;
  double? maximumSpeed;
  List<VdaAction> actions;

  VdaEdge(
      {required this.edgeId,
      required this.sequenceId,
      required this.released,
      this.descriptor,
      this.startNodeId,
      this.endNodeId,
      this.maximumSpeed,
      List<VdaAction>? actions})
      : actions = actions ?? [];
}

class VdaOrder extends VdaMessage {
  String orderId;
  int orderUpdateId;
  List<VdaNode> nodes;
  List<VdaEdge> edges;

  VdaOrder(
      {super.header,
      super.extra,
      required this.orderId,
      this.orderUpdateId = 0,
      List<VdaNode>? nodes,
      List<VdaEdge>? edges})
      : nodes = nodes ?? [],
        edges = edges ?? [];

  @override
  String get topic => VdaTopic.order;
}

class VdaInstantActions extends VdaMessage {
  List<VdaAction> actions;

  VdaInstantActions({super.header, super.extra, List<VdaAction>? actions}) : actions = actions ?? [];

  @override
  String get topic => VdaTopic.instantActions;
}

class VdaNodeState {
  String nodeId;
  int sequenceId;
  bool released;
  String? descriptor;
  VdaNodePosition? position;

  VdaNodeState({required this.nodeId, required this.sequenceId, required this.released, this.descriptor, this.position});
}

class VdaEdgeState {
  String edgeId;
  int sequenceId;
  bool released;
  String? descriptor;

  VdaEdgeState({required this.edgeId, required this.sequenceId, required this.released, this.descriptor});
}

class VdaPosition {
  double x;
  double y;
  double theta;
  String mapId;
  // positionInitialized in 2.x
  bool localized;
  double? localizationScore;
  double? deviationRange;

  VdaPosition(
      {required this.x,
      required this.y,
      required this.theta,
      required this.mapId,
      this.localized = true,
      this.localizationScore,
      this.deviationRange});
}

class VdaVelocity {
  double? vx;
  double? vy;
  double? omega;

  VdaVelocity({this.vx, this.vy, this.omega});
}

// batteryState in 2.x
class VdaPowerSupply {
  // batteryCharge in 2.x
  double stateOfCharge;
  bool charging;
  double? batteryVoltage;
  // 3.0
  double? batteryCurrent;
  double? batteryHealth;
  // reach in 2.x
  double? range;

  VdaPowerSupply(
      {required this.stateOfCharge,
      this.charging = false,
      this.batteryVoltage,
      this.batteryCurrent,
      this.batteryHealth,
      this.range});
}

class VdaActionState {
  String actionId;
  String? actionType;
  String status;
  String? descriptor;
  // resultDescription in 2.x
  String? result;

  VdaActionState({required this.actionId, this.actionType, required this.status, this.descriptor, this.result});
}

class VdaReference {
  String key;
  String value;

  VdaReference(this.key, this.value);
}

class VdaError {
  String errorType;
  String errorLevel;
  String? description;
  String? hint;
  List<VdaReference> references;

  VdaError(
      {required this.errorType, required this.errorLevel, this.description, this.hint, List<VdaReference>? references})
      : references = references ?? [];
}

class VdaInfo {
  String infoType;
  String infoLevel;
  String? descriptor;
  List<VdaReference> references;

  VdaInfo({required this.infoType, required this.infoLevel, this.descriptor, List<VdaReference>? references})
      : references = references ?? [];
}

class VdaSafetyState {
  // eStop in 2.x
  String activeEmergencyStop;
  bool fieldViolation;

  VdaSafetyState({this.activeEmergencyStop = VdaEmergencyStop.none, this.fieldViolation = false});
}

class VdaMapInfo {
  String mapId;
  String mapVersion;
  String status;

  VdaMapInfo({required this.mapId, required this.mapVersion, this.status = 'ENABLED'});
}

// 3.0: a zone set the robot has, in its state
class VdaZoneSetInfo {
  String zoneSetId;
  String mapId;
  String status;

  VdaZoneSetInfo({required this.zoneSetId, required this.mapId, this.status = 'ENABLED'});
}

// 3.0
class VdaZoneRequest {
  String requestId;
  String requestType;
  String zoneId;
  String zoneSetId;
  String requestStatus;

  VdaZoneRequest(
      {required this.requestId,
      this.requestType = 'ACCESS',
      required this.zoneId,
      required this.zoneSetId,
      this.requestStatus = VdaRequestStatus.requested});
}

// 3.0
class VdaEdgeRequest {
  String requestId;
  String requestType;
  String edgeId;
  int sequenceId;
  String requestStatus;

  VdaEdgeRequest(
      {required this.requestId,
      this.requestType = 'CORRIDOR',
      required this.edgeId,
      required this.sequenceId,
      this.requestStatus = VdaRequestStatus.requested});
}

// 3.0: the path a robot plans to drive, as the control points of a degree 1 trajectory
class VdaPlannedPath {
  List<VdaPoint> controlPoints;
  List<String> traversedNodes;

  VdaPlannedPath({List<VdaPoint>? controlPoints, List<String>? traversedNodes})
      : controlPoints = controlPoints ?? [],
        traversedNodes = traversedNodes ?? [];
}

class VdaPathPoint {
  double x;
  double y;
  double? theta;
  DateTime eta;

  VdaPathPoint({required this.x, required this.y, this.theta, required this.eta});
}

// 3.0: the next meters a robot drives
class VdaIntermediatePath {
  List<VdaPathPoint> polyline;

  VdaIntermediatePath({List<VdaPathPoint>? polyline}) : polyline = polyline ?? [];
}

class VdaState extends VdaMessage {
  String orderId;
  int orderUpdateId;
  String lastNodeId;
  int lastNodeSequenceId;
  List<VdaNodeState> nodeStates;
  List<VdaEdgeState> edgeStates;
  VdaPosition? position;
  VdaVelocity? velocity;
  // load objects as sent
  List<Map<String, Object?>> loads;
  bool driving;
  bool? paused;
  bool? newBaseRequest;
  double? distanceSinceLastNode;
  List<VdaActionState> actionStates;
  VdaPowerSupply powerSupply;
  String operatingMode;
  List<VdaError> errors;
  List<VdaInfo> information;
  VdaSafetyState safetyState;
  List<VdaMapInfo> maps;
  // 3.0
  List<VdaActionState> instantActionStates;
  List<VdaActionState> zoneActionStates;
  List<VdaZoneSetInfo> zoneSets;
  List<VdaZoneRequest> zoneRequests;
  List<VdaEdgeRequest> edgeRequests;
  VdaPlannedPath? plannedPath;
  VdaIntermediatePath? intermediatePath;
  // 2.x
  String? zoneSetId;

  VdaState({
    super.header,
    super.extra,
    this.orderId = '',
    this.orderUpdateId = 0,
    this.lastNodeId = '',
    this.lastNodeSequenceId = 0,
    List<VdaNodeState>? nodeStates,
    List<VdaEdgeState>? edgeStates,
    this.position,
    this.velocity,
    List<Map<String, Object?>>? loads,
    this.driving = false,
    this.paused,
    this.newBaseRequest,
    this.distanceSinceLastNode,
    List<VdaActionState>? actionStates,
    VdaPowerSupply? powerSupply,
    this.operatingMode = VdaOperatingMode.automatic,
    List<VdaError>? errors,
    List<VdaInfo>? information,
    VdaSafetyState? safetyState,
    List<VdaMapInfo>? maps,
    List<VdaActionState>? instantActionStates,
    List<VdaActionState>? zoneActionStates,
    List<VdaZoneSetInfo>? zoneSets,
    List<VdaZoneRequest>? zoneRequests,
    List<VdaEdgeRequest>? edgeRequests,
    this.plannedPath,
    this.intermediatePath,
    this.zoneSetId,
  })  : nodeStates = nodeStates ?? [],
        edgeStates = edgeStates ?? [],
        loads = loads ?? [],
        actionStates = actionStates ?? [],
        powerSupply = powerSupply ?? VdaPowerSupply(stateOfCharge: 0),
        errors = errors ?? [],
        information = information ?? [],
        safetyState = safetyState ?? VdaSafetyState(),
        maps = maps ?? [],
        instantActionStates = instantActionStates ?? [],
        zoneActionStates = zoneActionStates ?? [],
        zoneSets = zoneSets ?? [],
        zoneRequests = zoneRequests ?? [],
        edgeRequests = edgeRequests ?? [];

  @override
  String get topic => VdaTopic.state;
}

class VdaVisualization extends VdaMessage {
  VdaPosition? position;
  VdaVelocity? velocity;
  // 3.0
  int? referenceStateHeaderId;
  VdaPlannedPath? plannedPath;
  VdaIntermediatePath? intermediatePath;

  VdaVisualization(
      {super.header,
      super.extra,
      this.position,
      this.velocity,
      this.referenceStateHeaderId,
      this.plannedPath,
      this.intermediatePath});

  @override
  String get topic => VdaTopic.visualization;
}

class VdaConnection extends VdaMessage {
  String connectionState;

  VdaConnection({super.header, super.extra, this.connectionState = VdaConnectionState.online});

  @override
  String get topic => VdaTopic.connection;
}

class VdaFactsheetAction {
  String actionType;
  // INSTANT, NODE, EDGE and in 3.0 ZONE
  List<String> scopes;
  // 3.0
  bool pauseAllowed;
  bool cancelAllowed;

  VdaFactsheetAction(this.actionType, this.scopes, {this.pauseAllowed = false, this.cancelAllowed = false});
}

// The parts of a factsheet MQTT Studio uses; the other sections are kept in extra. Kinematics, class and navigation
// types use the 3.0 values (DIFFERENTIAL, FREELY_NAVIGATING).
class VdaFactsheet extends VdaMessage {
  String seriesName;
  String? seriesDescription;
  String kinematics;
  String robotClass;
  double maximumLoadMass;
  List<String> localizationTypes;
  List<String> navigationTypes;
  double minimumSpeed;
  double maximumSpeed;
  double maximumAcceleration;
  double maximumDeceleration;
  double minimumHeight;
  double maximumHeight;
  double width;
  double length;
  double minimumOrderInterval;
  double minimumStateInterval;
  List<VdaFactsheetAction> actions;

  VdaFactsheet({
    super.header,
    super.extra,
    this.seriesName = '',
    this.seriesDescription,
    this.kinematics = 'DIFFERENTIAL',
    this.robotClass = 'CARRIER',
    this.maximumLoadMass = 0,
    List<String>? localizationTypes,
    List<String>? navigationTypes,
    this.minimumSpeed = 0,
    this.maximumSpeed = 0,
    this.maximumAcceleration = 0,
    this.maximumDeceleration = 0,
    this.minimumHeight = 0,
    this.maximumHeight = 0,
    this.width = 0,
    this.length = 0,
    this.minimumOrderInterval = 0,
    this.minimumStateInterval = 0,
    List<VdaFactsheetAction>? actions,
  })  : localizationTypes = localizationTypes ?? [],
        navigationTypes = navigationTypes ?? [],
        actions = actions ?? [];

  @override
  String get topic => VdaTopic.factsheet;
}

class VdaZone {
  String zoneId;
  String zoneType;
  String? descriptor;
  List<VdaPoint> vertices;
  // the parameters of the zone type, e.g. maximumSpeed or releaseLossBehavior, as sent
  Map<String, Object?> parameters;

  VdaZone(
      {required this.zoneId,
      required this.zoneType,
      this.descriptor,
      List<VdaPoint>? vertices,
      Map<String, Object?>? parameters})
      : vertices = vertices ?? [],
        parameters = parameters ?? {};

  // even-odd test, the vertices form a closed polygon
  bool contains(double x, double y) {
    var inside = false;
    for (var i = 0, j = vertices.length - 1; i < vertices.length; j = i++) {
      var a = vertices[i];
      var b = vertices[j];
      if ((a.y > y) != (b.y > y) && x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x) {
        inside = !inside;
      }
    }
    return inside;
  }
}

// 3.0
class VdaZoneSet {
  String zoneSetId;
  String mapId;
  String? descriptor;
  List<VdaZone> zones;

  VdaZoneSet({required this.zoneSetId, required this.mapId, this.descriptor, List<VdaZone>? zones})
      : zones = zones ?? [];
}

// 3.0
class VdaZoneSetMessage extends VdaMessage {
  VdaZoneSet zoneSet;

  VdaZoneSetMessage({super.header, super.extra, required this.zoneSet});

  @override
  String get topic => VdaTopic.zoneSet;
}

// 3.0
class VdaResponse {
  String requestId;
  String grantType;
  DateTime? leaseExpiry;

  VdaResponse({required this.requestId, required this.grantType, this.leaseExpiry});
}

// 3.0
class VdaResponses extends VdaMessage {
  List<VdaResponse> responses;

  VdaResponses({super.header, super.extra, List<VdaResponse>? responses}) : responses = responses ?? [];

  @override
  String get topic => VdaTopic.responses;
}
