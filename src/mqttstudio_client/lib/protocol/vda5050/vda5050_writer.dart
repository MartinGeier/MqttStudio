import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';

// Writes the version-neutral model as the JSON of VDA 5050 2.1.0 or 3.0.0 (doc/vda5050-design.md §6.6, V21).
// Optional fields that are null are left out. 3.0 values that 2.x doesn't have are written as their closest 2.x
// value, so a 2.x message stays valid against the 2.1 schema; 3.0 parts without a 2.x field (paths, zones,
// requests) are left out.
class Vda5050Writer {
  final VdaVersion version;

  const Vda5050Writer(this.version);

  bool get _v3 => version.isV3;

  Map<String, Object?> toJson(VdaMessage message) {
    var json = <String, Object?>{..._header(message.header)};
    switch (message) {
      case VdaOrder order:
        _order(order, json);
      case VdaInstantActions instant:
        json['actions'] = [for (var action in instant.actions) _action(action)];
      case VdaState state:
        _state(state, json);
      case VdaVisualization visualization:
        _visualization(visualization, json);
      case VdaConnection connection:
        json['connectionState'] = _connectionState(connection.connectionState);
      case VdaFactsheet factsheet:
        _factsheet(factsheet, json);
      case VdaZoneSetMessage zoneSet:
        json['zoneSet'] = _zoneSet(zoneSet.zoneSet);
      case VdaResponses responses:
        json['responses'] = [for (var response in responses.responses) _response(response)];
    }
    for (var entry in message.extra.entries) {
      json.putIfAbsent(_extraKey(entry.key), () => entry.value);
    }
    return json;
  }

  // ISO 8601 in UTC: milliseconds for 3.0, hundredths of a second for 2.x
  String timestamp(DateTime time) {
    var utc = time.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    var fraction = _v3 ? utc.millisecond.toString().padLeft(3, '0') : two(utc.millisecond ~/ 10);
    return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}'
        'T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}.${fraction}Z';
  }

  Map<String, Object?> _header(VdaHeader header) => {
        'headerId': header.headerId,
        'timestamp': timestamp(header.timestamp),
        'version': header.version.isEmpty ? version.protocolVersion : header.version,
        'manufacturer': header.manufacturer,
        'serialNumber': header.serialNumber,
      };

  String get _descriptorKey => _v3 ? 'Descriptor' : 'Description';

  void _order(VdaOrder order, Map<String, Object?> json) {
    json['orderId'] = order.orderId;
    json['orderUpdateId'] = order.orderUpdateId;
    json['nodes'] = [for (var node in order.nodes) _node(node)];
    json['edges'] = [for (var edge in order.edges) _edge(edge, order)];
  }

  Map<String, Object?> _node(VdaNode node) => {
        'nodeId': node.nodeId,
        'sequenceId': node.sequenceId,
        if (node.descriptor != null) 'node$_descriptorKey': node.descriptor,
        'released': node.released,
        if (node.position != null) 'nodePosition': _nodePosition(node.position!),
        'actions': [for (var action in node.actions) _action(action)],
      };

  Map<String, Object?> _nodePosition(VdaNodePosition position) => {
        'x': position.x,
        'y': position.y,
        if (position.theta != null) 'theta': position.theta,
        'mapId': position.mapId,
      };

  // 2.x needs the start and end node; they are the nodes next to the edge in the sequence
  Map<String, Object?> _edge(VdaEdge edge, VdaOrder order) {
    String? nodeAt(int sequenceId) => order.nodes.where((node) => node.sequenceId == sequenceId).firstOrNull?.nodeId;
    return {
      'edgeId': edge.edgeId,
      'sequenceId': edge.sequenceId,
      if (edge.descriptor != null) 'edge$_descriptorKey': edge.descriptor,
      'released': edge.released,
      if (!_v3) 'startNodeId': edge.startNodeId ?? nodeAt(edge.sequenceId - 1) ?? '',
      if (!_v3) 'endNodeId': edge.endNodeId ?? nodeAt(edge.sequenceId + 1) ?? '',
      if (edge.maximumSpeed != null) (_v3 ? 'maximumSpeed' : 'maxSpeed'): edge.maximumSpeed,
      'actions': [for (var action in edge.actions) _action(action)],
    };
  }

  Map<String, Object?> _action(VdaAction action) => {
        'actionType': action.actionType,
        'actionId': action.actionId,
        if (action.descriptor != null) 'action$_descriptorKey': action.descriptor,
        'blockingType': _blockingType(action.blockingType),
        if (action.parameters.isNotEmpty)
          'actionParameters': [
            for (var parameter in action.parameters) {'key': parameter.key, 'value': parameter.value}
          ],
        if (_v3 && action.retriable != null) 'retriable': action.retriable,
      };

  void _state(VdaState state, Map<String, Object?> json) {
    if (_v3) {
      if (state.maps.isNotEmpty) {
        json['maps'] = [for (var map in state.maps) _map(map)];
      }
      if (state.zoneSets.isNotEmpty) {
        json['zoneSets'] = [
          for (var zoneSet in state.zoneSets)
            {'zoneSetId': zoneSet.zoneSetId, 'mapId': zoneSet.mapId, 'zoneSetStatus': zoneSet.status}
        ];
      }
    } else if (state.maps.isNotEmpty) {
      json['maps'] = [for (var map in state.maps) _map(map)];
    }
    json['orderId'] = state.orderId;
    json['orderUpdateId'] = state.orderUpdateId;
    if (!_v3 && state.zoneSetId != null) {
      json['zoneSetId'] = state.zoneSetId;
    }
    json['lastNodeId'] = state.lastNodeId;
    json['lastNodeSequenceId'] = state.lastNodeSequenceId;
    json['nodeStates'] = [
      for (var node in state.nodeStates)
        {
          'nodeId': node.nodeId,
          'sequenceId': node.sequenceId,
          if (node.descriptor != null) 'node$_descriptorKey': node.descriptor,
          'released': node.released,
          if (node.position != null) 'nodePosition': _nodePosition(node.position!),
        }
    ];
    json['edgeStates'] = [
      for (var edge in state.edgeStates)
        {
          'edgeId': edge.edgeId,
          'sequenceId': edge.sequenceId,
          if (edge.descriptor != null) 'edge$_descriptorKey': edge.descriptor,
          'released': edge.released,
        }
    ];
    if (_v3) {
      if (state.plannedPath != null) {
        json['plannedPath'] = _plannedPath(state.plannedPath!);
      }
      if (state.intermediatePath != null) {
        json['intermediatePath'] = _intermediatePath(state.intermediatePath!);
      }
    }
    if (state.position != null) {
      json[_v3 ? 'mobileRobotPosition' : 'agvPosition'] = _position(state.position!);
    }
    if (state.velocity != null) {
      json['velocity'] = _velocity(state.velocity!);
    }
    if (state.loads.isNotEmpty) {
      json['loads'] = state.loads;
    }
    json['driving'] = state.driving;
    if (state.paused != null) {
      json['paused'] = state.paused;
    }
    if (state.newBaseRequest != null) {
      json['newBaseRequest'] = state.newBaseRequest;
    }
    if (_v3) {
      if (state.zoneRequests.isNotEmpty) {
        json['zoneRequests'] = [for (var request in state.zoneRequests) _zoneRequest(request)];
      }
      if (state.edgeRequests.isNotEmpty) {
        json['edgeRequests'] = [for (var request in state.edgeRequests) _edgeRequest(request)];
      }
    }
    if (state.distanceSinceLastNode != null) {
      json['distanceSinceLastNode'] = state.distanceSinceLastNode;
    }
    if (_v3) {
      json['actionStates'] = [for (var action in state.actionStates) _actionState(action)];
      json['instantActionStates'] = [for (var action in state.instantActionStates) _actionState(action)];
      if (state.zoneActionStates.isNotEmpty) {
        json['zoneActionStates'] = [for (var action in state.zoneActionStates) _actionState(action)];
      }
      json['powerSupply'] = _powerSupply(state.powerSupply);
    } else {
      // 2.x has one list for the actions of the order and the instant actions
      json['actionStates'] = [
        for (var action in [...state.actionStates, ...state.instantActionStates, ...state.zoneActionStates])
          _actionState(action)
      ];
      json['batteryState'] = _powerSupply(state.powerSupply);
    }
    json['operatingMode'] = _operatingMode(state.operatingMode);
    json['errors'] = [for (var error in state.errors) _error(error)];
    if (state.information.isNotEmpty) {
      json['information'] = [for (var info in state.information) _info(info)];
    }
    json['safetyState'] = {
      (_v3 ? 'activeEmergencyStop' : 'eStop'): state.safetyState.activeEmergencyStop,
      'fieldViolation': state.safetyState.fieldViolation,
    };
  }

  Map<String, Object?> _map(VdaMapInfo map) =>
      {'mapId': map.mapId, 'mapVersion': map.mapVersion, 'mapStatus': map.status};

  Map<String, Object?> _position(VdaPosition position) => {
        'x': position.x,
        'y': position.y,
        'theta': position.theta,
        'mapId': position.mapId,
        (_v3 ? 'localized' : 'positionInitialized'): position.localized,
        if (position.localizationScore != null) 'localizationScore': position.localizationScore,
        if (position.deviationRange != null) 'deviationRange': position.deviationRange,
      };

  Map<String, Object?> _velocity(VdaVelocity velocity) => {
        if (velocity.vx != null) 'vx': velocity.vx,
        if (velocity.vy != null) 'vy': velocity.vy,
        if (velocity.omega != null) 'omega': velocity.omega,
      };

  Map<String, Object?> _powerSupply(VdaPowerSupply power) => _v3
      ? {
          'stateOfCharge': power.stateOfCharge,
          if (power.batteryVoltage != null) 'batteryVoltage': power.batteryVoltage,
          if (power.batteryCurrent != null) 'batteryCurrent': power.batteryCurrent,
          if (power.batteryHealth != null) 'batteryHealth': power.batteryHealth,
          'charging': power.charging,
          if (power.range != null) 'range': power.range,
        }
      : {
          'batteryCharge': power.stateOfCharge,
          if (power.batteryVoltage != null) 'batteryVoltage': power.batteryVoltage,
          if (power.batteryHealth != null) 'batteryHealth': power.batteryHealth,
          'charging': power.charging,
          if (power.range != null) 'reach': power.range,
        };

  Map<String, Object?> _actionState(VdaActionState action) => {
        'actionId': action.actionId,
        if (action.actionType != null) 'actionType': action.actionType,
        if (action.descriptor != null) 'action$_descriptorKey': action.descriptor,
        'actionStatus': _actionStatus(action.status),
        if (action.result != null) (_v3 ? 'actionResult' : 'resultDescription'): action.result,
      };

  Map<String, Object?> _error(VdaError error) => {
        'errorType': error.errorType,
        if (error.references.isNotEmpty) 'errorReferences': _references(error.references),
        if (error.description != null) 'errorDescription': error.description,
        if (error.hint != null) 'errorHint': error.hint,
        'errorLevel': _errorLevel(error.errorLevel),
      };

  Map<String, Object?> _info(VdaInfo info) => {
        'infoType': info.infoType,
        if (info.references.isNotEmpty) 'infoReferences': _references(info.references),
        if (info.descriptor != null) 'info$_descriptorKey': info.descriptor,
        'infoLevel': info.infoLevel,
      };

  List<Map<String, Object?>> _references(List<VdaReference> references) => [
        for (var reference in references) {'referenceKey': reference.key, 'referenceValue': reference.value}
      ];

  Map<String, Object?> _zoneRequest(VdaZoneRequest request) => {
        'requestId': request.requestId,
        'requestType': request.requestType,
        'zoneId': request.zoneId,
        'zoneSetId': request.zoneSetId,
        'requestStatus': request.requestStatus,
      };

  Map<String, Object?> _edgeRequest(VdaEdgeRequest request) => {
        'requestId': request.requestId,
        'requestType': request.requestType,
        'edgeId': request.edgeId,
        'sequenceId': request.sequenceId,
        'requestStatus': request.requestStatus,
      };

  Map<String, Object?> _plannedPath(VdaPlannedPath path) => {
        'trajectory': {
          'degree': 1,
          'controlPoints': [
            for (var point in path.controlPoints) {'x': point.x, 'y': point.y}
          ],
        },
        if (path.traversedNodes.isNotEmpty) 'traversedNodes': path.traversedNodes,
      };

  Map<String, Object?> _intermediatePath(VdaIntermediatePath path) => {
        'polyline': [
          for (var point in path.polyline)
            {'x': point.x, 'y': point.y, if (point.theta != null) 'theta': point.theta, 'eta': timestamp(point.eta)}
        ],
      };

  void _visualization(VdaVisualization visualization, Map<String, Object?> json) {
    if (_v3) {
      json['referenceStateHeaderId'] = visualization.referenceStateHeaderId ?? 0;
      if (visualization.plannedPath != null) {
        json['plannedPath'] = _plannedPath(visualization.plannedPath!);
      }
      if (visualization.intermediatePath != null) {
        json['intermediatePath'] = _intermediatePath(visualization.intermediatePath!);
      }
    }
    if (visualization.position != null) {
      json[_v3 ? 'mobileRobotPosition' : 'agvPosition'] = _position(visualization.position!);
    }
    if (visualization.velocity != null) {
      json['velocity'] = _velocity(visualization.velocity!);
    }
  }

  void _factsheet(VdaFactsheet factsheet, Map<String, Object?> json) {
    if (_v3) {
      json['typeSpecification'] = {
        'seriesName': factsheet.seriesName,
        if (factsheet.seriesDescription != null) 'seriesDescription': factsheet.seriesDescription,
        'mobileRobotKinematics': factsheet.kinematics,
        'mobileRobotClass': factsheet.robotClass,
        'maximumLoadMass': factsheet.maximumLoadMass,
        'localizationTypes': factsheet.localizationTypes,
        'navigationTypes': factsheet.navigationTypes,
      };
      json['physicalParameters'] = {
        'minimumSpeed': factsheet.minimumSpeed,
        'maximumSpeed': factsheet.maximumSpeed,
        'maximumAcceleration': factsheet.maximumAcceleration,
        'maximumDeceleration': factsheet.maximumDeceleration,
        'minimumHeight': factsheet.minimumHeight,
        'maximumHeight': factsheet.maximumHeight,
        'width': factsheet.width,
        'length': factsheet.length,
      };
      json['protocolLimits'] = {
        'maximumStringLengths': <String, Object?>{},
        'maximumArrayLengths': <String, Object?>{},
        'timing': {
          'minimumOrderInterval': factsheet.minimumOrderInterval,
          'minimumStateInterval': factsheet.minimumStateInterval,
        },
      };
      json['protocolFeatures'] = {
        'optionalParameters': <Object?>[],
        'mobileRobotActions': [
          for (var action in factsheet.actions)
            {
              'actionType': action.actionType,
              'actionScopes': action.scopes,
              'pauseAllowed': action.pauseAllowed,
              'cancelAllowed': action.cancelAllowed,
            }
        ],
      };
      json['mobileRobotGeometry'] = factsheet.extra['mobileRobotGeometry'] ?? <String, Object?>{};
    } else {
      json['typeSpecification'] = {
        'seriesName': factsheet.seriesName,
        if (factsheet.seriesDescription != null) 'seriesDescription': factsheet.seriesDescription,
        'agvKinematic': _kinematics2[factsheet.kinematics] ?? factsheet.kinematics,
        'agvClass': factsheet.robotClass,
        'maxLoadMass': factsheet.maximumLoadMass,
        'localizationTypes': factsheet.localizationTypes,
        'navigationTypes': [
          for (var type in factsheet.navigationTypes) type == 'FREELY_NAVIGATING' ? 'AUTONOMOUS' : type
        ],
      };
      json['physicalParameters'] = {
        'speedMin': factsheet.minimumSpeed,
        'speedMax': factsheet.maximumSpeed,
        'accelerationMax': factsheet.maximumAcceleration,
        'decelerationMax': factsheet.maximumDeceleration,
        'heightMin': factsheet.minimumHeight,
        'heightMax': factsheet.maximumHeight,
        'width': factsheet.width,
        'length': factsheet.length,
      };
      json['protocolLimits'] = {
        'maxStringLens': <String, Object?>{},
        'maxArrayLens': <String, Object?>{},
        'timing': {
          'minOrderInterval': factsheet.minimumOrderInterval,
          'minStateInterval': factsheet.minimumStateInterval,
        },
      };
      json['protocolFeatures'] = {
        'optionalParameters': <Object?>[],
        'agvActions': [
          for (var action in factsheet.actions)
            {'actionType': action.actionType, 'actionScopes': action.scopes.where((scope) => scope != 'ZONE').toList()}
        ],
      };
      json['agvGeometry'] = factsheet.extra['mobileRobotGeometry'] ?? <String, Object?>{};
    }
    json['loadSpecification'] = factsheet.extra['loadSpecification'] ?? <String, Object?>{};
  }

  static const Map<String, String> _kinematics2 = {
    'DIFFERENTIAL': 'DIFF',
    'OMNIDIRECTIONAL': 'OMNI',
    'THREE_WHEEL': 'THREEWHEEL',
  };

  Map<String, Object?> _zoneSet(VdaZoneSet zoneSet) => {
        'mapId': zoneSet.mapId,
        'zoneSetId': zoneSet.zoneSetId,
        if (zoneSet.descriptor != null) 'zoneSetDescriptor': zoneSet.descriptor,
        'zones': [
          for (var zone in zoneSet.zones)
            {
              'zoneId': zone.zoneId,
              'zoneType': zone.zoneType,
              if (zone.descriptor != null) 'zoneDescriptor': zone.descriptor,
              'vertices': [
                for (var vertex in zone.vertices) {'x': vertex.x, 'y': vertex.y}
              ],
              ...zone.parameters,
            }
        ],
      };

  Map<String, Object?> _response(VdaResponse response) => {
        'requestId': response.requestId,
        'grantType': response.grantType,
        if (response.leaseExpiry != null) 'leaseExpiry': timestamp(response.leaseExpiry!),
      };

  // the factsheet sections the reader keeps under their 3.0 name are written under the 2.x name
  String _extraKey(String key) => _v3 ? key : (Vda5050Names.factsheetSections2[key] ?? key);

  String _connectionState(String state) {
    if (_v3) {
      return state;
    }
    return switch (state) {
      VdaConnectionState.connectionBroken => 'CONNECTIONBROKEN',
      // 2.x has no hibernation; the robot isn't sending, like after a coordinated disconnect
      VdaConnectionState.hibernating => VdaConnectionState.offline,
      _ => state,
    };
  }

  String _operatingMode(String mode) {
    if (_v3) {
      return mode;
    }
    return switch (mode) {
      VdaOperatingMode.teachIn => 'TEACHIN',
      VdaOperatingMode.startup => VdaOperatingMode.automatic,
      VdaOperatingMode.intervened => VdaOperatingMode.manual,
      _ => mode,
    };
  }

  String _errorLevel(String level) {
    if (_v3) {
      return level;
    }
    return switch (level) {
      VdaErrorLevel.urgent => VdaErrorLevel.warning,
      VdaErrorLevel.critical => VdaErrorLevel.fatal,
      _ => level,
    };
  }

  String _actionStatus(String status) {
    if (_v3) {
      return status;
    }
    // the 2.1 schema has no PAUSED and RETRIABLE
    return switch (status) {
      VdaActionStatus.paused => VdaActionStatus.running,
      VdaActionStatus.retriable => VdaActionStatus.failed,
      _ => status,
    };
  }

  String _blockingType(String type) => !_v3 && type == VdaBlockingType.single ? VdaBlockingType.soft : type;
}
