import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';

SpbPayload roundTrip(SpbPayload payload) => SparkplugReader.read(SparkplugWriter.write(payload));

SpbMetric metric(String name, SpbDataType type, Object? value) =>
    SpbMetric(name: name, datatype: type.code, value: value);

void main() {
  test('reads the wire format of the specification', () {
    // timestamp 1, seq 0, one metric "a" with int_value 5 (field 10)
    var bytes = Uint8List.fromList([0x08, 0x01, 0x18, 0x00, 0x12, 0x05, 0x0a, 0x01, 0x61, 0x50, 0x05]);
    var payload = SparkplugReader.read(bytes);
    expect(payload.timestamp, 1);
    expect(payload.seq, 0);
    expect(payload.metrics.single.name, 'a');
    expect(payload.metrics.single.value, 5);
  });

  test('writes and reads every scalar type', () {
    var payload = roundTrip(
      SpbPayload(
        timestamp: 1761400000000,
        seq: 255,
        uuid: 'u-1',
        body: Uint8List.fromList([1, 2]),
        metrics: [
          metric('i8', SpbDataType.int8, -5),
          metric('i16', SpbDataType.int16, -300),
          metric('i32', SpbDataType.int32, -70000),
          metric('i64', SpbDataType.int64, -5000000000),
          metric('u32', SpbDataType.uInt32, 4000000000),
          metric('u64', SpbDataType.uInt64, 9000000000000000000),
          metric('f', SpbDataType.float, 1.5),
          metric('d', SpbDataType.double, 21.25),
          metric('b', SpbDataType.boolean, true),
          metric('s', SpbDataType.string, 'Grüße'),
          metric('t', SpbDataType.dateTime, DateTime.utc(2026, 10, 27, 8)),
          metric('raw', SpbDataType.bytes, Uint8List.fromList([9, 8, 7])),
          SpbMetric(name: 'n', datatype: SpbDataType.int32.code, isNull: true),
        ],
      ),
    );
    expect(payload.timestamp, 1761400000000);
    expect(payload.seq, 255);
    expect(payload.uuid, 'u-1');
    expect(payload.body, [1, 2]);
    var values = {for (var metric in payload.metrics) metric.name: metric.value};
    expect(values, {
      'i8': -5,
      'i16': -300,
      'i32': -70000,
      'i64': -5000000000,
      'u32': 4000000000,
      'u64': 9000000000000000000,
      'f': 1.5,
      'd': 21.25,
      'b': true,
      's': 'Grüße',
      't': DateTime.utc(2026, 10, 27, 8),
      'raw': [9, 8, 7],
      'n': null,
    });
    expect(payload.metrics.last.isNull, isTrue);
  });

  test('an UInt64 above the int range is a BigInt', () {
    var big = BigInt.parse('18446744073709551615');
    var payload = roundTrip(SpbPayload(metrics: [metric('max', SpbDataType.uInt64, big)]));
    expect(payload.metrics.single.value, big);
  });

  test('reads the arrays of 3.0 from little endian bytes', () {
    var int16 = ByteData(4)
      ..setInt16(0, -2, Endian.little)
      ..setInt16(2, 300, Endian.little);
    var doubles = ByteData(16)
      ..setFloat64(0, 1.5, Endian.little)
      ..setFloat64(8, -2, Endian.little);
    var payload = roundTrip(
      SpbPayload(
        metrics: [
          metric('i16', SpbDataType.int16Array, int16.buffer.asUint8List()),
          metric('d', SpbDataType.doubleArray, doubles.buffer.asUint8List()),
          // 3 booleans: true, false, true
          metric('b', SpbDataType.booleanArray, Uint8List.fromList([3, 0, 0, 0, 0xa0])),
          metric('s', SpbDataType.stringArray, Uint8List.fromList([0x61, 0, 0x62, 0x63, 0])),
        ],
      ),
    );
    var values = {for (var metric in payload.metrics) metric.name: metric.value};
    expect(values['i16'], [-2, 300]);
    expect(values['d'], [1.5, -2]);
    expect(values['b'], [true, false, true]);
    expect(values['s'], ['a', 'bc']);
  });

  test('properties, metadata, data sets and templates', () {
    var payload = roundTrip(
      SpbPayload(
        metrics: [
          SpbMetric(
            name: 'temp',
            alias: 3,
            datatype: SpbDataType.double.code,
            value: 21.5,
            isHistorical: true,
            metadata: SpbMetaData(contentType: 'text/plain', size: 4),
            properties: SpbPropertySet({
              'engUnit': SpbPropertyValue(type: SpbDataType.string.code, value: '°C'),
              'Quality': SpbPropertyValue(type: SpbDataType.int32.code, value: 192),
            }),
          ),
          metric(
            'table',
            SpbDataType.dataSet,
            SpbDataSet(
              columns: ['id', 'name'],
              types: [SpbDataType.int32.code, SpbDataType.string.code],
              rows: [
                [1, 'one'],
                [-2, 'two'],
              ],
            ),
          ),
          metric(
            'motor',
            SpbDataType.template,
            SpbTemplate(
              templateRef: 'Motor',
              metrics: [metric('rpm', SpbDataType.int32, 1500)],
              parameters: [SpbParameter(name: 'size', type: SpbDataType.string.code, value: 'L')],
            ),
          ),
        ],
      ),
    );
    var temp = payload.metrics[0];
    expect(temp.alias, 3);
    expect(temp.isHistorical, isTrue);
    expect(temp.metadata!.contentType, 'text/plain');
    expect(temp.properties!.values['engUnit']!.value, '°C');
    expect(temp.properties!.values['Quality']!.value, 192);
    var table = payload.metrics[1].value as SpbDataSet;
    expect(table.columns, ['id', 'name']);
    expect(table.rows, [
      [1, 'one'],
      [-2, 'two'],
    ]);
    var motor = payload.metrics[2].value as SpbTemplate;
    expect(motor.templateRef, 'Motor');
    expect(motor.metrics.single.value, 1500);
    expect(motor.parameters.single.value, 'L');
  });

  test('skips fields it does not know and rejects broken payloads', () {
    // field 15 (varint) before the seq
    var payload = SparkplugReader.read(Uint8List.fromList([0x78, 0x07, 0x18, 0x04]));
    expect(payload.seq, 4);
    expect(() => SparkplugReader.read(Uint8List.fromList([0x12, 0x09, 0x0a])), throwsFormatException);
    expect(() => SparkplugReader.read(Uint8List.fromList([0x0f])), throwsFormatException);
  });
}
