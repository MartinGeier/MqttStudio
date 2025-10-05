import 'dart:convert';
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
}
