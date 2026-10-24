// The placeholders of simulated topics, template texts and user property values:
// {n} is the instance number, {n:3} the instance number padded with zeros to 3 digits, {device} the device name.
class Placeholders {
  static final RegExp _instancePattern = RegExp(r'\{n(?::(\d+))?\}');
  static const String _devicePlaceholder = '{device}';

  static String resolve(String text, {required int instance, required String deviceName}) {
    var resolved = text.replaceAllMapped(_instancePattern, (match) {
      var width = match.group(1);
      return width == null ? '$instance' : '$instance'.padLeft(int.parse(width), '0');
    });
    return resolved.replaceAll(_devicePlaceholder, sanitizeDeviceName(deviceName));
  }

  static bool containsInstance(String text) => _instancePattern.hasMatch(text);

  // a device name must not add topic levels or wildcards
  static String sanitizeDeviceName(String name) => name.replaceAll(RegExp(r'[/+#]'), '_');

  // the subscription that receives all instances of a simulated topic: weather/{n}/temp -> weather/+/temp
  static String toSubscription(String topic, {required String deviceName}) {
    var levels = topic.split('/').map((level) => _instancePattern.hasMatch(level) ? '+' : level);
    return levels.join('/').replaceAll(_devicePlaceholder, sanitizeDeviceName(deviceName));
  }
}
