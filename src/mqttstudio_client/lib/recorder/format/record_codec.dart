import 'dart:convert';
import 'dart:typed_data';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/recorder/model/recorded_message.dart';

// The byte layout of a .mqttrec file, see doc/recorder-design.md §4.2. All integers are little endian.
//
//   File    = "MQREC" | version u8 | headerLength u32 | header JSON | Record* | Trailer
//   Record  = type u8 | bodyLength u32 | body | crc32 u32 (over type, bodyLength and body)
//   Trailer = footerPosition u64 | "MQEND"
class RecordCodec {
  static const List<int> magic = [0x4d, 0x51, 0x52, 0x45, 0x43]; // MQREC
  static const List<int> endMagic = [0x4d, 0x51, 0x45, 0x4e, 0x44]; // MQEND
  static const int formatVersion = 1;
  static const int prefixLength = 10; // magic, version, header length
  static const int recordOverhead = 9; // type, body length, crc
  static const int trailerLength = 13;
  // records larger than this are treated as damage while reading
  static const int maxBodyLength = 64 * 1024 * 1024;

  static const int typeTopic = 1;
  static const int typeMessage = 2;
  static const int typeMarker = 3;
  static const int typeFooter = 9;

  static const int _flagRetain = 0x04;
  static const int _flagSnapshot = 0x08;
  static const int _flagProperties = 0x10;
  static const int _flagTruncated = 0x20;

  static Uint8List encodeStart(Map<String, dynamic> header) {
    var json = utf8.encode(jsonEncode(header));
    var bytes = BytesBuilder(copy: false)
      ..add(magic)
      ..addByte(formatVersion)
      ..add(_u32(json.length))
      ..add(json);
    return bytes.takeBytes();
  }

  static Uint8List encodeTopic(int topicIndex, String topic) {
    var name = utf8.encode(topic);
    return _record(typeTopic, BytesBuilder(copy: false)..add(_u32(topicIndex))..add(name));
  }

  static Uint8List encodeMessage(RecordedMessage message, int topicIndex, Map<String, dynamic>? properties) {
    var flags = message.qos.index & 0x03;
    if (message.retain) {
      flags |= _flagRetain;
    }
    if (message.snapshot) {
      flags |= _flagSnapshot;
    }
    if (message.truncated) {
      flags |= _flagTruncated;
    }
    if (properties != null) {
      flags |= _flagProperties;
    }
    var body = BytesBuilder(copy: false)
      ..add(_u64(message.offsetMicros))
      ..add(_u32(topicIndex))
      ..addByte(flags)
      ..add(_u32(message.payloadLength))
      ..add(_u32(message.payload.length))
      ..add(message.payload);
    if (properties != null) {
      var json = utf8.encode(jsonEncode(properties));
      body
        ..add(_u32(json.length))
        ..add(json);
    }
    return _record(typeMessage, body);
  }

  static Uint8List encodeMarker(RecordingMarker marker) {
    var json = utf8.encode(jsonEncode({'kind': marker.kind}));
    return _record(typeMarker, BytesBuilder(copy: false)..add(_u64(marker.offsetMicros))..add(json));
  }

  static Uint8List encodeFooter(Map<String, dynamic> footer) =>
      _record(typeFooter, BytesBuilder(copy: false)..add(utf8.encode(jsonEncode(footer))));

  static Uint8List encodeTrailer(int footerPosition) =>
      (BytesBuilder(copy: false)..add(_u64(footerPosition))..add(endMagic)).takeBytes();

  // the footer position of a valid trailer, null if the bytes are no trailer
  static int? decodeTrailer(Uint8List bytes) {
    if (bytes.length != trailerLength) {
      return null;
    }
    for (var i = 0; i < endMagic.length; i++) {
      if (bytes[8 + i] != endMagic[i]) {
        return null;
      }
    }
    return readU64(ByteData.sublistView(bytes), 0);
  }

  // the header length, null if the bytes don't start a recording of a known version
  static int? decodePrefix(Uint8List bytes) {
    if (bytes.length < prefixLength) {
      return null;
    }
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) {
        return null;
      }
    }
    if (bytes[5] != formatVersion) {
      return null;
    }
    return ByteData.sublistView(bytes).getUint32(6, Endian.little);
  }

  static Map<String, dynamic> decodeJson(Uint8List bytes) => jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

  static ({int topicIndex, String topic}) decodeTopic(Uint8List body) {
    var data = ByteData.sublistView(body);
    return (topicIndex: data.getUint32(0, Endian.little), topic: utf8.decode(Uint8List.sublistView(body, 4)));
  }

  static RecordedMessage decodeMessage(Uint8List body, String Function(int topicIndex) topicOf) {
    var data = ByteData.sublistView(body);
    var offset = readU64(data, 0);
    var topicIndex = data.getUint32(8, Endian.little);
    var flags = body[12];
    var payloadLength = data.getUint32(13, Endian.little);
    var storedLength = data.getUint32(17, Endian.little);
    var payload = Uint8List.fromList(Uint8List.sublistView(body, 21, 21 + storedLength));
    Map<String, dynamic>? properties;
    if (flags & _flagProperties != 0) {
      var start = 21 + storedLength;
      var length = data.getUint32(start, Endian.little);
      properties = decodeJson(Uint8List.sublistView(body, start + 4, start + 4 + length));
    }
    return RecordedMessage(
      offsetMicros: offset,
      topic: topicOf(topicIndex),
      payload: payload,
      payloadLength: payloadLength,
      qos: MqttQos.values[flags & 0x03],
      retain: flags & _flagRetain != 0,
      snapshot: flags & _flagSnapshot != 0,
      truncated: flags & _flagTruncated != 0,
      properties: properties == null ? null : RecordedProperties.fromJson(properties),
    );
  }

  static RecordingMarker decodeMarker(Uint8List body) {
    var offset = readU64(ByteData.sublistView(body), 0);
    var json = decodeJson(Uint8List.sublistView(body, 8));
    return RecordingMarker(offset, json['kind'] as String);
  }

  static Uint8List _record(int type, BytesBuilder body) {
    var bodyBytes = body.takeBytes();
    var head = Uint8List(5)..[0] = type;
    head.buffer.asByteData().setUint32(1, bodyBytes.length, Endian.little);
    return (BytesBuilder(copy: false)
          ..add(head)
          ..add(bodyBytes)
          ..add(_u32(crcOf(head, bodyBytes))))
        .takeBytes();
  }

  // the checksum stored after a record's body; head is the type and the body length
  static int crcOf(Uint8List head, Uint8List body) => Crc32.of(body, crc: Crc32.of(head, finish: false));

  static Uint8List _u32(int value) => Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);

  // two 32 bit halves, because ByteData.setUint64 is not available in the browser
  static Uint8List _u64(int value) => Uint8List(8)
    ..buffer.asByteData().setUint32(0, value % 0x100000000, Endian.little)
    ..buffer.asByteData().setUint32(4, value ~/ 0x100000000, Endian.little);

  static int readU64(ByteData data, int offset) =>
      data.getUint32(offset, Endian.little) + data.getUint32(offset + 4, Endian.little) * 0x100000000;
}

// CRC-32 (IEEE 802.3), the checksum of zip and PNG
class Crc32 {
  static const int initial = 0xffffffff;
  static final List<int> _table = _buildTable();

  static List<int> _buildTable() {
    var table = List<int>.filled(256, 0);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
      }
      table[n] = c;
    }
    return table;
  }

  // continues the running value [crc]; finish: false leaves it open for more data
  static int of(List<int> bytes, {int crc = initial, bool finish = true}) {
    var c = crc;
    for (var byte in bytes) {
      c = _table[(c ^ byte) & 0xff] ^ (c >> 8);
    }
    return finish ? (c ^ 0xffffffff) & 0xffffffff : c;
  }
}
