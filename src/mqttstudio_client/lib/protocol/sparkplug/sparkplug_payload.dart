import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

// The Sparkplug B payload (sparkplug_b.proto of the Eclipse Sparkplug specification 3.0) and a reader and writer of
// its Protobuf wire format, written by hand so the app needs no generated code (doc/sparkplug-design.md §4). Fields
// the reader doesn't know are skipped, as Protobuf readers do.

// the Sparkplug data types with their numbers in the specification
enum SpbDataType {
  unknown(0),
  int8(1),
  int16(2),
  int32(3),
  int64(4),
  uInt8(5),
  uInt16(6),
  uInt32(7),
  uInt64(8),
  float(9),
  double(10),
  boolean(11),
  string(12),
  dateTime(13),
  text(14),
  uuid(15),
  dataSet(16),
  bytes(17),
  file(18),
  template(19),
  propertySet(20),
  propertySetList(21),
  int8Array(22),
  int16Array(23),
  int32Array(24),
  int64Array(25),
  uInt8Array(26),
  uInt16Array(27),
  uInt32Array(28),
  uInt64Array(29),
  floatArray(30),
  doubleArray(31),
  booleanArray(32),
  stringArray(33),
  dateTimeArray(34);

  final int code;

  const SpbDataType(this.code);

  static SpbDataType? of(int? code) => code == null ? null : values.where((type) => type.code == code).firstOrNull;

  // as the specification writes it, e.g. 'Int32'
  String get label => name[0].toUpperCase() + name.substring(1);

  bool get isArray => code >= int8Array.code;
}

class SpbMetaData {
  bool? isMultiPart;
  String? contentType;
  int? size;
  int? seq;
  String? fileName;
  String? fileType;
  String? md5;
  String? description;

  SpbMetaData({
    this.isMultiPart,
    this.contentType,
    this.size,
    this.seq,
    this.fileName,
    this.fileType,
    this.md5,
    this.description,
  });
}

class SpbPropertyValue {
  int? type;
  bool isNull;
  // int, double, bool, String, SpbPropertySet or List<SpbPropertySet>
  Object? value;

  SpbPropertyValue({this.type, this.isNull = false, this.value});
}

class SpbPropertySet {
  final Map<String, SpbPropertyValue> values;

  SpbPropertySet([Map<String, SpbPropertyValue>? values]) : values = values ?? {};
}

class SpbDataSet {
  List<String> columns;
  List<int> types;
  List<List<Object?>> rows;

  SpbDataSet({List<String>? columns, List<int>? types, List<List<Object?>>? rows})
    : columns = columns ?? [],
      types = types ?? [],
      rows = rows ?? [];
}

class SpbParameter {
  String? name;
  int? type;
  Object? value;

  SpbParameter({this.name, this.type, this.value});
}

class SpbTemplate {
  String? version;
  List<SpbMetric> metrics;
  List<SpbParameter> parameters;
  String? templateRef;
  bool? isDefinition;

  SpbTemplate({
    this.version,
    List<SpbMetric>? metrics,
    List<SpbParameter>? parameters,
    this.templateRef,
    this.isDefinition,
  }) : metrics = metrics ?? [],
       parameters = parameters ?? [];
}

class SpbMetric {
  String? name;
  int? alias;
  // milliseconds since the epoch, UTC
  int? timestamp;
  int? datatype;
  bool isHistorical;
  bool isTransient;
  bool isNull;
  SpbMetaData? metadata;
  SpbPropertySet? properties;
  // as the data type says: int (signed for IntN), BigInt for a UInt64 above the int range, double, bool, String,
  // DateTime, Uint8List, SpbDataSet, SpbTemplate or a List for arrays; null when isNull or no value was sent
  Object? value;

  SpbMetric({
    this.name,
    this.alias,
    this.timestamp,
    this.datatype,
    this.isHistorical = false,
    this.isTransient = false,
    this.isNull = false,
    this.metadata,
    this.properties,
    this.value,
  });

  SpbDataType? get type => SpbDataType.of(datatype);
}

class SpbPayload {
  // milliseconds since the epoch, UTC
  int? timestamp;
  List<SpbMetric> metrics;
  int? seq;
  String? uuid;
  Uint8List? body;
  // set when the payload was sent compressed and this is the payload in its body, e.g. 'GZIP'
  String? compressedWith;

  SpbPayload({this.timestamp, List<SpbMetric>? metrics, this.seq, this.uuid, this.body}) : metrics = metrics ?? [];

  // e.g. bdSeq or 'Node Control/Rebirth'
  SpbMetric? metric(String name) => metrics.where((metric) => metric.name == name).firstOrNull;
}

// ---------- 64 bit integers on every platform ----------

// On the web, integers are doubles and shifts work on 32 bits, so varints are added up by multiplying. On the native
// VM the multiplication wraps around, which gives the two's complement of negative 64 bit values for free.
final bool _isWeb = identical(0, 0.0);
const double _two64 = 18446744073709551616.0;
const double _two63 = 9223372036854775808.0;

int _pow2(int exponent) => _isWeb ? pow(2, exponent).toInt() : 1 << exponent;

// a varint read as a signed 64 bit value (the native VM wraps, the web gets the unsigned value)
int _signed64(int raw) => _isWeb && raw >= _two63 ? (raw - _two64).toInt() : raw;

// a varint read as an unsigned 64 bit value; above the int range it is a BigInt on the native VM
Object _unsigned64(int raw) => raw < 0 ? BigInt.from(raw).toUnsigned(64) : raw;

int _signed32(int raw) {
  var value = raw % 4294967296;
  return value >= 2147483648 ? value - 4294967296 : value;
}

int _signed(int raw, int bits) {
  var range = _pow2(bits);
  var value = raw % range;
  return value >= range ~/ 2 ? value - range : value;
}

// ---------- reading ----------

class _Reader {
  final Uint8List bytes;
  final ByteData data;
  int position = 0;
  final int end;

  _Reader(this.bytes, [int start = 0, int? end])
    : data = ByteData.sublistView(bytes),
      position = start,
      end = end ?? bytes.length;

  bool get atEnd => position >= end;

  int _byte() {
    if (position >= end) {
      throw FormatException('Sparkplug payload ends inside a field', bytes, position);
    }
    return bytes[position++];
  }

  int varint() {
    var result = 0;
    for (var shift = 0; shift < 70; shift += 7) {
      var byte = _byte();
      if (shift < 63) {
        result += (byte & 0x7f) * _pow2(shift);
      } else {
        // the tenth byte holds only the top bit
        result += (byte & 0x01) * _pow2(63);
      }
      if (byte & 0x80 == 0) {
        return result;
      }
    }
    throw FormatException('Sparkplug payload has a varint longer than 10 bytes', bytes, position);
  }

  double float32() {
    _need(4);
    var value = data.getFloat32(position, Endian.little);
    position += 4;
    return value;
  }

  double float64() {
    _need(8);
    var value = data.getFloat64(position, Endian.little);
    position += 8;
    return value;
  }

  void _need(int count) {
    if (position + count > end) {
      throw FormatException('Sparkplug payload ends inside a field', bytes, position);
    }
  }

  // the bounds of a length-delimited field
  (int, int) delimited() {
    var length = varint();
    if (length < 0 || position + length > end) {
      throw FormatException('Sparkplug payload has a field longer than the payload', bytes, position);
    }
    var start = position;
    position += length;
    return (start, position);
  }

  Uint8List bytesField() {
    var (start, stop) = delimited();
    return Uint8List.sublistView(bytes, start, stop);
  }

  String string() => utf8.decode(bytesField(), allowMalformed: true);

  _Reader sub() {
    var (start, stop) = delimited();
    return _Reader(bytes, start, stop);
  }

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        varint();
      case 1:
        _need(8);
        position += 8;
      case 2:
        delimited();
      case 5:
        _need(4);
        position += 4;
      default:
        throw FormatException('Sparkplug payload has an unknown wire type $wireType', bytes, position);
    }
  }

  // the fields of the message as (field number, wire type) until its end
  Iterable<(int, int)> fields() sync* {
    while (!atEnd) {
      var key = varint();
      yield (key ~/ 8, key % 8);
    }
  }
}

class SparkplugReader {
  // throws a FormatException when the bytes aren't a Sparkplug B payload
  static SpbPayload read(Uint8List bytes) {
    var reader = _Reader(bytes);
    var payload = SpbPayload();
    for (var (field, wire) in reader.fields()) {
      switch ((field, wire)) {
        case (1, 0):
          payload.timestamp = reader.varint();
        case (2, 2):
          payload.metrics.add(_metric(reader.sub()));
        case (3, 0):
          payload.seq = reader.varint();
        case (4, 2):
          payload.uuid = reader.string();
        case (5, 2):
          payload.body = reader.bytesField();
        default:
          reader.skip(wire);
      }
    }
    return payload;
  }

  static SpbMetric _metric(_Reader reader) {
    var metric = SpbMetric();
    int? intValue;
    int? longValue;
    for (var (field, wire) in reader.fields()) {
      switch ((field, wire)) {
        case (1, 2):
          metric.name = reader.string();
        case (2, 0):
          metric.alias = reader.varint();
        case (3, 0):
          metric.timestamp = reader.varint();
        case (4, 0):
          metric.datatype = reader.varint();
        case (5, 0):
          metric.isHistorical = reader.varint() != 0;
        case (6, 0):
          metric.isTransient = reader.varint() != 0;
        case (7, 0):
          metric.isNull = reader.varint() != 0;
        case (8, 2):
          metric.metadata = _metaData(reader.sub());
        case (9, 2):
          metric.properties = _propertySet(reader.sub());
        case (10, 0):
          intValue = reader.varint();
        case (11, 0):
          longValue = reader.varint();
        case (12, 5):
          metric.value = reader.float32();
        case (13, 1):
          metric.value = reader.float64();
        case (14, 0):
          metric.value = reader.varint() != 0;
        case (15, 2):
          metric.value = reader.string();
        case (16, 2):
          metric.value = reader.bytesField();
        case (17, 2):
          metric.value = _dataSet(reader.sub());
        case (18, 2):
          metric.value = _template(reader.sub());
        default:
          reader.skip(wire);
      }
    }
    if (intValue != null) {
      metric.value = _fromInt(intValue, metric.type);
    } else if (longValue != null) {
      metric.value = _fromLong(longValue, metric.type);
    } else if (metric.value is Uint8List && (metric.type?.isArray ?? false)) {
      metric.value = _array(metric.value as Uint8List, metric.type!);
    }
    if (metric.isNull) {
      metric.value = null;
    }
    return metric;
  }

  // Int8, Int16 and Int32 travel as the two's complement in an uint32 (specification 3.0 §6.4.16)
  static Object _fromInt(int raw, SpbDataType? type) => switch (type) {
    SpbDataType.int8 => _signed(raw, 8),
    SpbDataType.int16 => _signed(raw, 16),
    SpbDataType.int32 => _signed32(raw),
    SpbDataType.boolean => raw != 0,
    _ => raw % 4294967296,
  };

  static Object _fromLong(int raw, SpbDataType? type) => switch (type) {
    SpbDataType.int64 => _signed64(raw),
    SpbDataType.dateTime => DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true),
    // 2.2 senders put small integers into long_value too
    SpbDataType.int8 => _signed(raw, 8),
    SpbDataType.int16 => _signed(raw, 16),
    SpbDataType.int32 => _signed32(raw),
    _ => _unsigned64(raw),
  };

  // arrays travel little endian in bytes_value (specification 3.0 §6.4.17)
  static List<Object?> _array(Uint8List bytes, SpbDataType type) {
    var data = ByteData.sublistView(bytes);
    List<Object?> fixed(int size, Object? Function(int offset) read) => [
      for (var offset = 0; offset + size <= bytes.length; offset += size) read(offset),
    ];
    switch (type) {
      case SpbDataType.int8Array:
        return fixed(1, data.getInt8);
      case SpbDataType.int16Array:
        return fixed(2, (offset) => data.getInt16(offset, Endian.little));
      case SpbDataType.int32Array:
        return fixed(4, (offset) => data.getInt32(offset, Endian.little));
      case SpbDataType.int64Array:
        return fixed(8, (offset) => _int64At(data, offset, signed: true));
      case SpbDataType.uInt8Array:
        return fixed(1, data.getUint8);
      case SpbDataType.uInt16Array:
        return fixed(2, (offset) => data.getUint16(offset, Endian.little));
      case SpbDataType.uInt32Array:
        return fixed(4, (offset) => data.getUint32(offset, Endian.little));
      case SpbDataType.uInt64Array:
        return fixed(8, (offset) => _int64At(data, offset, signed: false));
      case SpbDataType.floatArray:
        return fixed(4, (offset) => data.getFloat32(offset, Endian.little));
      case SpbDataType.doubleArray:
        return fixed(8, (offset) => data.getFloat64(offset, Endian.little));
      case SpbDataType.dateTimeArray:
        return fixed(
          8,
          (offset) => DateTime.fromMillisecondsSinceEpoch(_int64At(data, offset, signed: true) as int, isUtc: true),
        );
      case SpbDataType.booleanArray:
        // a 4 byte count of the booleans, then the bits, high bit first
        if (bytes.length < 4) {
          return [];
        }
        var count = data.getUint32(0, Endian.little);
        return [
          for (var i = 0; i < count && 4 + i ~/ 8 < bytes.length; i++) bytes[4 + i ~/ 8] & (0x80 >> (i % 8)) != 0,
        ];
      case SpbDataType.stringArray:
        // null terminated strings
        var strings = <Object?>[];
        var start = 0;
        for (var i = 0; i < bytes.length; i++) {
          if (bytes[i] == 0) {
            strings.add(utf8.decode(bytes.sublist(start, i), allowMalformed: true));
            start = i + 1;
          }
        }
        return strings;
      default:
        return [bytes];
    }
  }

  // two 32 bit halves, so the web reads them too
  static Object _int64At(ByteData data, int offset, {required bool signed}) {
    var low = data.getUint32(offset, Endian.little);
    var high = signed ? data.getInt32(offset + 4, Endian.little) : data.getUint32(offset + 4, Endian.little);
    var value = high * 4294967296 + low;
    return !signed && value < 0 ? BigInt.from(value).toUnsigned(64) : value;
  }

  static SpbMetaData _metaData(_Reader reader) {
    var meta = SpbMetaData();
    for (var (field, wire) in reader.fields()) {
      switch ((field, wire)) {
        case (1, 0):
          meta.isMultiPart = reader.varint() != 0;
        case (2, 2):
          meta.contentType = reader.string();
        case (3, 0):
          meta.size = reader.varint();
        case (4, 0):
          meta.seq = reader.varint();
        case (5, 2):
          meta.fileName = reader.string();
        case (6, 2):
          meta.fileType = reader.string();
        case (7, 2):
          meta.md5 = reader.string();
        case (8, 2):
          meta.description = reader.string();
        default:
          reader.skip(wire);
      }
    }
    return meta;
  }

  static SpbPropertySet _propertySet(_Reader reader) {
    var keys = <String>[];
    var values = <SpbPropertyValue>[];
    for (var (field, wire) in reader.fields()) {
      switch ((field, wire)) {
        case (1, 2):
          keys.add(reader.string());
        case (2, 2):
          values.add(_propertyValue(reader.sub()));
        default:
          reader.skip(wire);
      }
    }
    return SpbPropertySet({for (var i = 0; i < keys.length && i < values.length; i++) keys[i]: values[i]});
  }

  static SpbPropertyValue _propertyValue(_Reader reader) {
    var property = SpbPropertyValue();
    int? intValue;
    int? longValue;
    for (var (field, wire) in reader.fields()) {
      switch ((field, wire)) {
        case (1, 0):
          property.type = reader.varint();
        case (2, 0):
          property.isNull = reader.varint() != 0;
        case (3, 0):
          intValue = reader.varint();
        case (4, 0):
          longValue = reader.varint();
        case (5, 5):
          property.value = reader.float32();
        case (6, 1):
          property.value = reader.float64();
        case (7, 0):
          property.value = reader.varint() != 0;
        case (8, 2):
          property.value = reader.string();
        case (9, 2):
          property.value = _propertySet(reader.sub());
        case (10, 2):
          property.value = _propertySetList(reader.sub());
        default:
          reader.skip(wire);
      }
    }
    var type = SpbDataType.of(property.type);
    if (intValue != null) {
      property.value = _fromInt(intValue, type);
    } else if (longValue != null) {
      property.value = _fromLong(longValue, type);
    }
    return property;
  }

  static List<SpbPropertySet> _propertySetList(_Reader reader) {
    var sets = <SpbPropertySet>[];
    for (var (field, wire) in reader.fields()) {
      if (field == 1 && wire == 2) {
        sets.add(_propertySet(reader.sub()));
      } else {
        reader.skip(wire);
      }
    }
    return sets;
  }

  static SpbDataSet _dataSet(_Reader reader) {
    var dataSet = SpbDataSet();
    for (var (field, wire) in reader.fields()) {
      switch ((field, wire)) {
        case (2, 2):
          dataSet.columns.add(reader.string());
        case (3, 0):
          dataSet.types.add(reader.varint());
        // proto2 doesn't pack, but some writers do
        case (3, 2):
          var packed = reader.sub();
          while (!packed.atEnd) {
            dataSet.types.add(packed.varint());
          }
        case (4, 2):
          dataSet.rows.add(_row(reader.sub(), dataSet.types));
        default:
          reader.skip(wire);
      }
    }
    return dataSet;
  }

  static List<Object?> _row(_Reader reader, List<int> types) {
    var row = <Object?>[];
    for (var (field, wire) in reader.fields()) {
      if (field == 1 && wire == 2) {
        row.add(_dataSetValue(reader.sub(), SpbDataType.of(row.length < types.length ? types[row.length] : null)));
      } else {
        reader.skip(wire);
      }
    }
    return row;
  }

  static Object? _dataSetValue(_Reader reader, SpbDataType? type) {
    Object? value;
    for (var (field, wire) in reader.fields()) {
      switch ((field, wire)) {
        case (1, 0):
          value = _fromInt(reader.varint(), type);
        case (2, 0):
          value = _fromLong(reader.varint(), type);
        case (3, 5):
          value = reader.float32();
        case (4, 1):
          value = reader.float64();
        case (5, 0):
          value = reader.varint() != 0;
        case (6, 2):
          value = reader.string();
        default:
          reader.skip(wire);
      }
    }
    return value;
  }

  static SpbTemplate _template(_Reader reader) {
    var template = SpbTemplate();
    for (var (field, wire) in reader.fields()) {
      switch ((field, wire)) {
        case (1, 2):
          template.version = reader.string();
        case (2, 2):
          template.metrics.add(_metric(reader.sub()));
        case (3, 2):
          template.parameters.add(_parameter(reader.sub()));
        case (4, 2):
          template.templateRef = reader.string();
        case (5, 0):
          template.isDefinition = reader.varint() != 0;
        default:
          reader.skip(wire);
      }
    }
    return template;
  }

  static SpbParameter _parameter(_Reader reader) {
    var parameter = SpbParameter();
    for (var (field, wire) in reader.fields()) {
      switch ((field, wire)) {
        case (1, 2):
          parameter.name = reader.string();
        case (2, 0):
          parameter.type = reader.varint();
        case (3, 0):
          parameter.value = _fromInt(reader.varint(), SpbDataType.of(parameter.type));
        case (4, 0):
          parameter.value = _fromLong(reader.varint(), SpbDataType.of(parameter.type));
        case (5, 5):
          parameter.value = reader.float32();
        case (6, 1):
          parameter.value = reader.float64();
        case (7, 0):
          parameter.value = reader.varint() != 0;
        case (8, 2):
          parameter.value = reader.string();
        default:
          reader.skip(wire);
      }
    }
    return parameter;
  }
}

// ---------- writing ----------

class _Writer {
  final BytesBuilder _out = BytesBuilder(copy: false);

  Uint8List takeBytes() => _out.takeBytes();

  void _key(int field, int wire) => _varint(field * 8 + wire);

  void _varint(Object value) {
    if (value is BigInt || (value is int && value < 0)) {
      // negative 64 bit values take 10 bytes in two's complement
      var big = (value is BigInt ? value : BigInt.from(value as int)).toUnsigned(64);
      var mask = BigInt.from(0x7f);
      while (big > mask) {
        _out.addByte((big & mask).toInt() | 0x80);
        big = big >> 7;
      }
      _out.addByte(big.toInt());
      return;
    }
    var number = value as int;
    while (number >= 0x80) {
      _out.addByte(number % 128 | 0x80);
      number ~/= 128;
    }
    _out.addByte(number);
  }

  void varint(int field, Object value) {
    _key(field, 0);
    _varint(value);
  }

  void boolean(int field, bool value) => varint(field, value ? 1 : 0);

  void float32(int field, double value) {
    _key(field, 5);
    _out.add((ByteData(4)..setFloat32(0, value, Endian.little)).buffer.asUint8List());
  }

  void float64(int field, double value) {
    _key(field, 1);
    _out.add((ByteData(8)..setFloat64(0, value, Endian.little)).buffer.asUint8List());
  }

  void bytes(int field, List<int> value) {
    _key(field, 2);
    _varint(value.length);
    _out.add(value);
  }

  void string(int field, String value) => bytes(field, utf8.encode(value));

  void message(int field, void Function(_Writer writer) write) {
    var inner = _Writer();
    write(inner);
    bytes(field, inner.takeBytes());
  }
}

class SparkplugWriter {
  static Uint8List write(SpbPayload payload) {
    var writer = _Writer();
    if (payload.timestamp != null) {
      writer.varint(1, payload.timestamp!);
    }
    for (var metric in payload.metrics) {
      writer.message(2, (inner) => _metric(inner, metric));
    }
    if (payload.seq != null) {
      writer.varint(3, payload.seq!);
    }
    if (payload.uuid != null) {
      writer.string(4, payload.uuid!);
    }
    if (payload.body != null) {
      writer.bytes(5, payload.body!);
    }
    return writer.takeBytes();
  }

  static void _metric(_Writer writer, SpbMetric metric) {
    if (metric.name != null) {
      writer.string(1, metric.name!);
    }
    if (metric.alias != null) {
      writer.varint(2, metric.alias!);
    }
    if (metric.timestamp != null) {
      writer.varint(3, metric.timestamp!);
    }
    if (metric.datatype != null) {
      writer.varint(4, metric.datatype!);
    }
    if (metric.isHistorical) {
      writer.boolean(5, true);
    }
    if (metric.isTransient) {
      writer.boolean(6, true);
    }
    if (metric.isNull) {
      writer.boolean(7, true);
    }
    if (metric.metadata != null) {
      writer.message(8, (inner) => _metaData(inner, metric.metadata!));
    }
    if (metric.properties != null) {
      writer.message(9, (inner) => _propertySet(inner, metric.properties!));
    }
    if (!metric.isNull && metric.value != null) {
      _value(writer, metric.type, metric.value!);
    }
  }

  static void _value(_Writer writer, SpbDataType? type, Object value) {
    switch (type) {
      case SpbDataType.int8 || SpbDataType.int16 || SpbDataType.int32:
        writer.varint(10, (value as int) % 4294967296);
      case SpbDataType.uInt8 || SpbDataType.uInt16 || SpbDataType.uInt32:
        writer.varint(10, value as int);
      case SpbDataType.int64 || SpbDataType.uInt64:
        writer.varint(11, value);
      case SpbDataType.dateTime:
        writer.varint(11, value is DateTime ? value.millisecondsSinceEpoch : value);
      case SpbDataType.float:
        writer.float32(12, (value as num).toDouble());
      case SpbDataType.double:
        writer.float64(13, (value as num).toDouble());
      case SpbDataType.boolean:
        writer.boolean(14, value as bool);
      case SpbDataType.string || SpbDataType.text || SpbDataType.uuid:
        writer.string(15, value as String);
      case SpbDataType.dataSet:
        writer.message(17, (inner) => _dataSet(inner, value as SpbDataSet));
      case SpbDataType.template:
        writer.message(18, (inner) => _template(inner, value as SpbTemplate));
      default:
        if (value is List<int>) {
          writer.bytes(16, value);
        }
    }
  }

  static void _metaData(_Writer writer, SpbMetaData meta) {
    if (meta.isMultiPart != null) {
      writer.boolean(1, meta.isMultiPart!);
    }
    if (meta.contentType != null) {
      writer.string(2, meta.contentType!);
    }
    if (meta.size != null) {
      writer.varint(3, meta.size!);
    }
    if (meta.seq != null) {
      writer.varint(4, meta.seq!);
    }
    if (meta.fileName != null) {
      writer.string(5, meta.fileName!);
    }
    if (meta.fileType != null) {
      writer.string(6, meta.fileType!);
    }
    if (meta.md5 != null) {
      writer.string(7, meta.md5!);
    }
    if (meta.description != null) {
      writer.string(8, meta.description!);
    }
  }

  static void _propertySet(_Writer writer, SpbPropertySet set) {
    for (var key in set.values.keys) {
      writer.string(1, key);
    }
    for (var value in set.values.values) {
      writer.message(2, (inner) {
        if (value.type != null) {
          inner.varint(1, value.type!);
        }
        if (value.isNull) {
          inner.boolean(2, true);
          return;
        }
        var data = value.value;
        switch (SpbDataType.of(value.type)) {
          case SpbDataType.int8 || SpbDataType.int16 || SpbDataType.int32:
            inner.varint(3, (data as int) % 4294967296);
          case SpbDataType.uInt8 || SpbDataType.uInt16 || SpbDataType.uInt32:
            inner.varint(3, data as int);
          case SpbDataType.int64 || SpbDataType.uInt64 || SpbDataType.dateTime:
            inner.varint(4, data is DateTime ? data.millisecondsSinceEpoch : data!);
          case SpbDataType.float:
            inner.float32(5, (data as num).toDouble());
          case SpbDataType.double:
            inner.float64(6, (data as num).toDouble());
          case SpbDataType.boolean:
            inner.boolean(7, data as bool);
          case SpbDataType.propertySet:
            inner.message(9, (set) => _propertySet(set, data as SpbPropertySet));
          case SpbDataType.propertySetList:
            inner.message(10, (list) {
              for (var set in data as List<SpbPropertySet>) {
                list.message(1, (item) => _propertySet(item, set));
              }
            });
          default:
            if (data is String) {
              inner.string(8, data);
            }
        }
      });
    }
  }

  static void _dataSet(_Writer writer, SpbDataSet dataSet) {
    writer.varint(1, dataSet.columns.length);
    for (var column in dataSet.columns) {
      writer.string(2, column);
    }
    for (var type in dataSet.types) {
      writer.varint(3, type);
    }
    for (var row in dataSet.rows) {
      writer.message(4, (rowWriter) {
        for (var i = 0; i < row.length; i++) {
          var type = SpbDataType.of(i < dataSet.types.length ? dataSet.types[i] : null);
          var value = row[i];
          rowWriter.message(1, (element) {
            if (value == null) {
              return;
            }
            switch (type) {
              case SpbDataType.int8 || SpbDataType.int16 || SpbDataType.int32:
                element.varint(1, (value as int) % 4294967296);
              case SpbDataType.uInt8 || SpbDataType.uInt16 || SpbDataType.uInt32:
                element.varint(1, value as int);
              case SpbDataType.int64 || SpbDataType.uInt64 || SpbDataType.dateTime:
                element.varint(2, value is DateTime ? value.millisecondsSinceEpoch : value);
              case SpbDataType.float:
                element.float32(3, (value as num).toDouble());
              case SpbDataType.double:
                element.float64(4, (value as num).toDouble());
              case SpbDataType.boolean:
                element.boolean(5, value as bool);
              default:
                element.string(6, '$value');
            }
          });
        }
      });
    }
  }

  static void _template(_Writer writer, SpbTemplate template) {
    if (template.version != null) {
      writer.string(1, template.version!);
    }
    for (var metric in template.metrics) {
      writer.message(2, (inner) => _metric(inner, metric));
    }
    for (var parameter in template.parameters) {
      writer.message(3, (inner) {
        if (parameter.name != null) {
          inner.string(1, parameter.name!);
        }
        if (parameter.type != null) {
          inner.varint(2, parameter.type!);
        }
        var value = parameter.value;
        if (value is bool) {
          inner.boolean(7, value);
        } else if (value is int) {
          inner.varint(4, value);
        } else if (value is double) {
          inner.float64(6, value);
        } else if (value is String) {
          inner.string(8, value);
        }
      });
    }
    if (template.templateRef != null) {
      writer.string(4, template.templateRef!);
    }
    if (template.isDefinition != null) {
      writer.boolean(5, template.isDefinition!);
    }
  }
}
