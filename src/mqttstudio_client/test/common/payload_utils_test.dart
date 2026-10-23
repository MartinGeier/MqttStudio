import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/common/utils/payload_utils.dart';
import 'package:typed_data/typed_buffers.dart';
import '../helpers/test_setup.dart';

Uint8Buffer bytes(List<int> values) => Uint8Buffer()..addAll(values);

void main() {
  group('PayloadUtils.safePayloadToString', () {
    test('decodes UTF-8 including umlauts', () {
      expect(PayloadUtils.safePayloadToString(toPayload('Grüße aus Südtirol')), 'Grüße aus Südtirol');
    });

    test('decodes an empty payload', () {
      expect(PayloadUtils.safePayloadToString(Uint8Buffer()), '');
    });

    test('replaces invalid UTF-8 instead of failing', () {
      // 0xE4 is "ä" in Latin-1 but not valid UTF-8
      expect(PayloadUtils.safePayloadToString(bytes([0x4B, 0xE4, 0x73, 0x65])), 'K�se');
    });
  });

  group('PayloadUtils.tryParseCoordinates', () {
    test('parses latitude and longitude', () {
      var position = PayloadUtils.tryParseCoordinates('47.2692,11.4041')!;
      expect(position.latitude, 47.2692);
      expect(position.longitude, 11.4041);
    });

    test('accepts spaces and negative values', () {
      var position = PayloadUtils.tryParseCoordinates(' -33.8688, 151.2093 ')!;
      expect(position.latitude, -33.8688);
      expect(position.longitude, 151.2093);
    });

    test('rejects values out of range', () {
      expect(PayloadUtils.tryParseCoordinates('91,10'), isNull);
      expect(PayloadUtils.tryParseCoordinates('10,181'), isNull);
    });

    test('rejects anything that is not exactly two numbers', () {
      expect(PayloadUtils.tryParseCoordinates('47.2692'), isNull);
      expect(PayloadUtils.tryParseCoordinates('47.2692,11.4041,574'), isNull);
      expect(PayloadUtils.tryParseCoordinates('lat=47.2692,lon=11.4041'), isNull);
      expect(PayloadUtils.tryParseCoordinates('46.4983,11.3548\n47.0707,15.4395'), isNull);
      expect(PayloadUtils.tryParseCoordinates(''), isNull);
    });
  });

  group('PayloadUtils.detectPayloadType', () {
    test('detects numbers', () {
      expect(PayloadUtils.detectPayloadType(toPayload('42')), PayloadType.Number);
      expect(PayloadUtils.detectPayloadType(toPayload('-3.5')), PayloadType.Number);
    });

    test('detects JSON objects', () {
      expect(PayloadUtils.detectPayloadType(toPayload('{"temp": 21.5}')), PayloadType.Json);
      expect(PayloadUtils.detectPayloadType(toPayload('  {"a": [1, 2]}')), PayloadType.Json);
    });

    test('treats invalid JSON as text', () {
      expect(PayloadUtils.detectPayloadType(toPayload('{not json')), PayloadType.Text);
    });

    test('detects PNG and JPG images by their signature', () {
      expect(PayloadUtils.detectPayloadType(bytes([137, 80, 78, 71, 13, 10, 26, 10])), PayloadType.Image);
      expect(PayloadUtils.detectPayloadType(bytes([255, 216, 255, 224, 0, 16])), PayloadType.Image);
    });

    test('detects coordinates', () {
      expect(PayloadUtils.detectPayloadType(toPayload('47.2692,11.4041')), PayloadType.GnssCoordinates);
    });

    test('falls back to text', () {
      expect(PayloadUtils.detectPayloadType(toPayload('hello')), PayloadType.Text);
      expect(PayloadUtils.detectPayloadType(Uint8Buffer()), PayloadType.Text);
    });

    test('handles binary payloads shorter than an image signature', () {
      expect(PayloadUtils.detectPayloadType(bytes([0x89])), PayloadType.Text);
      expect(PayloadUtils.detectPayloadType(bytes([0xFF])), PayloadType.Text);
      expect(PayloadUtils.detectPayloadType(bytes([0xFF, 0xD8])), PayloadType.Text);
    });
  });
}
