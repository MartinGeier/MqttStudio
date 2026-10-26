import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/common/utils/payload_decoder.dart';

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

Uint8List hex(String text) =>
    Uint8List.fromList([for (var i = 0; i < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16)]);

void main() {
  group('PayloadDecoding hex', () {
    test('dumps offset, bytes and ASCII', () {
      var dump = PayloadDecoding.hexDump(Uint8List.fromList(utf8.encode('{"a":1}\n')), bytesPerLine: 8);

      expect(dump, '00000000  7b 22 61 22  3a 31 7d 0a  |{"a":1}.|');
    });

    test('pads the last line', () {
      var dump = PayloadDecoding.hexDump(bytes(List.generate(18, (i) => i + 0x41)));

      expect(dump.split('\n'), [
        '00000000  41 42 43 44 45 46 47 48  49 4a 4b 4c 4d 4e 4f 50  |ABCDEFGHIJKLMNOP|',
        '00000010  51 52                                             |QR|',
      ]);
    });

    test('dumps at most maxBytes', () {
      expect(PayloadDecoding.hexDump(bytes(List.filled(64, 0)), maxBytes: 16).split('\n').length, 1);
    });
  });

  group('PayloadDecoding text and JSON', () {
    test('parses JSON objects and arrays', () {
      var decoded = PayloadDecoding.decode(Uint8List.fromList(utf8.encode(' {"a":[1,2]}')), PayloadDecoder.auto);

      expect(decoded.hasValue, isTrue);
      expect(decoded.value, {
        'a': [1, 2]
      });
      expect(decoded.comparable, decoded.value);
    });

    test('compares other payloads as text', () {
      var decoded = PayloadDecoding.decode(Uint8List.fromList(utf8.encode('42')), PayloadDecoder.text);

      expect(decoded.hasValue, isFalse);
      expect(decoded.comparable, '42');
    });

    test('knows UTF-8', () {
      expect(PayloadDecoding.isUtf8(utf8.encode('Grüße')), isTrue);
      expect(PayloadDecoding.isUtf8([0xff, 0xfe]), isFalse);
    });
  });

  group('PayloadDecoding Base64', () {
    test('decodes standard and URL-safe text without padding', () {
      var standard = PayloadDecoding.decode(Uint8List.fromList(utf8.encode('eyJhIjoxfQ==')), PayloadDecoder.base64);
      var urlSafe = PayloadDecoding.decode(Uint8List.fromList(utf8.encode('-_8')), PayloadDecoder.base64);

      expect(standard.value, {'a': 1});
      expect(urlSafe.bytes, [0xfb, 0xff]);
    });

    test('reports other text', () {
      var decoded = PayloadDecoding.decode(Uint8List.fromList(utf8.encode('not base64!')), PayloadDecoder.base64);

      expect(decoded.error, isNotNull);
    });
  });

  group('PayloadDecoding gzip', () {
    test('unpacks gzip and zlib', () {
      var data = utf8.encode('{"temp":21.5}');

      var gzip = PayloadDecoding.decode(GZipEncoder().encodeBytes(data), PayloadDecoder.gzip);
      var zlib = PayloadDecoding.decode(ZLibEncoder().encodeBytes(data), PayloadDecoder.gzip);

      expect(gzip.value, {'temp': 21.5});
      expect(zlib.value, {'temp': 21.5});
    });

    test('reports data that is not compressed or damaged', () {
      var damaged = GZipEncoder().encodeBytes(utf8.encode('x' * 100)).sublist(0, 14);

      expect(PayloadDecoding.decode(Uint8List.fromList(utf8.encode('plain')), PayloadDecoder.gzip).error, isNotNull);
      expect(PayloadDecoding.decode(damaged, PayloadDecoder.gzip).error, isNotNull);
    });
  });

  group('PayloadDecoding MessagePack', () {
    test('decodes maps, arrays, strings and numbers', () {
      // {"compact": true, "schema": 0, "values": [-1, 300, 1.5, null, "x"]}
      var payload = hex('83a7636f6d70616374c3a6736368656d6100a676616c75657395ffcd012ccb3ff8000000000000c0a178');

      expect(PayloadDecoding.decodeMessagePack(payload), {
        'compact': true,
        'schema': 0,
        'values': [-1, 300, 1.5, null, 'x'],
      });
    });

    test('decodes wide integers, binary data and timestamps', () {
      expect(PayloadDecoding.decodeMessagePack(hex('d3fffffffffffffffe')), -2);
      expect(PayloadDecoding.decodeMessagePack(hex('cf0000000100000000')), 4294967296);
      expect(PayloadDecoding.toJsonCompatible(PayloadDecoding.decodeMessagePack(hex('c4020aff'))), '0x0aff');
      expect(PayloadDecoding.decodeMessagePack(hex('d6ff5f5e1000')), DateTime.utc(2020, 9, 13, 12, 26, 40));
    });

    test('reports truncated data and trailing bytes', () {
      expect(() => PayloadDecoding.decodeMessagePack(hex('92 01'.replaceAll(' ', ''))), throwsFormatException);
      expect(() => PayloadDecoding.decodeMessagePack(hex('0101')), throwsFormatException);
      expect(() => PayloadDecoding.decodeMessagePack(hex('c1')), throwsFormatException);
    });

    test('shows the data as JSON', () {
      var decoded = PayloadDecoding.decode(hex('81a161c4020aff'), PayloadDecoder.messagePack);

      expect(decoded.value, {'a': '0x0aff'});
    });
  });

  group('PayloadDecoding CBOR', () {
    // examples from RFC 8949 appendix A
    test('decodes the examples of the RFC', () {
      expect(PayloadDecoding.decodeCbor(hex('1903e8')), 1000);
      expect(PayloadDecoding.decodeCbor(hex('3863')), -100);
      expect(PayloadDecoding.decodeCbor(hex('f93c00')), 1.0);
      expect(PayloadDecoding.decodeCbor(hex('f9c400')), -4.0);
      expect(PayloadDecoding.decodeCbor(hex('fb3ff199999999999a')), 1.1);
      expect(PayloadDecoding.decodeCbor(hex('f5')), true);
      expect(PayloadDecoding.decodeCbor(hex('f6')), null);
      expect(PayloadDecoding.decodeCbor(hex('6449455446')), 'IETF');
      expect(PayloadDecoding.decodeCbor(hex('83010203')), [1, 2, 3]);
      expect(PayloadDecoding.decodeCbor(hex('a26161016162820203')), {
        'a': 1,
        'b': [2, 3]
      });
    });

    test('decodes indefinite lengths', () {
      expect(PayloadDecoding.decodeCbor(hex('9f018202039f0405ffff')), [
        1,
        [2, 3],
        [4, 5]
      ]);
      expect(PayloadDecoding.decodeCbor(hex('7f657374726561646d696e67ff')), 'streaming');
      expect(PayloadDecoding.decodeCbor(hex('bf61610161629f0203ffff')), {
        'a': 1,
        'b': [2, 3]
      });
    });

    test('decodes dates and big numbers', () {
      expect(PayloadDecoding.decodeCbor(hex('c11a514b67b0')), DateTime.utc(2013, 3, 21, 20, 4));
      expect(PayloadDecoding.decodeCbor(hex('c249010000000000000000')), BigInt.parse('18446744073709551616'));
    });

    test('reports invalid data', () {
      expect(() => PayloadDecoding.decodeCbor(hex('ff')), throwsFormatException);
      expect(() => PayloadDecoding.decodeCbor(hex('8301')), throwsFormatException);
      expect(() => PayloadDecoding.decodeCbor(hex('0101')), throwsFormatException);
    });

    test('shows the data as JSON', () {
      var decoded = PayloadDecoding.decode(hex('a1016161'), PayloadDecoder.cbor);

      expect(decoded.value, {'1': 'a'});
      expect(PayloadDecoding.decode(hex('ff'), PayloadDecoder.cbor).error, isNotNull);
    });
  });
}
