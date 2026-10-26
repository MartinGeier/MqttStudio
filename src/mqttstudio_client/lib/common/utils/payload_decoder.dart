import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';

// How the message detail view shows a payload. auto picks a viewer by the content (PayloadUtils.detectPayloadType).
enum PayloadDecoder { auto, text, hex, base64, gzip, messagePack, cbor }

// A payload after decoding: the bytes for the viewers (unpacked for base64 and gzip) and, for JSON, MessagePack and
// CBOR, the decoded data. error is set when the payload isn't what the decoder expects.
class DecodedPayload {
  final Uint8List bytes;
  final Object? value;
  final bool hasValue;
  final String? error;

  const DecodedPayload(this.bytes, {this.value, this.hasValue = false, this.error});

  // the data to compare: decoded data or JSON, otherwise the text
  Object? get comparable => hasValue ? value : utf8.decode(bytes, allowMalformed: true);
}

class PayloadDecoding {
  static const int maxHexDumpBytes = 64 * 1024;
  static const int _maxDepth = 200;

  static DecodedPayload decode(Uint8List payload, PayloadDecoder decoder) {
    try {
      switch (decoder) {
        case PayloadDecoder.auto:
        case PayloadDecoder.text:
        case PayloadDecoder.hex:
          return _withJson(payload);
        case PayloadDecoder.base64:
          return _withJson(decodeBase64(payload));
        case PayloadDecoder.gzip:
          return _withJson(gunzip(payload));
        case PayloadDecoder.messagePack:
          return DecodedPayload(payload, value: toJsonCompatible(decodeMessagePack(payload)), hasValue: true);
        case PayloadDecoder.cbor:
          return DecodedPayload(payload, value: toJsonCompatible(decodeCbor(payload)), hasValue: true);
      }
      // ArchiveException is a FormatException too
    } on FormatException catch (exc) {
      return DecodedPayload(payload, error: exc.message);
    }
  }

  // JSON objects and arrays become the value
  static DecodedPayload _withJson(Uint8List bytes) {
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      return DecodedPayload(bytes);
    }
    var trimmed = text.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        return DecodedPayload(bytes, value: jsonDecode(text), hasValue: true);
      } on FormatException {
        // shown as text
      }
    }
    return DecodedPayload(bytes);
  }

  static bool isUtf8(List<int> bytes) {
    try {
      utf8.decode(bytes);
      return true;
    } on FormatException {
      return false;
    }
  }

  // offset, the bytes in hex and as ASCII per line, like hexdump -C
  static String hexDump(Uint8List bytes, {int bytesPerLine = 16, int maxBytes = maxHexDumpBytes}) {
    var shown = min(bytes.length, maxBytes);
    var text = StringBuffer();
    for (var offset = 0; offset < shown; offset += bytesPerLine) {
      var end = min(offset + bytesPerLine, shown);
      text.write(offset.toRadixString(16).padLeft(8, '0'));
      text.write('  ');
      for (var i = offset; i < offset + bytesPerLine; i++) {
        text.write(i < end ? bytes[i].toRadixString(16).padLeft(2, '0') : '  ');
        text.write(i == offset + bytesPerLine ~/ 2 - 1 ? '  ' : ' ');
      }
      text.write(' |');
      for (var i = offset; i < end; i++) {
        var byte = bytes[i];
        text.write(byte >= 0x20 && byte < 0x7f ? String.fromCharCode(byte) : '.');
      }
      text.write('|');
      if (end < shown) {
        text.write('\n');
      }
    }
    return text.toString();
  }

  // standard and URL-safe alphabet, padding and white space are optional
  static Uint8List decodeBase64(Uint8List payload) {
    var text = utf8.decode(payload, allowMalformed: true).replaceAll(RegExp(r'\s'), '');
    if (text.isEmpty) {
      throw FormatException('The payload is empty');
    }
    try {
      return base64.decode(base64.normalize(text.replaceAll('-', '+').replaceAll('_', '/')));
    } on FormatException {
      throw FormatException('The payload is no Base64 text');
    }
  }

  // gzip, or zlib (deflate with a zlib header)
  static Uint8List gunzip(Uint8List payload) {
    var isGzip = payload.length >= 2 && payload[0] == 0x1f && payload[1] == 0x8b;
    var isZlib = payload.length >= 2 && (payload[0] & 0x0f) == 8 && ((payload[0] << 8) | payload[1]) % 31 == 0;
    if (!isGzip && !isZlib) {
      throw FormatException('The payload is no gzip or zlib data');
    }
    Uint8List data;
    try {
      data = isGzip ? GZipDecoder().decodeBytes(payload, verify: true) : ZLibDecoder().decodeBytes(payload, verify: true);
    } on FormatException {
      rethrow;
    } catch (_) {
      // the decoders run past the end of damaged data
      throw FormatException('The compressed data is damaged');
    }
    // the decoders return what they could unpack of truncated data, the checksum at the end tells
    if (!(isGzip ? _hasGzipTrailer(payload, data) : _hasZlibTrailer(payload, data))) {
      throw FormatException('The compressed data is damaged or incomplete');
    }
    return data;
  }

  // CRC-32 and size, little endian
  static bool _hasGzipTrailer(Uint8List payload, Uint8List data) {
    if (payload.length < 18) {
      return false;
    }
    var trailer = ByteData.sublistView(payload, payload.length - 8);
    return trailer.getUint32(0, Endian.little) == getCrc32(data) &&
        trailer.getUint32(4, Endian.little) == data.length & 0xffffffff;
  }

  // Adler-32, big endian
  static bool _hasZlibTrailer(Uint8List payload, Uint8List data) {
    if (payload.length < 6) {
      return false;
    }
    return ByteData.sublistView(payload, payload.length - 4).getUint32(0) == getAdler32(data);
  }

  // byte arrays become hex text, map keys text and dates ISO 8601 text, so JSON viewers and the diff can show them
  static Object? toJsonCompatible(Object? value) {
    if (value is Uint8List) {
      return value.isEmpty ? '' : '0x${value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is BigInt) {
      return value.toString();
    }
    if (value is Map) {
      return {for (var entry in value.entries) _keyText(entry.key): toJsonCompatible(entry.value)};
    }
    if (value is List) {
      return [for (var item in value) toJsonCompatible(item)];
    }
    return value;
  }

  static String _keyText(Object? key) {
    var compatible = toJsonCompatible(key);
    return compatible is String ? compatible : jsonEncode(compatible);
  }

  static Object? decodeMessagePack(Uint8List payload) {
    var reader = _ByteReader(payload);
    var value = _readMessagePack(reader, 0);
    reader.expectEnd();
    return value;
  }

  static Object? _readMessagePack(_ByteReader reader, int depth) {
    if (depth > _maxDepth) {
      throw FormatException('The data is nested too deep');
    }
    var type = reader.byte();
    if (type <= 0x7f) {
      return type;
    }
    if (type >= 0xe0) {
      return type - 0x100;
    }
    if (type >= 0x80 && type <= 0x8f) {
      return _messagePackMap(reader, type & 0x0f, depth);
    }
    if (type >= 0x90 && type <= 0x9f) {
      return _messagePackList(reader, type & 0x0f, depth);
    }
    if (type >= 0xa0 && type <= 0xbf) {
      return reader.utf8Text(type & 0x1f);
    }
    switch (type) {
      case 0xc0:
        return null;
      case 0xc2:
        return false;
      case 0xc3:
        return true;
      case 0xc4:
        return reader.bytes(reader.uint(1));
      case 0xc5:
        return reader.bytes(reader.uint(2));
      case 0xc6:
        return reader.bytes(reader.uint(4));
      case 0xc7:
        return _messagePackExt(reader, reader.uint(1));
      case 0xc8:
        return _messagePackExt(reader, reader.uint(2));
      case 0xc9:
        return _messagePackExt(reader, reader.uint(4));
      case 0xca:
        return reader.float32();
      case 0xcb:
        return reader.float64();
      case 0xcc:
        return reader.uint(1);
      case 0xcd:
        return reader.uint(2);
      case 0xce:
        return reader.uint(4);
      case 0xcf:
        return reader.uint(8);
      case 0xd0:
        return reader.signed(1);
      case 0xd1:
        return reader.signed(2);
      case 0xd2:
        return reader.signed(4);
      case 0xd3:
        return reader.signed(8);
      case 0xd4:
        return _messagePackExt(reader, 1);
      case 0xd5:
        return _messagePackExt(reader, 2);
      case 0xd6:
        return _messagePackExt(reader, 4);
      case 0xd7:
        return _messagePackExt(reader, 8);
      case 0xd8:
        return _messagePackExt(reader, 16);
      case 0xd9:
        return reader.utf8Text(reader.uint(1));
      case 0xda:
        return reader.utf8Text(reader.uint(2));
      case 0xdb:
        return reader.utf8Text(reader.uint(4));
      case 0xdc:
        return _messagePackList(reader, reader.uint(2), depth);
      case 0xdd:
        return _messagePackList(reader, reader.uint(4), depth);
      case 0xde:
        return _messagePackMap(reader, reader.uint(2), depth);
      case 0xdf:
        return _messagePackMap(reader, reader.uint(4), depth);
    }
    throw FormatException('Unknown MessagePack type 0x${type.toRadixString(16)} at byte ${reader.position - 1}');
  }

  static List<Object?> _messagePackList(_ByteReader reader, int length, int depth) {
    reader.checkCount(length);
    return [for (var i = 0; i < length; i++) _readMessagePack(reader, depth + 1)];
  }

  static Map<Object?, Object?> _messagePackMap(_ByteReader reader, int length, int depth) {
    reader.checkCount(length * 2);
    var map = <Object?, Object?>{};
    for (var i = 0; i < length; i++) {
      var key = _readMessagePack(reader, depth + 1);
      map[key] = _readMessagePack(reader, depth + 1);
    }
    return map;
  }

  // the timestamp extension (type -1) becomes a date, other extensions their type and data
  static Object? _messagePackExt(_ByteReader reader, int length) {
    var type = reader.signed(1);
    var data = reader.bytes(length);
    if (type == -1) {
      var view = _ByteReader(data);
      if (length == 4) {
        return DateTime.fromMillisecondsSinceEpoch(view.uint(4) * 1000, isUtc: true);
      }
      if (length == 8) {
        var high = view.uint(4);
        var low = view.uint(4);
        var nanos = high >> 2;
        var seconds = (high & 0x3) * 0x100000000 + low;
        return DateTime.fromMicrosecondsSinceEpoch(seconds * 1000000 + nanos ~/ 1000, isUtc: true);
      }
      if (length == 12) {
        var nanos = view.uint(4);
        var seconds = view.signed(8);
        return DateTime.fromMicrosecondsSinceEpoch(seconds * 1000000 + nanos ~/ 1000, isUtc: true);
      }
    }
    return {'ext': type, 'data': data};
  }

  static final Object _break = Object();

  static Object? decodeCbor(Uint8List payload) {
    var reader = _ByteReader(payload);
    var value = _readCbor(reader, 0);
    if (identical(value, _break)) {
      throw FormatException('Unexpected break at byte 0');
    }
    reader.expectEnd();
    return value;
  }

  static Object? _readCbor(_ByteReader reader, int depth) {
    if (depth > _maxDepth) {
      throw FormatException('The data is nested too deep');
    }
    var start = reader.position;
    var initial = reader.byte();
    var major = initial >> 5;
    var info = initial & 0x1f;
    if (major == 7) {
      return _cborSimple(reader, info, start);
    }
    var indefinite = info == 31;
    if (indefinite && (major == 0 || major == 1 || major == 6)) {
      throw FormatException('Invalid CBOR item at byte $start');
    }
    var argument = indefinite ? -1 : _cborArgument(reader, info, start);
    switch (major) {
      case 0:
        return argument;
      case 1:
        return -1 - argument;
      case 2:
        return indefinite ? _cborChunks(reader, 2, depth) : reader.bytes(argument);
      case 3:
        return indefinite ? utf8.decode(_cborChunks(reader, 3, depth)) : reader.utf8Text(argument);
      case 4:
        var list = <Object?>[];
        while (indefinite || list.length < argument) {
          var item = _readCbor(reader, depth + 1);
          if (identical(item, _break)) {
            if (!indefinite) {
              throw FormatException('Unexpected break at byte ${reader.position - 1}');
            }
            break;
          }
          list.add(item);
        }
        return list;
      case 5:
        var map = <Object?, Object?>{};
        var entries = 0;
        while (indefinite || entries < argument) {
          var key = _readCbor(reader, depth + 1);
          if (identical(key, _break)) {
            if (!indefinite) {
              throw FormatException('Unexpected break at byte ${reader.position - 1}');
            }
            break;
          }
          var value = _readCbor(reader, depth + 1);
          if (identical(value, _break)) {
            throw FormatException('A map entry has no value at byte ${reader.position - 1}');
          }
          map[key] = value;
          entries++;
        }
        return map;
      default:
        return _cborTag(argument, _readCbor(reader, depth + 1));
    }
  }

  static int _cborArgument(_ByteReader reader, int info, int start) {
    if (info < 24) {
      return info;
    }
    switch (info) {
      case 24:
        return reader.uint(1);
      case 25:
        return reader.uint(2);
      case 26:
        return reader.uint(4);
      case 27:
        return reader.uint(8);
    }
    throw FormatException('Invalid CBOR item at byte $start');
  }

  static Uint8List _cborChunks(_ByteReader reader, int major, int depth) {
    var bytes = BytesBuilder(copy: false);
    while (true) {
      var start = reader.position;
      var chunk = _readCbor(reader, depth + 1);
      if (identical(chunk, _break)) {
        return bytes.takeBytes();
      }
      if (major == 2 && chunk is Uint8List) {
        bytes.add(chunk);
      } else if (major == 3 && chunk is String) {
        bytes.add(utf8.encode(chunk));
      } else {
        throw FormatException('Invalid chunk of an indefinite length string at byte $start');
      }
    }
  }

  static Object? _cborSimple(_ByteReader reader, int info, int start) {
    switch (info) {
      case 20:
        return false;
      case 21:
        return true;
      case 22:
      case 23:
        return null;
      case 24:
        return 'simple(${reader.uint(1)})';
      case 25:
        return _halfFloat(reader.uint(2));
      case 26:
        return reader.float32();
      case 27:
        return reader.float64();
      case 31:
        return _break;
    }
    if (info < 20) {
      return 'simple($info)';
    }
    throw FormatException('Invalid CBOR item at byte $start');
  }

  // dates (tags 0 and 1) and big numbers (tags 2 and 3) are decoded, other tags only show their content
  static Object? _cborTag(int tag, Object? content) {
    if (tag == 1 && content is num) {
      return DateTime.fromMicrosecondsSinceEpoch((content * 1000000).round(), isUtc: true);
    }
    if ((tag == 2 || tag == 3) && content is Uint8List) {
      var value = BigInt.zero;
      for (var byte in content) {
        value = (value << 8) | BigInt.from(byte);
      }
      return tag == 2 ? value : -BigInt.one - value;
    }
    return content;
  }

  static double _halfFloat(int bits) {
    var exponent = (bits >> 10) & 0x1f;
    var mantissa = bits & 0x3ff;
    double value;
    if (exponent == 0) {
      value = mantissa * pow(2, -24).toDouble();
    } else if (exponent == 31) {
      value = mantissa == 0 ? double.infinity : double.nan;
    } else {
      value = (mantissa + 1024) * pow(2, exponent - 25).toDouble();
    }
    return bits & 0x8000 != 0 ? -value : value;
  }
}

// Reads big endian numbers without ByteData.getUint64, which the browser doesn't support
class _ByteReader {
  final Uint8List _bytes;
  int position = 0;

  _ByteReader(this._bytes);

  int byte() {
    if (position >= _bytes.length) {
      throw FormatException('The data ends early at byte $position');
    }
    return _bytes[position++];
  }

  Uint8List bytes(int length) {
    if (length > _bytes.length - position) {
      throw FormatException('The data ends early at byte ${_bytes.length}');
    }
    var result = Uint8List.sublistView(_bytes, position, position + length);
    position += length;
    return result;
  }

  // a list or map can't have more items than bytes are left
  void checkCount(int count) {
    if (count > _bytes.length - position) {
      throw FormatException('The data ends early at byte ${_bytes.length}');
    }
  }

  int uint(int length) {
    var value = 0;
    for (var i = 0; i < length; i++) {
      value = value * 256 + byte();
    }
    return value;
  }

  int signed(int length) {
    var first = byte();
    var value = first >= 0x80 ? first - 0x100 : first;
    for (var i = 1; i < length; i++) {
      value = value * 256 + byte();
    }
    return value;
  }

  String utf8Text(int length) {
    try {
      return utf8.decode(bytes(length));
    } on FormatException {
      throw FormatException('A text is no valid UTF-8 before byte $position');
    }
  }

  double float32() => ByteData.sublistView(bytes(4)).getFloat32(0);

  double float64() => ByteData.sublistView(bytes(8)).getFloat64(0);

  void expectEnd() {
    if (position < _bytes.length) {
      throw FormatException('${_bytes.length - position} bytes follow the end of the data at byte $position');
    }
  }
}
