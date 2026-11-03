import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/protocol/protocol_profile.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_profile.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_state.dart';

class _Context implements InterpretationContext {
  final Map<String, Object?> data;

  _Context(this.data);

  @override
  Object? lastData(String topic) => data[topic];
}

SpbMetric _metric(String name, int alias, SpbDataType type, Object? value) =>
    SpbMetric(name: name, alias: alias, datatype: type.code, value: value);

// a birth with a value of every kind, the material the mutations start from
Uint8List _birth() => SparkplugWriter.write(
  SpbPayload(
    timestamp: 1761552000000,
    seq: 0,
    uuid: 'u',
    metrics: [
      SpbMetric(name: 'bdSeq', datatype: SpbDataType.int64.code, value: 2),
      _metric('i8', 1, SpbDataType.int8, -5),
      _metric('i64', 2, SpbDataType.int64, -5000000000),
      _metric('u64', 3, SpbDataType.uInt64, BigInt.parse('18446744073709551615')),
      _metric('t', 4, SpbDataType.dateTime, DateTime.utc(2026, 11, 3)),
      _metric('d', 5, SpbDataType.double, 1.5),
      _metric('s', 6, SpbDataType.string, 'text'),
      _metric('ts', 7, SpbDataType.dateTimeArray, Uint8List(16)),
      _metric(
        'set',
        8,
        SpbDataType.dataSet,
        SpbDataSet(
          columns: ['a', 'b'],
          types: [SpbDataType.int32.code, SpbDataType.dateTime.code],
          rows: [
            [-1, 1761552000000],
          ],
        ),
      ),
      _metric(
        'tpl',
        9,
        SpbDataType.template,
        SpbTemplate(
          templateRef: 'T',
          metrics: [_metric('m', 10, SpbDataType.int16, -2)],
          parameters: [SpbParameter(name: 'p', type: SpbDataType.int64.code, value: -7)],
        ),
      ),
      SpbMetric(
        name: 'props',
        alias: 11,
        datatype: SpbDataType.boolean.code,
        value: true,
        properties: SpbPropertySet({
          'engUnit': SpbPropertyValue(type: SpbDataType.string.code, value: 'm'),
          'nested': SpbPropertyValue(
            type: SpbDataType.propertySet.code,
            value: SpbPropertySet({'q': SpbPropertyValue(type: SpbDataType.dateTime.code, value: 1)}),
          ),
        }),
      ),
    ],
  ),
);

// data by alias without data types, as edge nodes send it
Uint8List _data() => SparkplugWriter.write(
  SpbPayload(
    timestamp: 1761552001000,
    seq: 1,
    metrics: [
      SpbMetric(alias: 1, value: -6, encodeAs: SpbDataType.int64),
      SpbMetric(alias: 4, value: 1761552001000, encodeAs: SpbDataType.int64),
      SpbMetric(alias: 7, value: Uint8List(8), encodeAs: SpbDataType.bytes),
    ],
  ),
);

Uint8List _mutate(Uint8List original, Random random) {
  var bytes = Uint8List.fromList(original);
  switch (random.nextInt(4)) {
    case 0:
      for (var i = random.nextInt(4); i >= 0; i--) {
        bytes[random.nextInt(bytes.length)] = random.nextInt(256);
      }
      return bytes;
    case 1:
      // 0xff bytes make huge varints, lengths and timestamps
      var at = random.nextInt(bytes.length);
      return Uint8List.fromList([...bytes.take(at), for (var i = random.nextInt(10); i >= 0; i--) 0xff, ...bytes.skip(at)]);
    case 2:
      return Uint8List.sublistView(bytes, 0, random.nextInt(bytes.length));
    default:
      return Uint8List.fromList([for (var i = random.nextInt(64); i >= 0; i--) random.nextInt(256)]);
  }
}

// Pattern 2 of the code review of 2026-11-03: a malformed payload may only give a FormatException from the reader, and
// nothing at all from the profile, the state and the checker
void main() {
  var profile = SparkplugProfile();

  test('mutated payloads never throw anything but a FormatException', () {
    var random = Random(5050);
    var birth = _birth();
    var data = _data();
    var birthTopic = 'spBv1.0/G/NBIRTH/E';
    var topics = [birthTopic, 'spBv1.0/G/NDATA/E', 'spBv1.0/G/DDATA/E/D', 'spBv1.0/G/NDEATH/E', 'spBv1.0/G/NCMD/E'];
    var state = SparkplugState<int>();
    var checker = profile.createChecker();
    var now = DateTime.utc(2026, 11, 3);
    for (var i = 0; i < 5000; i++) {
      var bytes = _mutate(i.isEven ? birth : data, random);
      try {
        SparkplugReader.read(bytes);
      } on FormatException {
        // expected for most mutations
      }
      for (var topic in topics) {
        var match = profile.matchTopic(topic)!;
        // the last birth is a mutated one too, so data is read with broken types
        profile.interpret(match, bytes, context: _Context({birthTopic: i % 3 == 0 ? bytes : birth}));
        state.add(match, bytes, now, i);
        checker.check(topic, match, bytes, now);
      }
    }
  });
}
