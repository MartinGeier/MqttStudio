import 'package:mqttstudio/protocol/protocol_profile.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_profile.dart';

// The known protocol profiles in a fixed order; the first one that recognizes a topic wins. The result of a topic is
// cached, topics repeat a lot.
class ProtocolRegistry {
  final List<ProtocolProfile> profiles;
  final Map<String, ProtocolTopic?> _matches = {};

  ProtocolRegistry(this.profiles);

  factory ProtocolRegistry.standard() => ProtocolRegistry([Vda5050Profile()]);

  ProtocolTopic? match(String topic) => _matches.putIfAbsent(topic, () {
        for (var profile in profiles) {
          var match = profile.matchTopic(topic);
          if (match != null) {
            return match;
          }
        }
        return null;
      });

  void clearCache() => _matches.clear();
}
