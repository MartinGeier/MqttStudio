import 'dart:typed_data';
import 'package:clock/clock.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_profile.dart';

// an edge node, the target of node commands such as a rebirth request
class SparkplugEdgeNode implements Comparable<SparkplugEdgeNode> {
  final String group;
  final String edgeNode;

  const SparkplugEdgeNode(this.group, this.edgeNode);

  @override
  bool operator ==(Object other) => other is SparkplugEdgeNode && other.group == group && other.edgeNode == edgeNode;

  @override
  int get hashCode => Object.hash(group, edgeNode);

  @override
  int compareTo(SparkplugEdgeNode other) {
    var byGroup = group.compareTo(other.group);
    return byGroup != 0 ? byGroup : edgeNode.compareTo(other.edgeNode);
  }

  @override
  String toString() => '$group/$edgeNode';
}

// Commands MQTT Studio sends to edge nodes (doc/sparkplug-design.md §12): for now the rebirth request. Only built
// here; the user sends them, MQTT Studio never does on its own (R3).
class SparkplugCommands {
  static final SparkplugProfile _profile = SparkplugProfile();

  // the edge node a node or device message belongs to; null for other topics and host STATE
  static SparkplugEdgeNode? edgeNodeOf(String topic) {
    var match = _profile.matchTopic(topic);
    var edgeNode = match?.parameters[SparkplugProfile.edgeNodeKey];
    if (match == null || edgeNode == null) {
      return null;
    }
    return SparkplugEdgeNode(match.parameters[SparkplugProfile.groupKey]!, edgeNode);
  }

  // the edge nodes of the topics in a branch of the topic tree, e.g. a group or one edge node
  static List<SparkplugEdgeNode> edgeNodesIn(String branch, Iterable<String> topics) {
    var nodes = <SparkplugEdgeNode>{
      for (var topic in topics)
        if (topic == branch || topic.startsWith('$branch/'))
          if (edgeNodeOf(topic) case var node?) node,
    };
    return nodes.toList()..sort();
  }

  // NCMD with Node Control/Rebirth = true, by name: an alias needs the birth that is missing (§12.3)
  static (String, Uint8List) rebirth(SparkplugEdgeNode node) => (
    SparkplugProfile.topicOf(SpbMessageType.nCmd, node.group, node.edgeNode),
    SparkplugWriter.write(
      SpbPayload(
        timestamp: clock.now().millisecondsSinceEpoch,
        metrics: [SpbMetric(name: SparkplugProfile.rebirthMetric, datatype: SpbDataType.boolean.code, value: true)],
      ),
    ),
  );
}
