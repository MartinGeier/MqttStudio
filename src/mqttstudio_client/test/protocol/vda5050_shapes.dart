import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';

// The required fields and enums of the official VDA 5050 2.1.0 and 3.0.0 JSON schemas
// (github.com/VDA5050/VDA5050, json_schemas/), as far as MQTT Studio writes them. shapeErrors lists what a message
// breaks; an empty list means it has the shape of its schema.

const _header = ['headerId', 'timestamp', 'version', 'manufacturer', 'serialNumber'];

class _Checker {
  final List<String> errors = [];

  void required(Map json, List<String> keys, String where) {
    for (var key in keys) {
      if (!json.containsKey(key)) {
        errors.add('$where: missing $key');
      }
    }
  }

  void absent(Map json, List<String> keys, String where) {
    for (var key in keys) {
      if (json.containsKey(key)) {
        errors.add('$where: $key does not exist in this version');
      }
    }
  }

  void oneOf(Object? value, List<String> allowed, String where) {
    if (value != null && !allowed.contains(value)) {
      errors.add('$where: $value is not one of $allowed');
    }
  }

  void type<T>(Object? value, String where) {
    if (value != null && value is! T) {
      errors.add('$where: $value is not a $T');
    }
  }

  Map map(Map json, String key, String where) {
    var value = json[key];
    if (value is Map) {
      return value;
    }
    if (value != null) {
      errors.add('$where: $key is not an object');
    }
    return {};
  }

  List<Map> maps(Map json, String key, String where) {
    var value = json[key];
    if (value == null) {
      return [];
    }
    if (value is! List) {
      errors.add('$where: $key is not an array');
      return [];
    }
    return value.whereType<Map>().toList();
  }
}

List<String> shapeErrors(String topic, VdaVersion version, Map<String, Object?> json) {
  var c = _Checker();
  var v3 = version.isV3;
  if (topic != VdaTopic.visualization || v3) {
    c.required(json, v3 || topic != VdaTopic.factsheet ? _header : ['version', 'manufacturer', 'serialNumber'], topic);
  }
  c.type<int>(json['headerId'], '$topic.headerId');
  var timestamp = json['timestamp'];
  if (timestamp != null && (timestamp is! String || DateTime.tryParse(timestamp) == null || !timestamp.endsWith('Z'))) {
    c.errors.add('$topic.timestamp: $timestamp is not an ISO 8601 UTC time');
  }
  switch (topic) {
    case VdaTopic.state:
      _state(c, json, v3);
    case VdaTopic.order:
      _order(c, json, v3);
    case VdaTopic.instantActions:
      c.required(json, ['actions'], topic);
      for (var action in c.maps(json, 'actions', topic)) {
        _action(c, action, v3, 'instantActions.actions');
      }
    case VdaTopic.visualization:
      if (v3) {
        c.required(json, ['referenceStateHeaderId'], topic);
      } else {
        c.absent(json, ['referenceStateHeaderId', 'mobileRobotPosition', 'plannedPath', 'intermediatePath'], topic);
      }
      _position(c, json, v3, topic);
    case VdaTopic.connection:
      c.required(json, ['connectionState'], topic);
      c.oneOf(json['connectionState'],
          v3 ? ['ONLINE', 'OFFLINE', 'HIBERNATING', 'CONNECTION_BROKEN'] : ['ONLINE', 'OFFLINE', 'CONNECTIONBROKEN'], topic);
    case VdaTopic.factsheet:
      _factsheet(c, json, v3);
    case VdaTopic.zoneSet:
      _zoneSet(c, json);
    case VdaTopic.responses:
      c.required(json, ['responses'], topic);
      for (var response in c.maps(json, 'responses', topic)) {
        c.required(response, ['requestId', 'grantType'], 'responses.responses');
        c.oneOf(response['grantType'], ['GRANTED', 'QUEUED', 'REVOKED', 'REJECTED'], 'responses.grantType');
      }
  }
  return c.errors;
}

void _position(_Checker c, Map json, bool v3, String where) {
  var key = v3 ? 'mobileRobotPosition' : 'agvPosition';
  if (json.containsKey(key)) {
    var position = c.map(json, key, where);
    c.required(position, ['x', 'y', 'theta', 'mapId', v3 ? 'localized' : 'positionInitialized'], '$where.$key');
    var theta = position['theta'];
    if (theta is num && theta.abs() > 3.14159265359) {
      c.errors.add('$where.$key.theta: $theta is out of range');
    }
  }
  c.absent(json, [v3 ? 'agvPosition' : 'mobileRobotPosition'], where);
}

void _state(_Checker c, Map json, bool v3) {
  const where = 'state';
  c.required(json, [
    'orderId', 'orderUpdateId', 'lastNodeId', 'lastNodeSequenceId', 'nodeStates', 'edgeStates', 'driving',
    'actionStates', 'operatingMode', 'errors', 'safetyState', v3 ? 'powerSupply' : 'batteryState',
    if (v3) 'instantActionStates',
  ], where);
  if (v3) {
    c.absent(json, ['batteryState', 'zoneSetId'], where);
  } else {
    c.absent(json, ['powerSupply', 'instantActionStates', 'zoneActionStates', 'zoneSets', 'zoneRequests', 'edgeRequests',
      'plannedPath', 'intermediatePath'], where);
  }
  c.oneOf(
      json['operatingMode'],
      v3
          ? ['STARTUP', 'AUTOMATIC', 'SEMIAUTOMATIC', 'INTERVENED', 'MANUAL', 'SERVICE', 'TEACH_IN']
          : ['AUTOMATIC', 'SEMIAUTOMATIC', 'MANUAL', 'SERVICE', 'TEACHIN'],
      '$where.operatingMode');
  _position(c, json, v3, where);
  for (var node in c.maps(json, 'nodeStates', where)) {
    c.required(node, ['nodeId', 'sequenceId', 'released'], '$where.nodeStates');
  }
  for (var edge in c.maps(json, 'edgeStates', where)) {
    c.required(edge, ['edgeId', 'sequenceId', 'released'], '$where.edgeStates');
  }
  var statuses = v3
      ? ['WAITING', 'INITIALIZING', 'RUNNING', 'PAUSED', 'RETRIABLE', 'FINISHED', 'FAILED']
      : ['WAITING', 'INITIALIZING', 'RUNNING', 'FINISHED', 'FAILED'];
  for (var key in ['actionStates', 'instantActionStates', 'zoneActionStates']) {
    for (var action in c.maps(json, key, where)) {
      c.required(action, ['actionId', 'actionStatus'], '$where.$key');
      c.oneOf(action['actionStatus'], statuses, '$where.$key.actionStatus');
      c.absent(action, [v3 ? 'resultDescription' : 'actionResult'], '$where.$key');
    }
  }
  var power = c.map(json, v3 ? 'powerSupply' : 'batteryState', where);
  c.required(power, [v3 ? 'stateOfCharge' : 'batteryCharge', 'charging'], '$where.power');
  for (var error in c.maps(json, 'errors', where)) {
    c.required(error, ['errorType', 'errorLevel'], '$where.errors');
    c.oneOf(error['errorLevel'], v3 ? ['WARNING', 'URGENT', 'CRITICAL', 'FATAL'] : ['WARNING', 'FATAL'], '$where.errorLevel');
  }
  var safety = c.map(json, 'safetyState', where);
  c.required(safety, [v3 ? 'activeEmergencyStop' : 'eStop', 'fieldViolation'], '$where.safetyState');
  c.oneOf(safety[v3 ? 'activeEmergencyStop' : 'eStop'],
      v3 ? ['MANUAL', 'REMOTE', 'NONE'] : ['AUTOACK', 'MANUAL', 'REMOTE', 'NONE'], '$where.safetyState');
  for (var map in c.maps(json, 'maps', where)) {
    c.required(map, ['mapId', 'mapVersion', 'mapStatus'], '$where.maps');
  }
  for (var zoneSet in c.maps(json, 'zoneSets', where)) {
    c.required(zoneSet, ['zoneSetId', 'mapId', 'zoneSetStatus'], '$where.zoneSets');
  }
  for (var request in c.maps(json, 'zoneRequests', where)) {
    c.required(request, ['requestId', 'requestType', 'zoneId', 'zoneSetId', 'requestStatus'], '$where.zoneRequests');
    c.oneOf(request['requestType'], ['ACCESS', 'REPLANNING'], '$where.zoneRequests.requestType');
    c.oneOf(request['requestStatus'], ['REQUESTED', 'GRANTED', 'REVOKED', 'EXPIRED'], '$where.zoneRequests.requestStatus');
  }
  if (json['plannedPath'] != null) {
    var trajectory = c.map(c.map(json, 'plannedPath', where), 'trajectory', '$where.plannedPath');
    c.required(trajectory, ['controlPoints'], '$where.plannedPath.trajectory');
  }
  if (json['intermediatePath'] != null) {
    for (var point in c.maps(c.map(json, 'intermediatePath', where), 'polyline', '$where.intermediatePath')) {
      c.required(point, ['x', 'y', 'eta'], '$where.intermediatePath.polyline');
    }
  }
}

void _action(_Checker c, Map action, bool v3, String where) {
  c.required(action, ['actionId', 'actionType', 'blockingType'], where);
  c.oneOf(action['blockingType'], v3 ? ['NONE', 'SOFT', 'SINGLE', 'HARD'] : ['NONE', 'SOFT', 'HARD'], '$where.blockingType');
  c.absent(action, [v3 ? 'actionDescription' : 'actionDescriptor'], where);
  for (var parameter in c.maps(action, 'actionParameters', where)) {
    c.required(parameter, ['key', 'value'], '$where.actionParameters');
  }
}

void _order(_Checker c, Map json, bool v3) {
  const where = 'order';
  c.required(json, ['orderId', 'orderUpdateId', 'nodes', 'edges'], where);
  if (v3) {
    c.absent(json, ['zoneSetId'], where);
  }
  for (var node in c.maps(json, 'nodes', where)) {
    c.required(node, ['nodeId', 'sequenceId', 'released', 'actions'], '$where.nodes');
    if (node['nodePosition'] != null) {
      c.required(c.map(node, 'nodePosition', '$where.nodes'), ['x', 'y', 'mapId'], '$where.nodes.nodePosition');
    }
    for (var action in c.maps(node, 'actions', '$where.nodes')) {
      _action(c, action, v3, '$where.nodes.actions');
    }
  }
  for (var edge in c.maps(json, 'edges', where)) {
    c.required(edge, ['edgeId', 'sequenceId', 'released', 'actions', if (!v3) 'startNodeId', if (!v3) 'endNodeId'],
        '$where.edges');
    c.absent(edge, v3 ? ['startNodeId', 'endNodeId', 'maxSpeed'] : ['maximumSpeed'], '$where.edges');
    for (var action in c.maps(edge, 'actions', '$where.edges')) {
      _action(c, action, v3, '$where.edges.actions');
    }
  }
}

void _factsheet(_Checker c, Map json, bool v3) {
  const where = 'factsheet';
  c.required(json, [
    'typeSpecification', 'physicalParameters', 'protocolLimits', 'protocolFeatures', 'loadSpecification',
    v3 ? 'mobileRobotGeometry' : 'agvGeometry',
  ], where);
  var type = c.map(json, 'typeSpecification', where);
  var physical = c.map(json, 'physicalParameters', where);
  var limits = c.map(json, 'protocolLimits', where);
  var features = c.map(json, 'protocolFeatures', where);
  if (v3) {
    c.required(type, ['seriesName', 'mobileRobotKinematics', 'mobileRobotClass', 'maximumLoadMass', 'localizationTypes',
      'navigationTypes'], '$where.typeSpecification');
    c.required(physical, ['minimumSpeed', 'maximumSpeed', 'maximumAcceleration', 'maximumDeceleration', 'minimumHeight',
      'maximumHeight', 'width', 'length'], '$where.physicalParameters');
    c.required(limits, ['maximumStringLengths', 'maximumArrayLengths', 'timing'], '$where.protocolLimits');
    c.required(c.map(limits, 'timing', where), ['minimumOrderInterval', 'minimumStateInterval'], '$where.timing');
    c.required(features, ['optionalParameters', 'mobileRobotActions'], '$where.protocolFeatures');
    for (var action in c.maps(features, 'mobileRobotActions', where)) {
      c.required(action, ['actionType', 'actionScopes', 'pauseAllowed', 'cancelAllowed'], '$where.mobileRobotActions');
    }
  } else {
    c.required(type, ['seriesName', 'agvKinematic', 'agvClass', 'maxLoadMass', 'localizationTypes', 'navigationTypes'],
        '$where.typeSpecification');
    c.oneOf(type['agvKinematic'], ['DIFF', 'OMNI', 'THREEWHEEL'], '$where.agvKinematic');
    for (var navigation in (type['navigationTypes'] as List? ?? const [])) {
      c.oneOf(navigation, ['PHYSICAL_LINE_GUIDED', 'VIRTUAL_LINE_GUIDED', 'AUTONOMOUS'], '$where.navigationTypes');
    }
    c.required(physical, ['speedMin', 'speedMax', 'accelerationMax', 'decelerationMax', 'heightMax', 'width', 'length'],
        '$where.physicalParameters');
    c.required(limits, ['maxStringLens', 'maxArrayLens', 'timing'], '$where.protocolLimits');
    c.required(c.map(limits, 'timing', where), ['minOrderInterval', 'minStateInterval'], '$where.timing');
    c.required(features, ['optionalParameters', 'agvActions'], '$where.protocolFeatures');
    for (var action in c.maps(features, 'agvActions', where)) {
      c.required(action, ['actionType', 'actionScopes'], '$where.agvActions');
      for (var scope in (action['actionScopes'] as List? ?? const [])) {
        c.oneOf(scope, ['INSTANT', 'NODE', 'EDGE'], '$where.agvActions.actionScopes');
      }
    }
  }
}

void _zoneSet(_Checker c, Map json) {
  const where = 'zoneSet';
  c.required(json, ['zoneSet'], where);
  var zoneSet = c.map(json, 'zoneSet', where);
  c.required(zoneSet, ['mapId', 'zoneSetId', 'zones'], '$where.zoneSet');
  for (var zone in c.maps(zoneSet, 'zones', where)) {
    c.required(zone, ['zoneId', 'zoneType', 'vertices'], '$where.zones');
    c.oneOf(
        zone['zoneType'],
        ['BLOCKED', 'LINE_GUIDED', 'RELEASE', 'COORDINATED_REPLANNING', 'SPEED_LIMIT', 'ACTION', 'PRIORITY', 'PENALTY',
          'DIRECTED', 'BIDIRECTED'],
        '$where.zoneType');
    if ((zone['vertices'] as List? ?? const []).length < 3) {
      c.errors.add('$where.zones: fewer than 3 vertices');
    }
    if (zone['zoneType'] == 'RELEASE') {
      c.required(zone, ['releaseLossBehavior'], '$where.zones');
    }
    if (zone['zoneType'] == 'SPEED_LIMIT') {
      c.required(zone, ['maximumSpeed'], '$where.zones');
    }
  }
}
