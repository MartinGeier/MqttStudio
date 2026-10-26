import 'dart:math';
import 'package:mqttstudio/protocol/protocol_profile.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_reader.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_rules.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_writer.dart';

// Recognizes and interprets VDA 5050 messages of every version (doc/vda5050-design.md §6). It only reads what a
// message says, including the errors a robot reports; protocol violations are Vda5050Checker's (V5). Texts are
// English like the rest of the app; protocol terms stay as sent (V12).
class Vda5050Profile implements ProtocolProfile {
  static const String interfaceNameKey = 'interfaceName';
  static const String majorVersionKey = 'majorVersion';
  static const String manufacturerKey = 'manufacturer';
  static const String serialNumberKey = 'serialNumber';

  static final RegExp _majorLevel = RegExp(r'^v\d+$');

  @override
  String get id => 'vda5050';

  @override
  String get name => 'VDA 5050';

  // {interfaceName}/v{major}/{manufacturer}/{serialNumber}/{topic}; levels in front of these five are allowed
  @override
  ProtocolTopic? matchTopic(String topic) {
    var levels = topic.split('/');
    var count = levels.length;
    if (count < 5 || !VdaTopic.all.contains(levels.last) || !_majorLevel.hasMatch(levels[count - 4])) {
      return null;
    }
    return ProtocolTopic(this, levels.last, levels.sublist(0, count - 1).join('/'), {
      interfaceNameKey: levels[count - 5],
      majorVersionKey: levels[count - 4],
      manufacturerKey: levels[count - 3],
      serialNumberKey: levels[count - 2],
    });
  }

  // the version a message of the topic is read as: from its header, else from the topic
  static VdaVersion versionOf(ProtocolTopic topic, Map<String, Object?> json) =>
      Vda5050Reader.versionOf(json, topicVersion: VdaVersion.parse(topic.parameters[majorVersionKey]));

  static bool hasHeader(Object? data) =>
      data is Map && data.containsKey('headerId') && data.containsKey('manufacturer') && data.containsKey('serialNumber');

  @override
  ProtocolChecker createChecker() => Vda5050Checker(this);

  @override
  Interpretation? interpret(ProtocolTopic topic, Object? data, {InterpretationContext context = const NoContext()}) {
    if (!hasHeader(data)) {
      return null;
    }
    var json = (data as Map).map((key, value) => MapEntry('$key', value));
    var message = Vda5050Reader.read(topic.messageType, json);
    if (message == null) {
      return null;
    }
    var builder = _Builder(topic, message, context);
    return builder.build();
  }
}

class _Builder {
  final ProtocolTopic topic;
  final VdaMessage message;
  final InterpretationContext context;
  final List<InterpretedSection> sections = [];
  final Map<String, double> values = {};
  var level = InterpretationLevel.none;

  _Builder(this.topic, this.message, this.context);

  Interpretation build() {
    _header();
    var summary = switch (message) {
      VdaState state => _state(state),
      VdaOrder order => _order(order),
      VdaInstantActions instant => _instantActions(instant),
      VdaVisualization visualization => _visualization(visualization),
      VdaConnection connection => _connection(connection),
      VdaFactsheet factsheet => _factsheet(factsheet),
      VdaZoneSetMessage zoneSet => _zoneSet(zoneSet.zoneSet),
      VdaResponses responses => _responses(responses),
      _ => '',
    };
    if (message.extra.isNotEmpty) {
      sections.add(RawSection('other', 'Other fields', message.extra));
    }
    return Interpretation(
        protocolVersion: message.header.version,
        summary: summary,
        level: level,
        sections: sections,
        values: values);
  }

  void _raise(InterpretationLevel to) {
    if (to.index > level.index) {
      level = to;
    }
  }

  void _header() {
    var header = message.header;
    sections.add(KeyValueSection('header', 'Header', [
      InterpretedValue('Version', header.version),
      InterpretedValue('Header id', '${header.headerId}'),
      InterpretedValue('Timestamp', const Vda5050Writer(VdaVersion.v3).timestamp(header.timestamp)),
      InterpretedValue('Manufacturer', header.manufacturer),
      InterpretedValue('Serial number', header.serialNumber),
    ]));
  }

  // ---------- state ----------

  String _state(VdaState state) {
    var errorLevels = state.errors.map((error) => _errorLevel(error.errorLevel)).toList();
    for (var errorLevel in errorLevels) {
      _raise(errorLevel);
    }
    if (state.errors.isNotEmpty) {
      sections.add(TableSection('errors', 'Errors', const ['Level', 'Type', 'Description', 'Hint'], [
        for (var error in state.errors)
          InterpretedRow([error.errorLevel, error.errorType, error.description ?? '', error.hint ?? ''],
              level: _errorLevel(error.errorLevel))
      ]));
    }
    var power = state.powerSupply;
    var safety = state.safetyState;
    sections.add(KeyValueSection('status', 'Status', [
      InterpretedValue('Operating mode', state.operatingMode),
      InterpretedValue('Driving', _yesNo(state.driving)),
      if (state.paused != null) InterpretedValue('Paused', _yesNo(state.paused!)),
      InterpretedValue('Emergency stop', safety.activeEmergencyStop,
          level: safety.activeEmergencyStop == VdaEmergencyStop.none ? InterpretationLevel.none : InterpretationLevel.error),
      InterpretedValue('Field violation', _yesNo(safety.fieldViolation),
          level: safety.fieldViolation ? InterpretationLevel.warning : InterpretationLevel.none),
      InterpretedValue('State of charge', '${_n(power.stateOfCharge, 1)} %'),
      if (power.batteryVoltage != null) InterpretedValue('Battery voltage', '${_n(power.batteryVoltage!, 2)} V'),
      if (power.batteryCurrent != null) InterpretedValue('Battery current', '${_n(power.batteryCurrent!, 2)} A'),
      InterpretedValue('Charging', _yesNo(power.charging)),
      if (power.range != null) InterpretedValue('Range', '${_n(power.range!, 0)} m'),
      if (state.newBaseRequest != null) InterpretedValue('New base request', _yesNo(state.newBaseRequest!)),
    ]));
    values['State of charge %'] = power.stateOfCharge;
    if (power.batteryVoltage != null) {
      values['Battery voltage V'] = power.batteryVoltage!;
    }
    if (power.batteryCurrent != null) {
      values['Battery current A'] = power.batteryCurrent!;
    }
    _position(state.position, state.velocity);
    var baseLeft = state.nodeStates.where((node) => node.released).length;
    sections.add(KeyValueSection('order', 'Order', [
      InterpretedValue('Order id', state.orderId),
      InterpretedValue('Order update id', '${state.orderUpdateId}'),
      InterpretedValue('Last node', '${state.lastNodeId} (${state.lastNodeSequenceId})'),
      InterpretedValue('Nodes to go', '${state.nodeStates.length} ($baseLeft released)'),
      InterpretedValue('Edges to go', '${state.edgeStates.length}'),
      if (state.distanceSinceLastNode != null)
        InterpretedValue('Distance since last node', '${_n(state.distanceSinceLastNode!, 2)} m'),
    ]));
    _actionTable('actions', 'Actions', state.actionStates);
    _actionTable('instantActions', 'Instant actions', state.instantActionStates);
    _actionTable('zoneActions', 'Zone actions', state.zoneActionStates);
    var openRequests = _requests(state);
    _paths(state.plannedPath, state.intermediatePath);
    if (state.loads.isNotEmpty) {
      sections.add(TableSection('loads', 'Loads', const ['Load id', 'Type', 'Position'], [
        for (var load in state.loads)
          InterpretedRow(['${load['loadId'] ?? ''}', '${load['loadType'] ?? ''}', '${load['loadPosition'] ?? ''}'])
      ]));
    }
    if (state.information.isNotEmpty) {
      sections.add(TableSection('information', 'Information', const ['Level', 'Type', 'Description'], [
        for (var info in state.information) InterpretedRow([info.infoLevel, info.infoType, info.descriptor ?? ''])
      ]));
    }
    var driving = [state.driving ? 'DRIVING' : 'STOPPED', if (state.paused == true) 'PAUSED'].join('/');
    return [
      message.header.serialNumber,
      state.operatingMode,
      driving,
      '${_n(power.stateOfCharge, 0)} %${power.charging ? ' charging' : ''}',
      if (state.orderId.isNotEmpty)
        'order ${state.orderId}#${state.orderUpdateId} at ${state.lastNodeId}'
            '${state.nodeStates.isEmpty ? '' : ', ${state.nodeStates.length} ${state.nodeStates.length == 1 ? 'node' : 'nodes'} to go'}'
      else
        'at ${state.lastNodeId}',
      if (state.errors.isNotEmpty) '${state.errors.length} ${state.errors.length == 1 ? 'error' : 'errors'}',
      if (openRequests > 0) '$openRequests open ${openRequests == 1 ? 'request' : 'requests'}',
    ].join(' | ');
  }

  void _position(VdaPosition? position, VdaVelocity? velocity) {
    if (position == null && velocity == null) {
      return;
    }
    var speed = velocity == null ? null : sqrt(pow(velocity.vx ?? 0, 2) + pow(velocity.vy ?? 0, 2));
    sections.add(KeyValueSection('position', 'Position', [
      if (position != null) ...[
        InterpretedValue('x', '${_n(position.x, 3)} m'),
        InterpretedValue('y', '${_n(position.y, 3)} m'),
        InterpretedValue('θ', '${_n(position.theta, 3)} rad (${_n(position.theta * 180 / pi, 0)}°)'),
        InterpretedValue('Map', position.mapId),
        InterpretedValue('Localized', _yesNo(position.localized),
            level: position.localized ? InterpretationLevel.none : InterpretationLevel.warning),
        if (position.localizationScore != null)
          InterpretedValue('Localization score', _n(position.localizationScore!, 2)),
      ],
      if (speed != null) InterpretedValue('Velocity', '${_n(speed, 2)} m/s'),
    ]));
    if (position != null) {
      values['x m'] = position.x;
      values['y m'] = position.y;
      values['θ rad'] = position.theta;
      if (position.localizationScore != null) {
        values['Localization score'] = position.localizationScore!;
      }
    }
    if (speed != null) {
      values['Velocity m/s'] = speed;
    }
  }

  void _actionTable(String key, String title, List<VdaActionState> actions) {
    if (actions.isEmpty) {
      return;
    }
    sections.add(TableSection(key, title, const ['Type', 'Id', 'Status', 'Result'], [
      for (var action in actions)
        InterpretedRow([action.actionType ?? '', action.actionId, action.status, action.result ?? ''],
            level: switch (action.status) {
              VdaActionStatus.failed => InterpretationLevel.error,
              VdaActionStatus.retriable => InterpretationLevel.warning,
              _ => InterpretationLevel.none,
            })
    ]));
  }

  // the zone and edge requests with the fleet control's last answer; returns how many are still open
  int _requests(VdaState state) {
    if (state.zoneRequests.isEmpty && state.edgeRequests.isEmpty) {
      return 0;
    }
    var answers = <String, String>{};
    var responses = context.lastData(topic.deviceKey, VdaTopic.responses);
    if (responses is Map) {
      var read = Vda5050Reader.read(VdaTopic.responses, responses.map((key, value) => MapEntry('$key', value)));
      for (var response in (read as VdaResponses).responses) {
        answers[response.requestId] = response.grantType;
      }
    }
    var rows = [
      for (var request in state.zoneRequests)
        InterpretedRow([request.requestId, request.requestType, 'zone ${request.zoneId}', request.requestStatus,
          answers[request.requestId] ?? '']),
      for (var request in state.edgeRequests)
        InterpretedRow([request.requestId, request.requestType, 'edge ${request.edgeId}', request.requestStatus,
          answers[request.requestId] ?? '']),
    ];
    sections.add(TableSection('requests', 'Requests', const ['Request', 'Type', 'For', 'Status', 'Last response'], rows));
    return [
      ...state.zoneRequests.map((request) => request.requestStatus),
      ...state.edgeRequests.map((request) => request.requestStatus),
    ].where((status) => status == VdaRequestStatus.requested).length;
  }

  void _paths(VdaPlannedPath? planned, VdaIntermediatePath? intermediate) {
    if (planned == null && intermediate == null) {
      return;
    }
    sections.add(KeyValueSection('paths', 'Paths', [
      if (planned != null) InterpretedValue('Planned path', '${planned.controlPoints.length} points, ${_n(_length(planned.controlPoints), 1)} m'),
      if (intermediate != null)
        InterpretedValue('Intermediate path',
            '${intermediate.polyline.length} points, ${_n(_length([for (var p in intermediate.polyline) VdaPoint(p.x, p.y)]), 1)} m'),
    ]));
  }

  static double _length(List<VdaPoint> points) {
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += sqrt(pow(points[i].x - points[i - 1].x, 2) + pow(points[i].y - points[i - 1].y, 2));
    }
    return length;
  }

  // ---------- fleet control messages ----------

  String _order(VdaOrder order) {
    var nodes = [...order.nodes]..sort((a, b) => a.sequenceId.compareTo(b.sequenceId));
    var edges = {for (var edge in order.edges) edge.sequenceId: edge};
    var rows = <InterpretedRow>[];
    for (var node in nodes) {
      var position = node.position == null ? '' : '${_n(node.position!.x, 2)}, ${_n(node.position!.y, 2)}';
      rows.add(InterpretedRow(['${node.sequenceId}', 'node', node.nodeId, _yesNo(node.released), position,
        node.actions.map((action) => action.actionType).join(', ')], muted: !node.released));
      var edge = edges[node.sequenceId + 1];
      if (edge != null) {
        rows.add(InterpretedRow([
          '${edge.sequenceId}',
          'edge',
          edge.edgeId,
          _yesNo(edge.released),
          edge.maximumSpeed == null ? '' : 'max ${_n(edge.maximumSpeed!, 2)} m/s',
          edge.actions.map((action) => action.actionType).join(', ')
        ], muted: !edge.released));
      }
    }
    var actions = [
      for (var node in nodes) for (var action in node.actions) ('node ${node.nodeId}', action),
      for (var edge in order.edges) for (var action in edge.actions) ('edge ${edge.edgeId}', action),
    ];
    sections
      ..add(KeyValueSection('order', 'Order', [
        InterpretedValue('Order id', order.orderId),
        InterpretedValue('Order update id', '${order.orderUpdateId}'),
      ]))
      ..add(TableSection('route', 'Route', const ['Sequence', 'Kind', 'Id', 'Released', 'Position / speed', 'Actions'], rows));
    if (actions.isNotEmpty) {
      sections.add(TableSection('actions', 'Actions', const ['Where', 'Type', 'Id', 'Blocking', 'Parameters'], [
        for (var (where, action) in actions) InterpretedRow([where, action.actionType, action.actionId, action.blockingType, _parameters(action)])
      ]));
    }
    var base = nodes.where((node) => node.released).length;
    return [
      'order ${order.orderId}#${order.orderUpdateId}',
      '${nodes.length} nodes ($base base, ${nodes.length - base} horizon)',
      '${actions.length} ${actions.length == 1 ? 'action' : 'actions'}',
    ].join(' | ');
  }

  String _instantActions(VdaInstantActions instant) {
    sections.add(TableSection('actions', 'Actions', const ['Type', 'Id', 'Blocking', 'Parameters'], [
      for (var action in instant.actions) InterpretedRow([action.actionType, action.actionId, action.blockingType, _parameters(action)])
    ]));
    return instant.actions.map((action) => action.actionType).join(', ');
  }

  static String _parameters(VdaAction action) =>
      action.parameters.map((parameter) => '${parameter.key}=${parameter.value}').join(', ');

  String _visualization(VdaVisualization visualization) {
    _position(visualization.position, visualization.velocity);
    _paths(visualization.plannedPath, visualization.intermediatePath);
    var reference = visualization.referenceStateHeaderId;
    if (reference != null) {
      var state = context.lastData(topic.deviceKey, VdaTopic.state);
      var stateId = state is Map ? state['headerId'] : null;
      sections.add(KeyValueSection('reference', 'Based on', [
        InterpretedValue('State header id',
            stateId == null ? '$reference' : (stateId == reference ? '$reference (the last state)' : '$reference (an older state)')),
      ]));
    }
    var position = visualization.position;
    var velocity = visualization.velocity;
    var speed = velocity == null ? null : sqrt(pow(velocity.vx ?? 0, 2) + pow(velocity.vy ?? 0, 2));
    return [
      if (position != null) 'x ${_n(position.x, 2)} y ${_n(position.y, 2)} θ ${_n(position.theta * 180 / pi, 0)}°',
      if (speed != null) '${_n(speed, 2)} m/s',
      if (position != null) position.mapId,
    ].join(' | ');
  }

  String _connection(VdaConnection connection) {
    var state = connection.connectionState;
    var stateLevel = switch (state) {
      VdaConnectionState.connectionBroken => InterpretationLevel.error,
      VdaConnectionState.offline => InterpretationLevel.warning,
      _ => InterpretationLevel.none,
    };
    _raise(stateLevel);
    sections.add(KeyValueSection('connection', 'Connection', [InterpretedValue('State', state, level: stateLevel)]));
    return state;
  }

  String _factsheet(VdaFactsheet factsheet) {
    sections
      ..add(KeyValueSection('type', 'Type', [
        InterpretedValue('Series', factsheet.seriesName),
        if (factsheet.seriesDescription != null) InterpretedValue('Description', factsheet.seriesDescription!),
        InterpretedValue('Kinematics', factsheet.kinematics),
        InterpretedValue('Class', factsheet.robotClass),
        InterpretedValue('Maximum load', '${_n(factsheet.maximumLoadMass, 1)} kg'),
        InterpretedValue('Localization', factsheet.localizationTypes.join(', ')),
        InterpretedValue('Navigation', factsheet.navigationTypes.join(', ')),
      ]))
      ..add(KeyValueSection('physical', 'Physical parameters', [
        InterpretedValue('Speed', '${_n(factsheet.minimumSpeed, 2)} to ${_n(factsheet.maximumSpeed, 2)} m/s'),
        InterpretedValue('Acceleration', '${_n(factsheet.maximumAcceleration, 2)} m/s²'),
        InterpretedValue('Deceleration', '${_n(factsheet.maximumDeceleration, 2)} m/s²'),
        InterpretedValue('Height', '${_n(factsheet.minimumHeight, 2)} to ${_n(factsheet.maximumHeight, 2)} m'),
        InterpretedValue('Size', '${_n(factsheet.width, 2)} × ${_n(factsheet.length, 2)} m'),
      ]))
      ..add(TableSection('robotActions', 'Actions', const ['Type', 'Scopes'], [
        for (var action in factsheet.actions) InterpretedRow([action.actionType, action.scopes.join(', ')])
      ]));
    return [
      factsheet.seriesName,
      factsheet.kinematics,
      'max ${_n(factsheet.maximumSpeed, 2)} m/s',
    ].join(' | ');
  }

  String _zoneSet(VdaZoneSet zoneSet) {
    sections
      ..add(KeyValueSection('zoneSet', 'Zone set', [
        InterpretedValue('Zone set id', zoneSet.zoneSetId),
        InterpretedValue('Map', zoneSet.mapId),
        if (zoneSet.descriptor != null) InterpretedValue('Descriptor', zoneSet.descriptor!),
      ]))
      ..add(TableSection('zones', 'Zones', const ['Id', 'Type', 'Descriptor', 'Vertices', 'Parameters'], [
        for (var zone in zoneSet.zones)
          InterpretedRow([
            zone.zoneId,
            zone.zoneType,
            zone.descriptor ?? '',
            '${zone.vertices.length}',
            zone.parameters.entries.map((entry) => '${entry.key}=${entry.value}').join(', '),
          ])
      ]));
    return 'zone set ${zoneSet.zoneSetId} | ${zoneSet.mapId} | ${zoneSet.zones.length} zones';
  }

  String _responses(VdaResponses responses) {
    var requests = <String, String>{};
    var state = context.lastData(topic.deviceKey, VdaTopic.state);
    if (state is Map) {
      var read = Vda5050Reader.read(VdaTopic.state, state.map((key, value) => MapEntry('$key', value))) as VdaState;
      for (var request in read.zoneRequests) {
        requests[request.requestId] = '${request.requestType} zone ${request.zoneId}';
      }
      for (var request in read.edgeRequests) {
        requests[request.requestId] = '${request.requestType} edge ${request.edgeId}';
      }
    }
    var rows = <InterpretedRow>[];
    for (var response in responses.responses) {
      var refused = response.grantType == VdaGrantType.rejected || response.grantType == VdaGrantType.revoked;
      if (refused) {
        _raise(InterpretationLevel.warning);
      }
      rows.add(InterpretedRow([
        response.requestId,
        response.grantType,
        response.leaseExpiry == null ? '' : const Vda5050Writer(VdaVersion.v3).timestamp(response.leaseExpiry!),
        requests[response.requestId] ?? '',
      ], level: refused ? InterpretationLevel.warning : InterpretationLevel.none));
    }
    sections.add(TableSection('responses', 'Responses', const ['Request', 'Grant', 'Lease expiry', 'Request in the state'], rows));
    return responses.responses.map((response) => '${response.requestId} ${response.grantType}').join(', ');
  }

  // ---------- helpers ----------

  static InterpretationLevel _errorLevel(String errorLevel) => switch (errorLevel) {
        VdaErrorLevel.fatal || VdaErrorLevel.critical => InterpretationLevel.error,
        _ => InterpretationLevel.warning,
      };

  static String _yesNo(bool value) => value ? 'yes' : 'no';

  // a number with at most the given digits, without trailing zeros
  static String _n(double value, int digits) {
    var text = value.toStringAsFixed(digits);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return text == '-0' ? '0' : text;
  }
}
