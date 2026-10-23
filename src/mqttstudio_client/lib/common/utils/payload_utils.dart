import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:typed_data/typed_buffers.dart';

/// Utility class for safely handling MQTT payload conversions
class PayloadUtils {
  /// Safe UTF-8 conversion method to handle German umlauts and other encoding issues
  static String safePayloadToString(Uint8Buffer payload) {
    try {
      // Use utf8.decode directly for consistent UTF-8 handling
      return utf8.decode(payload, allowMalformed: false);
    } catch (FormatException) {
      // If UTF-8 conversion fails, try with error replacement
      try {
        return utf8.decode(payload, allowMalformed: true);
      } catch (e) {
        // Last resort: return hex representation
        return payload.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
      }
    }
  }

  /// Detects how a payload is shown in the message detail view
  static PayloadType detectPayloadType(Uint8Buffer payload) {
    String payloadString = safePayloadToString(payload);

    if (double.tryParse(payloadString) != null) {
      return PayloadType.Number;
    }

    try {
      if (payloadString.trim().startsWith('{')) {
        jsonDecode(payloadString);
        return PayloadType.Json;
      }
    } catch (error) {
      // ignore errors
    }

    // PNG
    if (payload.length >= 4 && payload[0] == 137 && payload[1] == 80 && payload[2] == 78 && payload[3] == 71) {
      return PayloadType.Image;
    }

    // JPG
    if (payload.length >= 3 && payload[0] == 255 && payload[1] == 216 && payload[2] == 255) {
      return PayloadType.Image;
    }

    // Gnss coordinates: if the payload contains two double numbers separated by a comma
    if (tryParseCoordinates(payloadString) != null) {
      return PayloadType.GnssCoordinates;
    }

    return PayloadType.Text;
  }

  /// Returns null if the value is not "latitude,longitude" with both numbers in their valid range
  static LatLng? tryParseCoordinates(String value) {
    var parts = value.split(',');
    if (parts.length != 2) {
      return null;
    }

    var lat = double.tryParse(parts[0]);
    var lon = double.tryParse(parts[1]);
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
      return null;
    }

    return LatLng(lat, lon);
  }
}

enum PayloadType { Text, Number, Json, Image, GnssCoordinates }
