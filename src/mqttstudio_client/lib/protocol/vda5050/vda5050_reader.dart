import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';

// Reads VDA 5050 JSON of any version into the version-neutral model (doc/vda5050-design.md §6.6, V6, V15). Reading
// is tolerant: a missing field gets an empty value, a field of the wrong type is ignored, and top-level fields the
// reader doesn't know are kept in VdaMessage.extra. Both the 2.x and the 3.0 names are accepted, and 2.x enum
// values are turned into their 3.0 spelling (CONNECTIONBROKEN -> CONNECTION_BROKEN).
class Vda5050Reader {
  // the version a message is read as: from its header, else from the topic, else the newest
  static VdaVersion versionOf(Map<String, Object?> json, {VdaVersion? topicVersion}) =>
      VdaVersion.parse(_str(json['version'])) ?? topicVersion ?? VdaVersion.v3;

  // null for a topic that isn't a VDA 5050 topic
  static VdaMessage? read(String topic, Map<String, Object?> json) {
    var known = <String>{..._headerKeys};
    VdaMessage? message;
    switch (topic) {
      case VdaTopic.order:
        message = _order(json, known);
      case VdaTopic.instantActions:
        known.addAll(['actions', 'instantActions']);
        message = VdaInstantActions(actions: _actions(json['actions'] ?? json['instantActions']));
      case VdaTopic.state:
        message = _state(json, known);
      case VdaTopic.visualization:
        message = _visualization(json, known);
      case VdaTopic.connection:
        known.add('connectionState');
        message = VdaConnection(connectionState: _connectionState(_str(json['connectionState'])));
      case VdaTopic.factsheet:
        message = _factsheet(json, known);
      case VdaTopic.zoneSet:
        known.add('zoneSet');
        message = VdaZoneSetMessage(zoneSet: _zoneSet(_map(json['zoneSet'])));
      case VdaTopic.responses:
        known.add('responses');
        message = VdaResponses(responses: [
          for (var item in _maps(json['responses']))
            VdaResponse(
                requestId: _str(item['requestId']),
                grantType: _str(item['grantType'] ?? item['responseType']),
                leaseExpiry: item['leaseExpiry'] == null ? null : _time(item['leaseExpiry']))
        ]);
    }
    if (message == null) {
      return null;
    }
    message.header = header(json);
    for (var entry in json.entries) {
      if (!known.contains(entry.key)) {
        message.extra[_neutralKey(entry.key)] = entry.value;
      }
    }
    return message;
  }

  static const List<String> _headerKeys = ['headerId', 'timestamp', 'version', 'manufacturer', 'serialNumber'];

  static VdaHeader header(Map<String, Object?> json) => VdaHeader(
        headerId: _int(json['headerId']),
        timestamp: _time(json['timestamp']),
        version: _str(json['version']),
        manufacturer: _str(json['manufacturer']),
        serialNumber: _str(json['serialNumber']),
      );

  static VdaOrder _order(Map<String, Object?> json, Set<String> known) {
    known.addAll(['orderId', 'orderUpdateId', 'nodes', 'edges']);
    return VdaOrder(
      orderId: _str(json['orderId']),
      orderUpdateId: _int(json['orderUpdateId']),
      nodes: [
        for (var node in _maps(json['nodes']))
          VdaNode(
            nodeId: _str(node['nodeId']),
            sequenceId: _int(node['sequenceId']),
            released: _bool(node['released']),
            descriptor: _optStr(node['nodeDescriptor'] ?? node['nodeDescription']),
            position: _nodePosition(node['nodePosition']),
            actions: _actions(node['actions']),
          )
      ],
      edges: [
        for (var edge in _maps(json['edges']))
          VdaEdge(
            edgeId: _str(edge['edgeId']),
            sequenceId: _int(edge['sequenceId']),
            released: _bool(edge['released']),
            descriptor: _optStr(edge['edgeDescriptor'] ?? edge['edgeDescription']),
            startNodeId: _optStr(edge['startNodeId']),
            endNodeId: _optStr(edge['endNodeId']),
            maximumSpeed: _optDouble(edge['maximumSpeed'] ?? edge['maxSpeed']),
            actions: _actions(edge['actions']),
          )
      ],
    );
  }

  static VdaNodePosition? _nodePosition(Object? value) {
    if (value is! Map) {
      return null;
    }
    var json = _map(value);
    return VdaNodePosition(
        x: _double(json['x']), y: _double(json['y']), theta: _optDouble(json['theta']), mapId: _str(json['mapId']));
  }

  static List<VdaAction> _actions(Object? value) => [
        for (var action in _maps(value))
          VdaAction(
            actionId: _str(action['actionId']),
            actionType: _str(action['actionType']),
            blockingType: _str(action['blockingType']),
            descriptor: _optStr(action['actionDescriptor'] ?? action['actionDescription']),
            parameters: [
              for (var parameter in _maps(action['actionParameters']))
                VdaActionParameter(_str(parameter['key']), parameter['value'])
            ],
            retriable: action['retriable'] is bool ? action['retriable'] as bool : null,
          )
      ];

  static VdaState _state(Map<String, Object?> json, Set<String> known) {
    known.addAll([
      'maps', 'zoneSets', 'orderId', 'orderUpdateId', 'zoneSetId', 'lastNodeId', 'lastNodeSequenceId', 'nodeStates',
      'edgeStates', 'plannedPath', 'intermediatePath', 'mobileRobotPosition', 'agvPosition', 'velocity', 'loads',
      'driving', 'paused', 'newBaseRequest', 'zoneRequests', 'edgeRequests', 'distanceSinceLastNode', 'actionStates',
      'instantActionStates', 'zoneActionStates', 'powerSupply', 'batteryState', 'operatingMode', 'errors',
      'information', 'safetyState',
    ]);
    var safety = _map(json['safetyState']);
    return VdaState(
      maps: [
        for (var map in _maps(json['maps']))
          VdaMapInfo(mapId: _str(map['mapId']), mapVersion: _str(map['mapVersion']), status: _str(map['mapStatus']))
      ],
      zoneSets: [
        for (var zoneSet in _maps(json['zoneSets']))
          VdaZoneSetInfo(
              zoneSetId: _str(zoneSet['zoneSetId']), mapId: _str(zoneSet['mapId']), status: _str(zoneSet['zoneSetStatus']))
      ],
      orderId: _str(json['orderId']),
      orderUpdateId: _int(json['orderUpdateId']),
      zoneSetId: _optStr(json['zoneSetId']),
      lastNodeId: _str(json['lastNodeId']),
      lastNodeSequenceId: _int(json['lastNodeSequenceId']),
      nodeStates: [
        for (var node in _maps(json['nodeStates']))
          VdaNodeState(
            nodeId: _str(node['nodeId']),
            sequenceId: _int(node['sequenceId']),
            released: _bool(node['released']),
            descriptor: _optStr(node['nodeDescriptor'] ?? node['nodeDescription']),
            position: _nodePosition(node['nodePosition']),
          )
      ],
      edgeStates: [
        for (var edge in _maps(json['edgeStates']))
          VdaEdgeState(
            edgeId: _str(edge['edgeId']),
            sequenceId: _int(edge['sequenceId']),
            released: _bool(edge['released']),
            descriptor: _optStr(edge['edgeDescriptor'] ?? edge['edgeDescription']),
          )
      ],
      plannedPath: _plannedPath(json['plannedPath']),
      intermediatePath: _intermediatePath(json['intermediatePath']),
      position: _position(json['mobileRobotPosition'] ?? json['agvPosition']),
      velocity: _velocity(json['velocity']),
      loads: _maps(json['loads']),
      driving: _bool(json['driving']),
      paused: json['paused'] is bool ? json['paused'] as bool : null,
      newBaseRequest: json['newBaseRequest'] is bool ? json['newBaseRequest'] as bool : null,
      zoneRequests: [
        for (var request in _maps(json['zoneRequests']))
          VdaZoneRequest(
            requestId: _str(request['requestId']),
            requestType: _str(request['requestType']),
            zoneId: _str(request['zoneId']),
            zoneSetId: _str(request['zoneSetId']),
            requestStatus: _str(request['requestStatus']),
          )
      ],
      edgeRequests: [
        for (var request in _maps(json['edgeRequests']))
          VdaEdgeRequest(
            requestId: _str(request['requestId']),
            requestType: _str(request['requestType']),
            edgeId: _str(request['edgeId']),
            sequenceId: _int(request['sequenceId']),
            requestStatus: _str(request['requestStatus']),
          )
      ],
      distanceSinceLastNode: _optDouble(json['distanceSinceLastNode']),
      actionStates: _actionStates(json['actionStates']),
      instantActionStates: _actionStates(json['instantActionStates']),
      zoneActionStates: _actionStates(json['zoneActionStates']),
      powerSupply: _powerSupply(_map(json['powerSupply'] ?? json['batteryState'])),
      operatingMode: _operatingMode(_str(json['operatingMode'])),
      errors: [
        for (var error in _maps(json['errors']))
          VdaError(
            errorType: _str(error['errorType']),
            errorLevel: _str(error['errorLevel']),
            description: _optStr(error['errorDescription']),
            hint: _optStr(error['errorHint']),
            references: _references(error['errorReferences']),
          )
      ],
      information: [
        for (var info in _maps(json['information']))
          VdaInfo(
            infoType: _str(info['infoType']),
            infoLevel: _str(info['infoLevel']),
            descriptor: _optStr(info['infoDescriptor'] ?? info['infoDescription']),
            references: _references(info['infoReferences']),
          )
      ],
      safetyState: VdaSafetyState(
        activeEmergencyStop: _str(safety['activeEmergencyStop'] ?? safety['eStop'], VdaEmergencyStop.none),
        fieldViolation: _bool(safety['fieldViolation']),
      ),
    );
  }

  static VdaPosition? _position(Object? value) {
    if (value is! Map) {
      return null;
    }
    var json = _map(value);
    return VdaPosition(
      x: _double(json['x']),
      y: _double(json['y']),
      theta: _double(json['theta']),
      mapId: _str(json['mapId']),
      localized: _bool(json['localized'] ?? json['positionInitialized']),
      localizationScore: _optDouble(json['localizationScore']),
      deviationRange: _optDouble(json['deviationRange']),
    );
  }

  static VdaVelocity? _velocity(Object? value) {
    if (value is! Map) {
      return null;
    }
    var json = _map(value);
    return VdaVelocity(vx: _optDouble(json['vx']), vy: _optDouble(json['vy']), omega: _optDouble(json['omega']));
  }

  static VdaPowerSupply _powerSupply(Map<String, Object?> json) => VdaPowerSupply(
        stateOfCharge: _double(json['stateOfCharge'] ?? json['batteryCharge']),
        charging: _bool(json['charging']),
        batteryVoltage: _optDouble(json['batteryVoltage']),
        batteryCurrent: _optDouble(json['batteryCurrent']),
        batteryHealth: _optDouble(json['batteryHealth']),
        range: _optDouble(json['range'] ?? json['reach']),
      );

  static List<VdaActionState> _actionStates(Object? value) => [
        for (var action in _maps(value))
          VdaActionState(
            actionId: _str(action['actionId']),
            actionType: _optStr(action['actionType']),
            status: _str(action['actionStatus']),
            descriptor: _optStr(action['actionDescriptor'] ?? action['actionDescription']),
            result: _optStr(action['actionResult'] ?? action['resultDescription']),
          )
      ];

  static List<VdaReference> _references(Object? value) => [
        for (var reference in _maps(value)) VdaReference(_str(reference['referenceKey']), _str(reference['referenceValue']))
      ];

  static VdaPlannedPath? _plannedPath(Object? value) {
    if (value is! Map) {
      return null;
    }
    var json = _map(value);
    return VdaPlannedPath(
      controlPoints: [
        for (var point in _maps(_map(json['trajectory'])['controlPoints'])) VdaPoint(_double(point['x']), _double(point['y']))
      ],
      traversedNodes: [for (var node in _list(json['traversedNodes'])) _str(node)],
    );
  }

  static VdaIntermediatePath? _intermediatePath(Object? value) {
    if (value is! Map) {
      return null;
    }
    return VdaIntermediatePath(polyline: [
      for (var point in _maps(_map(value)['polyline']))
        VdaPathPoint(
            x: _double(point['x']), y: _double(point['y']), theta: _optDouble(point['theta']), eta: _time(point['eta']))
    ]);
  }

  static VdaVisualization _visualization(Map<String, Object?> json, Set<String> known) {
    known.addAll(
        ['referenceStateHeaderId', 'plannedPath', 'intermediatePath', 'mobileRobotPosition', 'agvPosition', 'velocity']);
    return VdaVisualization(
      referenceStateHeaderId: json['referenceStateHeaderId'] is num ? _int(json['referenceStateHeaderId']) : null,
      plannedPath: _plannedPath(json['plannedPath']),
      intermediatePath: _intermediatePath(json['intermediatePath']),
      position: _position(json['mobileRobotPosition'] ?? json['agvPosition']),
      velocity: _velocity(json['velocity']),
    );
  }

  static VdaFactsheet _factsheet(Map<String, Object?> json, Set<String> known) {
    known.addAll(['typeSpecification', 'physicalParameters', 'protocolLimits', 'protocolFeatures']);
    var type = _map(json['typeSpecification']);
    var physical = _map(json['physicalParameters']);
    var timing = _map(_map(json['protocolLimits'])['timing']);
    var features = _map(json['protocolFeatures']);
    return VdaFactsheet(
      seriesName: _str(type['seriesName']),
      seriesDescription: _optStr(type['seriesDescription']),
      kinematics: _kinematics3[_str(type['mobileRobotKinematics'] ?? type['agvKinematic'])] ??
          _str(type['mobileRobotKinematics'] ?? type['agvKinematic']),
      robotClass: _str(type['mobileRobotClass'] ?? type['agvClass']),
      maximumLoadMass: _double(type['maximumLoadMass'] ?? type['maxLoadMass']),
      localizationTypes: [for (var item in _list(type['localizationTypes'])) _str(item)],
      navigationTypes: [
        for (var item in _list(type['navigationTypes'])) _str(item) == 'AUTONOMOUS' ? 'FREELY_NAVIGATING' : _str(item)
      ],
      minimumSpeed: _double(physical['minimumSpeed'] ?? physical['speedMin']),
      maximumSpeed: _double(physical['maximumSpeed'] ?? physical['speedMax']),
      maximumAcceleration: _double(physical['maximumAcceleration'] ?? physical['accelerationMax']),
      maximumDeceleration: _double(physical['maximumDeceleration'] ?? physical['decelerationMax']),
      minimumHeight: _double(physical['minimumHeight'] ?? physical['heightMin']),
      maximumHeight: _double(physical['maximumHeight'] ?? physical['heightMax']),
      width: _double(physical['width']),
      length: _double(physical['length']),
      minimumOrderInterval: _double(timing['minimumOrderInterval'] ?? timing['minOrderInterval']),
      minimumStateInterval: _double(timing['minimumStateInterval'] ?? timing['minStateInterval']),
      actions: [
        for (var action in _maps(features['mobileRobotActions'] ?? features['agvActions']))
          VdaFactsheetAction(
            _str(action['actionType']),
            [for (var scope in _list(action['actionScopes'])) _str(scope)],
            pauseAllowed: _bool(action['pauseAllowed']),
            cancelAllowed: _bool(action['cancelAllowed']),
          )
      ],
    );
  }

  static const Map<String, String> _kinematics3 = {
    'DIFF': 'DIFFERENTIAL',
    'OMNI': 'OMNIDIRECTIONAL',
    'THREEWHEEL': 'THREE_WHEEL',
  };

  static VdaZoneSet _zoneSet(Map<String, Object?> json) {
    const zoneKeys = {'zoneId', 'zoneType', 'zoneDescriptor', 'vertices'};
    return VdaZoneSet(
      zoneSetId: _str(json['zoneSetId']),
      mapId: _str(json['mapId']),
      descriptor: _optStr(json['zoneSetDescriptor']),
      zones: [
        for (var zone in _maps(json['zones']))
          VdaZone(
            zoneId: _str(zone['zoneId']),
            zoneType: _str(zone['zoneType']),
            descriptor: _optStr(zone['zoneDescriptor']),
            vertices: [for (var vertex in _maps(zone['vertices'])) VdaPoint(_double(vertex['x']), _double(vertex['y']))],
            parameters: {
              for (var entry in zone.entries)
                if (!zoneKeys.contains(entry.key)) entry.key: entry.value
            },
          )
      ],
    );
  }

  static String _connectionState(String state) =>
      state == 'CONNECTIONBROKEN' ? VdaConnectionState.connectionBroken : state;

  static String _operatingMode(String mode) => mode == 'TEACHIN' ? VdaOperatingMode.teachIn : mode;

  static String _neutralKey(String key) {
    for (var entry in Vda5050Names.factsheetSections2.entries) {
      if (entry.value == key) {
        return entry.key;
      }
    }
    return key;
  }

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? {for (var entry in value.entries) '${entry.key}': entry.value} : {};

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  static List<Map<String, Object?>> _maps(Object? value) => [
        for (var item in _list(value))
          if (item is Map) _map(item)
      ];

  static String _str(Object? value, [String fallback = '']) =>
      value is String ? value : (value is num || value is bool ? '$value' : fallback);

  static String? _optStr(Object? value) => value == null ? null : _str(value);

  static int _int(Object? value) => value is num ? value.toInt() : (int.tryParse(_str(value)) ?? 0);

  static double _double(Object? value) => _optDouble(value) ?? 0;

  static double? _optDouble(Object? value) => value is num ? value.toDouble() : double.tryParse(_str(value));

  static bool _bool(Object? value) => value == true;

  // an unparsable timestamp reads as the epoch, so the message is still shown
  static DateTime _time(Object? value) =>
      DateTime.tryParse(_str(value))?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
