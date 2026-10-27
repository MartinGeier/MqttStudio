import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/protocol/protocol_profile.dart';
import 'package:mqttstudio/protocol/protocol_registry.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_profile.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_rules.dart';

class _Context implements InterpretationContext {
  final Map<String, Object?> data;

  _Context(this.data);

  @override
  Object? lastData(String topic) => data[topic];
}

const _time = 1761552000000;

Uint8List nodeBirth({int bdSeq = 3, int seq = 0, List<SpbMetric>? extra}) => SparkplugWriter.write(
  SpbPayload(
    timestamp: _time,
    seq: seq,
    metrics: [
      SpbMetric(name: 'bdSeq', datatype: SpbDataType.int64.code, value: bdSeq),
      SpbMetric(name: 'Node Control/Rebirth', alias: 1, datatype: SpbDataType.boolean.code, value: false),
      SpbMetric(
        name: 'Temperature',
        alias: 2,
        datatype: SpbDataType.double.code,
        value: 20.0,
        properties: SpbPropertySet({'engUnit': SpbPropertyValue(type: SpbDataType.string.code, value: '°C')}),
      ),
      SpbMetric(name: 'Running', alias: 3, datatype: SpbDataType.boolean.code, value: true),
      ...?extra,
    ],
  ),
);

// data by alias, as most edge nodes send it
Uint8List nodeData(int seq, {double temperature = 21.5, int alias = 2, int? datatype}) => SparkplugWriter.write(
  SpbPayload(
    timestamp: _time + 1000,
    seq: seq,
    metrics: [SpbMetric(alias: alias, datatype: datatype ?? SpbDataType.double.code, value: temperature)],
  ),
);

Uint8List death({int bdSeq = 3}) => SparkplugWriter.write(
  SpbPayload(
    metrics: [SpbMetric(name: 'bdSeq', datatype: SpbDataType.int64.code, value: bdSeq)],
  ),
);

Uint8List deviceMessage(int seq, {double pressure = 1.02, bool birth = false}) => SparkplugWriter.write(
  SpbPayload(
    timestamp: _time,
    seq: seq,
    metrics: [SpbMetric(name: birth ? 'Pressure' : null, alias: 10, datatype: SpbDataType.float.code, value: pressure)],
  ),
);

void main() {
  var profile = SparkplugProfile();

  group('detection', () {
    test('recognizes node, device and host topics', () {
      var data = profile.matchTopic('spBv1.0/Plant1/NDATA/Edge1')!;
      expect(data.messageType, 'NDATA');
      expect(data.deviceKey, 'Plant1/Edge1');
      expect(data.parameters, {'groupId': 'Plant1', 'edgeNodeId': 'Edge1'});
      var device = profile.matchTopic('spBv1.0/Plant1/DBIRTH/Edge1/Pump')!;
      expect(device.parameters['deviceId'], 'Pump');
      expect(
        SparkplugProfile.birthTopicOf(profile.matchTopic('spBv1.0/Plant1/DDATA/Edge1/Pump')!),
        'spBv1.0/Plant1/DBIRTH/Edge1/Pump',
      );
      expect(profile.matchTopic('spBv1.0/STATE/scada1')!.parameters['hostId'], 'scada1');
      expect(profile.matchTopic('STATE/scada1')!.messageType, 'STATE');
    });

    test('ignores other topics and wrong shapes', () {
      expect(profile.matchTopic('spBv1.0/Plant1/NDATA/Edge1/extra'), isNull);
      expect(profile.matchTopic('spBv1.0/Plant1/DDATA/Edge1'), isNull);
      expect(profile.matchTopic('spBv1.0/Plant1/XDATA/Edge1'), isNull);
      expect(profile.matchTopic('spAv1.0/Plant1/NDATA/Edge1'), isNull);
      expect(profile.matchTopic('plant/NDATA/x/y'), isNull);
    });

    test('the standard registry knows Sparkplug next to VDA 5050', () {
      var registry = ProtocolRegistry.standard();
      expect(registry.match('spBv1.0/G/NBIRTH/E')!.profile, isA<SparkplugProfile>());
      expect(registry.match('uagv/v2/Acme/R1/state')!.profile.id, 'vda5050');
    });
  });

  group('interpretation', () {
    Interpretation interpret(String topic, Object? data, [Map<String, Object?> context = const {}]) =>
        profile.interpret(profile.matchTopic(topic)!, data, context: _Context(context))!;

    test('a birth lists its metrics with types and units', () {
      var birth = interpret('spBv1.0/Plant1/NBIRTH/Edge1', nodeBirth());
      expect(birth.protocolVersion, 'B');
      expect(birth.summary, 'BIRTH | edge node Edge1 | 4 metrics | bdSeq 3 | seq 0');
      var metrics = birth.sections.whereType<TableSection>().single;
      expect(metrics.title, 'Metrics (4)');
      var temperature = metrics.rows.firstWhere((row) => row.cells[0] == 'Temperature');
      expect(temperature.cells, ['Temperature', '2', 'Double', '20 °C', '']);
      expect(birth.values, {'bdSeq': 3, 'Node Control/Rebirth': 0, 'Temperature': 20, 'Running': 1});
    });

    test('data by alias takes names, types and units from the last birth', () {
      var data = interpret('spBv1.0/Plant1/NDATA/Edge1', nodeData(1), {'spBv1.0/Plant1/NBIRTH/Edge1': nodeBirth()});
      expect(data.summary, 'Edge1 | Temperature = 21.5 °C | seq 1');
      expect(data.values, {'Temperature': 21.5});
      var row = data.sections.whereType<TableSection>().single.rows.single;
      expect(row.cells.take(4), ['Temperature', '2', 'Double', '21.5 °C']);
    });

    test('values sent without a data type are read as the type of the birth', () {
      var birth = nodeBirth(
        extra: [SpbMetric(name: 'Offset', alias: 7, datatype: SpbDataType.int32.code, value: 0)],
      );
      var data = SparkplugWriter.write(
        SpbPayload(
          timestamp: _time,
          seq: 1,
          metrics: [SpbMetric(alias: 7, value: -5, encodeAs: SpbDataType.int32)],
        ),
      );
      // without the birth the bits read as an unsigned number
      expect(SparkplugReader.read(data).metrics.single.value, 4294967291);
      var interpreted = interpret('spBv1.0/Plant1/NDATA/Edge1', data, {'spBv1.0/Plant1/NBIRTH/Edge1': birth});
      expect(interpreted.summary, 'Edge1 | Offset = -5 | seq 1');
      expect(interpreted.values, {'Offset': -5});
    });

    test('without the birth the metrics are shown by alias', () {
      var data = interpret('spBv1.0/Plant1/NDATA/Edge1', nodeData(1));
      expect(data.summary, 'Edge1 | alias 2 = 21.5 | seq 1');
      var header = data.sections.whereType<KeyValueSection>().first;
      expect(header.values.last.label, 'Metric names');
      expect(header.values.last.level, InterpretationLevel.warning);
    });

    test('device messages, deaths and commands', () {
      var context = {'spBv1.0/Plant1/DBIRTH/Edge1/Pump': deviceMessage(1, birth: true)};
      expect(
        interpret('spBv1.0/Plant1/DDATA/Edge1/Pump', deviceMessage(2), context).summary,
        'Pump | Pressure = 1.02 | seq 2',
      );
      expect(
        interpret('spBv1.0/Plant1/DBIRTH/Edge1/Pump', deviceMessage(1, birth: true)).summary,
        'BIRTH | device Pump on Edge1 | 1 metric | seq 1',
      );
      var nodeDeath = interpret('spBv1.0/Plant1/NDEATH/Edge1', death());
      expect(nodeDeath.summary, 'DEATH | edge node Edge1 | bdSeq 3');
      expect(nodeDeath.level, InterpretationLevel.warning);
      var rebirth = SparkplugWriter.write(
        SpbPayload(
          timestamp: _time,
          metrics: [SpbMetric(name: 'Node Control/Rebirth', datatype: SpbDataType.boolean.code, value: true)],
        ),
      );
      expect(interpret('spBv1.0/Plant1/NCMD/Edge1', rebirth).summary, 'COMMAND to Edge1 | Node Control/Rebirth = true');
    });

    test('data sets and templates get tables of their own', () {
      var payload = SparkplugWriter.write(
        SpbPayload(
          timestamp: _time,
          seq: 2,
          metrics: [
            SpbMetric(
              name: 'Orders',
              datatype: SpbDataType.dataSet.code,
              value: SpbDataSet(
                columns: ['id', 'qty'],
                types: [SpbDataType.string.code, SpbDataType.int32.code],
                rows: [
                  ['A1', 5],
                ],
              ),
            ),
          ],
        ),
      );
      var data = interpret('spBv1.0/Plant1/NDATA/Edge1', payload);
      var table = data.sections.whereType<TableSection>().firstWhere((section) => section.key == 'dataset:Orders');
      expect(table.columns, ['id', 'qty']);
      expect(table.rows.single.cells, ['A1', '5']);
      expect(data.summary, 'Edge1 | Orders = DataSet 1 × 2 | seq 2');
    });

    test('host state in the 3.0 JSON and the 2.2 text', () {
      var online = interpret('spBv1.0/STATE/scada1', {'online': true, 'timestamp': _time});
      expect(online.summary, 'Host scada1 | ONLINE');
      var offline = interpret('STATE/scada1', Uint8List.fromList(utf8.encode('OFFLINE')));
      expect(offline.summary, 'Host scada1 | OFFLINE');
      expect(offline.level, InterpretationLevel.warning);
      expect(profile.interpret(profile.matchTopic('STATE/x')!, Uint8List.fromList(utf8.encode('hello'))), isNull);
    });

    test('a compressed payload is read from its body', () {
      var compressed = SparkplugWriter.write(
        SpbPayload(
          uuid: SparkplugProfile.compressedUuid,
          body: Uint8List.fromList(GZipEncoder().encode(nodeData(4))),
          metrics: [SpbMetric(name: 'algorithm', datatype: SpbDataType.string.code, value: 'GZIP')],
        ),
      );
      var data = interpret('spBv1.0/Plant1/NDATA/Edge1', compressed, {'spBv1.0/Plant1/NBIRTH/Edge1': nodeBirth()});
      expect(data.summary, 'Edge1 | Temperature = 21.5 °C | seq 4');
      var header = data.sections.whereType<KeyValueSection>().first.values;
      expect(header.firstWhere((value) => value.label == 'Compression').value, 'GZIP');
    });

    test('a payload that is not Sparkplug says why', () {
      var broken = interpret('spBv1.0/Plant1/NDATA/Edge1', Uint8List.fromList([0x12, 0x09, 0x0a]));
      expect(broken.level, InterpretationLevel.error);
      expect(broken.summary, startsWith('Not a Sparkplug B payload'));
      expect(profile.interpret(profile.matchTopic('spBv1.0/Plant1/NDATA/Edge1')!, {'json': true}), isNull);
    });
  });

  group('rules', () {
    late ProtocolChecker checker;
    var now = DateTime.utc(2026, 10, 27, 8);

    setUp(() => checker = profile.createChecker());

    List<String> check(String topic, Object? data) =>
        checker.check(topic, profile.matchTopic(topic)!, data, now).map((finding) => finding.rule).toList();

    test('a clean session has no findings', () {
      expect(check('spBv1.0/G/NBIRTH/E', nodeBirth(seq: 250)), isEmpty);
      for (var seq = 251; seq < 260; seq++) {
        expect(check('spBv1.0/G/NDATA/E', nodeData(seq % 256)), isEmpty, reason: 'seq $seq');
      }
      expect(check('spBv1.0/G/DBIRTH/E/Pump', deviceMessage(4, birth: true)), isEmpty);
      expect(check('spBv1.0/G/DDATA/E/Pump', deviceMessage(5)), isEmpty);
      expect(check('spBv1.0/G/NDEATH/E', death()), isEmpty);
      expect(check('spBv1.0/G/NBIRTH/E', nodeBirth(bdSeq: 4)), isEmpty);
    });

    test('sequence numbers', () {
      check('spBv1.0/G/NBIRTH/E', nodeBirth());
      expect(check('spBv1.0/G/NDATA/E', nodeData(1)), isEmpty);
      expect(check('spBv1.0/G/NDATA/E', nodeData(3)), [SparkplugRules.seqGap]);
      expect(check('spBv1.0/G/NDATA/E', SparkplugWriter.write(SpbPayload(timestamp: _time))), [
        SparkplugRules.seqMissing,
      ]);
      expect(check('spBv1.0/G/NDATA/E', SparkplugWriter.write(SpbPayload(seq: 4))), [SparkplugRules.timestampMissing]);
    });

    test('a check that starts while the node is online waits for its birth', () {
      expect(check('spBv1.0/G/NDATA/E', nodeData(17)), isEmpty);
      expect(check('spBv1.0/G/NDATA/E', nodeData(18, alias: 99)), isEmpty);
      expect(check('spBv1.0/G/DDATA/E/Pump', deviceMessage(19)), isEmpty);
    });

    test('births and deaths', () {
      expect(check('spBv1.0/G/NBIRTH/E', SparkplugWriter.write(SpbPayload(timestamp: _time, seq: 0))), [
        SparkplugRules.bdSeqMissing,
      ]);
      check('spBv1.0/G/NBIRTH/E', nodeBirth(bdSeq: 7));
      expect(check('spBv1.0/G/NDEATH/E', death(bdSeq: 6)), [SparkplugRules.bdSeqMismatch]);
      expect(check('spBv1.0/G/NDATA/E', nodeData(1)), [SparkplugRules.afterDeath]);
      var badBirth = nodeBirth(
        extra: [
          SpbMetric(name: 'NoType', value: 1),
          SpbMetric(name: 'Twin', alias: 2, datatype: SpbDataType.int32.code, value: 1),
        ],
      );
      expect(check('spBv1.0/G/NBIRTH/E', badBirth), [SparkplugRules.datatypeMissing, SparkplugRules.duplicateAlias]);
    });

    test('metrics the birth does not define', () {
      check('spBv1.0/G/NBIRTH/E', nodeBirth());
      expect(check('spBv1.0/G/NDATA/E', nodeData(1, alias: 42)), [SparkplugRules.unknownMetric]);
      expect(check('spBv1.0/G/NDATA/E', nodeData(2, datatype: SpbDataType.float.code)), [
        SparkplugRules.datatypeMismatch,
      ]);
    });

    test('device data needs the device birth', () {
      check('spBv1.0/G/NBIRTH/E', nodeBirth());
      expect(check('spBv1.0/G/DDATA/E/Pump', deviceMessage(1)), [SparkplugRules.deviceNotBorn]);
      check('spBv1.0/G/DBIRTH/E/Pump', deviceMessage(2, birth: true));
      check('spBv1.0/G/DDEATH/E/Pump', deviceMessage(3));
      expect(check('spBv1.0/G/DDATA/E/Pump', deviceMessage(4)), [SparkplugRules.deviceNotBorn]);
    });

    test('payloads that are not Protobuf', () {
      expect(check('spBv1.0/G/NDATA/E', {'temperature': 21}), [SparkplugRules.payload]);
      expect(check('spBv1.0/G/NDATA/E', Uint8List.fromList([0x12, 0x09])), [SparkplugRules.payload]);
      expect(check('spBv1.0/STATE/host', {'online': true}), isEmpty);
    });
  });
}
