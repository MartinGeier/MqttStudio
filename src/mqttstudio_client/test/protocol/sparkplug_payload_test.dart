import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';

SpbPayload roundTrip(SpbPayload payload) => SparkplugReader.read(SparkplugWriter.write(payload));

SpbMetric metric(String name, SpbDataType type, Object? value) =>
    SpbMetric(name: name, datatype: type.code, value: value);

List<int> _varint(int value) {
  var bytes = <int>[];
  for (; value >= 128; value ~/= 128) {
    bytes.add(value % 128 | 0x80);
  }
  return bytes..add(value);
}

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

  group('64 bit values', () {
    test('the halves give exact values on the native VM and the web', () {
      var minusFive = SpbInt64(0xfffffffb, 0xffffffff);
      for (var web in [false, true]) {
        expect(minusFive.signed(web: web), -5);
        expect(minusFive.unsigned(web: web), BigInt.parse('18446744073709551611'));
        expect(SpbInt64(0, 0x80000000).signed(web: web), web ? BigInt.from(-9223372036854775808) : -9223372036854775808);
        expect(SpbInt64(0xffffffff, 0x001fffff).signed(web: web), 9007199254740991);
        expect(SpbInt64(0x00000001, 0xffe00000).signed(web: web), -9007199254740991);
      }
      // above 2^53 the web needs a BigInt, the native VM doesn't
      expect(SpbInt64(1, 0x00200000).signed(web: true), BigInt.parse('9007199254740993'));
      expect(SpbInt64(1, 0x00200000).signed(web: false), 9007199254740993);
      expect(SpbInt64(1, 0x00200000).unsigned(web: true), BigInt.parse('9007199254740993'));
      expect(SpbInt64(1, 0x7fffffff).unsigned(web: false), 0x7fffffff00000001);
      expect(SpbInt64(1, 0x80000000).unsigned(web: false), BigInt.parse('9223372036854775809'));
    });

    test('the halves of ints and BigInts', () {
      SpbInt64 bits(Object value) => SpbInt64.of(value);
      expect([bits(-5).low, bits(-5).high], [0xfffffffb, 0xffffffff]);
      expect([bits(0x123456789).low, bits(0x123456789).high], [0x23456789, 1]);
      var big = bits(BigInt.parse('18446744073709551611'));
      expect([big.low, big.high], [0xfffffffb, 0xffffffff]);
      expect([bits(BigInt.from(-5)).low, bits(BigInt.from(-5)).high], [0xfffffffb, 0xffffffff]);
    });

    // a metric "a" with the data type and a value field of ten varint bytes: -5 sign-extended to 64 bits
    Uint8List signExtended(SpbDataType? type, {int field = 11}) {
      var minusFive = [0xfb, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01];
      var metric = [0x0a, 0x01, 0x61, if (type != null) ...[0x20, type.code], field * 8, ...minusFive];
      return Uint8List.fromList([0x12, metric.length, ...metric]);
    }

    test('negative values in ten bytes', () {
      expect(SparkplugReader.read(signExtended(SpbDataType.int64)).metrics.single.value, -5);
      expect(SparkplugReader.read(signExtended(SpbDataType.int32)).metrics.single.value, -5);
      expect(SparkplugReader.read(signExtended(SpbDataType.int16)).metrics.single.value, -5);
      expect(SparkplugReader.read(signExtended(SpbDataType.int8)).metrics.single.value, -5);
      // int_value, as Protobuf writers sign-extend int32
      expect(SparkplugReader.read(signExtended(SpbDataType.int32, field: 10)).metrics.single.value, -5);
      expect(roundTrip(SpbPayload(metrics: [metric('i64', SpbDataType.int64, -5)])).metrics.single.value, -5);
    });

    test('retype reads unsigned values and BigInts as the type of the birth', () {
      var data = SparkplugReader.read(signExtended(null)).metrics.single;
      expect(data.value, BigInt.parse('18446744073709551611'));
      for (var (type, expected) in [
        (SpbDataType.int32, -5),
        (SpbDataType.int8, -5),
        (SpbDataType.int64, -5),
        (SpbDataType.boolean, true),
      ]) {
        var metric = SparkplugReader.read(signExtended(null)).metrics.single;
        SparkplugReader.retype(metric, type);
        expect(metric.value, expected, reason: type.label);
        // again changes nothing
        SparkplugReader.retype(metric, type);
        expect(metric.value, expected, reason: type.label);
      }
      var unsigned = SpbMetric(value: 4294967291);
      SparkplugReader.retype(unsigned, SpbDataType.int32);
      expect(unsigned.value, -5);
    });
  });

  test('a time out of the DateTime range stays a number', () {
    var nanoseconds = 1761552000000000000;
    var payload = roundTrip(
      SpbPayload(
        timestamp: nanoseconds,
        metrics: [
          metric('t', SpbDataType.dateTime, nanoseconds),
          metric(
            'ts',
            SpbDataType.dateTimeArray,
            (ByteData(8)..setInt64(0, nanoseconds, Endian.little)).buffer.asUint8List(),
          ),
          SpbMetric(name: 'later', value: nanoseconds, encodeAs: SpbDataType.dateTime),
        ],
      ),
    );
    expect(payload.timestamp, nanoseconds);
    expect(payload.metrics[0].value, nanoseconds);
    expect(payload.metrics[1].value, [nanoseconds]);
    SparkplugReader.retype(payload.metrics[2], SpbDataType.dateTime);
    expect(payload.metrics[2].value, nanoseconds);
    expect(SparkplugReader.dateTimeOf(1761552000000), DateTime.utc(2025, 10, 27, 8));
  });

  test('a field longer than the payload, also near the int range', () {
    // field 2 with a length of 2^63 - 1
    var huge = Uint8List.fromList([0x12, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f]);
    expect(() => SparkplugReader.read(huge), throwsFormatException);
    var negative = Uint8List.fromList([0x12, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]);
    expect(() => SparkplugReader.read(negative), throwsFormatException);
  });

  test('templates nested too deep are rejected, not read until the stack overflows', () {
    // a metric holding a template holding a metric … 100000 times; every level is a header in front of the next, so the
    // headers are written outside in once the sizes are known
    const levels = 100000;
    var core = [0x0a, 0x01, 0x61];
    var sizes = [core.length];
    for (var i = 0; i < levels; i++) {
      var template = 1 + _varint(sizes.last).length + sizes.last;
      sizes.add(2 + _varint(template).length + template);
    }
    var bytes = <int>[0x12, ..._varint(sizes.last)];
    for (var i = levels; i > 0; i--) {
      var template = 1 + _varint(sizes[i - 1]).length + sizes[i - 1];
      bytes.addAll([0x92, 0x01, ..._varint(template), 0x12, ..._varint(sizes[i - 1])]);
    }
    bytes.addAll(core);
    expect(() => SparkplugReader.read(Uint8List.fromList(bytes)), throwsFormatException);
    var shallow = roundTrip(
      SpbPayload(
        metrics: [
          metric('t', SpbDataType.template, SpbTemplate(metrics: [metric('m', SpbDataType.int32, 1)])),
        ],
      ),
    );
    expect((shallow.metrics.single.value as SpbTemplate).metrics.single.value, 1);
  });

  test('skips fields it does not know and rejects broken payloads', () {
    // field 15 (varint) before the seq
    var payload = SparkplugReader.read(Uint8List.fromList([0x78, 0x07, 0x18, 0x04]));
    expect(payload.seq, 4);
    expect(() => SparkplugReader.read(Uint8List.fromList([0x12, 0x09, 0x0a])), throwsFormatException);
    expect(() => SparkplugReader.read(Uint8List.fromList([0x0f])), throwsFormatException);
  });
}
