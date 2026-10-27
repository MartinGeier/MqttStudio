// The generic protocol layer (doc/vda5050-design.md §5, V2): a profile recognizes the messages of one protocol,
// interprets them for the viewers and checks the protocol for the documentation check. The viewers and the check know
// profiles, not VDA 5050.

// what a device reports about itself: nothing special, a warning or an error
enum InterpretationLevel { none, warning, error }

// A topic a profile recognized from its levels alone
class ProtocolTopic {
  final ProtocolProfile profile;
  // e.g. 'state'
  final String messageType;
  // the topic without the message type, it groups the topics of one device
  final String deviceKey;
  // e.g. interfaceName, majorVersion, manufacturer, serialNumber
  final Map<String, String> parameters;

  const ProtocolTopic(this.profile, this.messageType, this.deviceKey, this.parameters);
}

// The parts of an interpreted message for the detail view. Data, not widgets, so the engine is testable without
// Flutter and the CLI could print it.
sealed class InterpretedSection {
  // stable, e.g. for the collapsed state
  final String key;
  final String title;

  const InterpretedSection(this.key, this.title);
}

class InterpretedValue {
  final String label;
  final String value;
  final InterpretationLevel level;

  const InterpretedValue(this.label, this.value, {this.level = InterpretationLevel.none});
}

class KeyValueSection extends InterpretedSection {
  final List<InterpretedValue> values;

  const KeyValueSection(super.key, super.title, this.values);
}

class InterpretedRow {
  final List<String> cells;
  final InterpretationLevel level;
  // drawn weaker, e.g. the unreleased horizon of an order
  final bool muted;

  const InterpretedRow(this.cells, {this.level = InterpretationLevel.none, this.muted = false});
}

class TableSection extends InterpretedSection {
  final List<String> columns;
  final List<InterpretedRow> rows;

  const TableSection(super.key, super.title, this.columns, this.rows);
}

// fields the profile doesn't know, as JSON
class RawSection extends InterpretedSection {
  final Map<String, Object?> json;

  const RawSection(super.key, super.title, this.json);
}

class Interpretation {
  // as in the message, e.g. '3.0.0'
  final String protocolVersion;
  // one line of plain text
  final String summary;
  final InterpretationLevel level;
  final List<InterpretedSection> sections;
  // chartable values by label, e.g. 'State of charge %': 78
  final Map<String, double> values;

  const Interpretation(
      {required this.protocolVersion,
      required this.summary,
      this.level = InterpretationLevel.none,
      this.sections = const [],
      this.values = const {}});
}

// what an interpreter may look up: the last message of another topic, e.g. of the same device, as data (see
// ProtocolProfile.interpret); the profile knows its topic layout
abstract class InterpretationContext {
  Object? lastData(String topic);
}

class NoContext implements InterpretationContext {
  const NoContext();

  @override
  Object? lastData(String topic) => null;
}

enum ProtocolSeverity { error, warning }

// one protocol rule a message breaks (doc/vda5050-design.md §9.3)
class ProtocolFinding {
  // e.g. 'vda5050.headerIdGap'
  final String rule;
  final ProtocolSeverity severity;
  // English, like the other check details
  final String detail;
  // findings of the same rule and topic with another key are kept apart
  final String key;

  const ProtocolFinding(this.rule, this.severity, this.detail, {this.key = ''});
}

// Checks the protocol over one check run; it keeps state, e.g. the last header id per topic
abstract class ProtocolChecker {
  // data as for ProtocolProfile.interpret; snapshot: a retained message the broker sent because the check subscribed,
  // it was published earlier
  List<ProtocolFinding> check(String topic, ProtocolTopic match, Object? data, DateTime receivedAt,
      {bool snapshot = false});

  // rules that fire on time, e.g. an unanswered request; returns the topic each finding belongs to
  List<(String, ProtocolFinding)> tick(DateTime now) => const [];
}

abstract class ProtocolProfile {
  // e.g. 'vda5050'
  String get id;

  // e.g. 'VDA 5050'
  String get name;

  // null when the topic can't belong to this profile
  ProtocolTopic? matchTopic(String topic);

  // data is the decoded JSON (or MessagePack, CBOR) when the payload has it, else the payload's bytes as a Uint8List,
  // e.g. Protobuf. Null when the payload doesn't confirm the match, e.g. no header.
  Interpretation? interpret(ProtocolTopic topic, Object? data, {InterpretationContext context = const NoContext()});

  // a new checker for one check run
  ProtocolChecker createChecker();
}
