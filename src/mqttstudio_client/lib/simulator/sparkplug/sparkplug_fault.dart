import 'package:mqttstudio/protocol/sparkplug/sparkplug_rules.dart';

enum SparkplugFaultGroup { session, protocol }

// The faults of a simulated edge node (doc/sparkplug-design.md §10.5). Session faults are things that happen in a
// healthy system and give no finding; each protocol fault breaks exactly the rule it names.
enum SparkplugFault {
  // the socket closes without DISCONNECT, the broker publishes the NDEATH will; a new connection follows
  dropConnection(SparkplugFaultGroup.session),
  // NDEATH, disconnect and a new connection with the next bdSeq
  restart(SparkplugFaultGroup.session),
  // DDEATH of every device, DBIRTH when turned off again
  devicesOffline(SparkplugFaultGroup.session, toggle: true),
  skipSeq(SparkplugFaultGroup.protocol, rule: SparkplugRules.seqGap),
  unknownMetric(SparkplugFaultGroup.protocol, rule: SparkplugRules.unknownMetric),
  wrongDatatype(SparkplugFaultGroup.protocol, rule: SparkplugRules.datatypeMismatch),
  // NDEATH, but data goes on; turned off, a rebirth starts a new session
  dataAfterDeath(SparkplugFaultGroup.protocol, rule: SparkplugRules.afterDeath, toggle: true),
  unbornDevice(SparkplugFaultGroup.protocol, rule: SparkplugRules.deviceNotBorn),
  wrongBdSeqInDeath(SparkplugFaultGroup.protocol, rule: SparkplugRules.bdSeqMismatch),
  noTimestamp(SparkplugFaultGroup.protocol, rule: SparkplugRules.timestampMissing, toggle: true),
  notSparkplug(SparkplugFaultGroup.protocol, rule: SparkplugRules.payload);

  final SparkplugFaultGroup group;
  // the finding of the documentation check it causes, null for session faults
  final String? rule;
  // stays on until it is selected again
  final bool toggle;

  const SparkplugFault(this.group, {this.rule, this.toggle = false});
}
