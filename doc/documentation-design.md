# MQTT Topic Documentation – Detailed Design

Status: **Draft**. Scope and the former open questions are decided (T1–T3, T17–T20); the other
decisions are proposed, see §2 · Branch: `mqtt5` · Last updated: 2026-10-24

Related: `recorder-design.md` (own connection R6, `.mqttrec` files, payload classification),
`simulator-design.md` (payload generators) and `cli-design.md` (commands, exit codes).
Screens: the canvas "MQTT Studio Topic Documentation",
https://claude.ai/artifact/LnGv7TegEdUt1NtsSqAXAf (§12.9).

## 1. Purpose

The documentation feature describes the topics of a broker namespace: what each topic means, what
its payload looks like, how often it is sent, with which QoS and retain flag, who produces and
consumes it. It lives in the existing (currently hidden) **DOCUMENTATION** tab.

Writing such a document by hand is slow, and it is out of date the day after. So MQTT Studio
**discovers** the documentation from live traffic: subscribe to a wildcard filter, listen for a
while, and turn every topic seen into a documented entry with its payload format, schema,
frequency, QoS and retain status already filled in. The user then edits the text by hand.
Discovery can run again at any time and only reports what changed; it never overwrites what the
user wrote. A conformance check compares live traffic against the documentation.

Typical uses: document an existing plant or product before a project starts, hand a system over
to a customer or a support team, review a namespace for naming and payload consistency, and check
in CI that devices still send what the documentation promises.

### Goals (v1)
- Document every topic of a tree: description, status, owner, tags, links, topic parameters,
  payload (format, unit, range, allowed values, JSON schema, examples), QoS, retain, frequency and
  stale threshold, MQTT 5 properties, producers, consumers, access notes, sensitivity, last will.
- Document namespace nodes (`plant/line1` = "Assembly line 1") and the documentation as a whole.
- **Discover** topics and their properties by subscribing to one or more wildcard filters, from
  a recording or from the topic viewer's messages. Collapse topic instances into **templates**
  with parameters (`plant/{line}/m{machine}/temp`).
- Run discovery again at any time: a **review** lists new, changed and no longer seen topics and
  proposed templates. Nothing the user wrote is overwritten without asking.
- **Check** live traffic against the documentation: undocumented topics, payloads that break the
  schema, values out of range, wrong QoS or retain, topics that go stale, deprecated topics still
  in use.
- Export to Markdown, HTML, AsyncAPI 3.0 (YAML and JSON), a JSON Schema bundle and CSV. Import
  AsyncAPI 2.6 and 3.0.
- Show a topic's documentation in the topic viewer (detail view, tree tooltips, chart units).
- Create a simulation from documented topics.
- Discover, check and export from the CLI.

### Non-goals (v1)
- Decoding Protobuf, Sparkplug B or other binary formats. They are documented as `binary` with a
  free-text description (§16).
- Several people editing one documentation at the same time, or a server that hosts it. Teams
  exchange it as an exported file or through a shared project export.
- Rich-text editing. Descriptions are Markdown, edited as plain text with a preview.
- Discovering producers and consumers. MQTT does not tell a subscriber who published a message.
  They are entered by hand (or taken from a user property, §5.3).
- Documenting broker ACLs automatically. Access is a free-text note per topic.
- Validating messages in the topic viewer (T19). The check runs in the documentation tab and the
  CLI.
- Importing from CSV or Excel, or publishing to Confluence (T20).

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| T1 | **Document all topics of a tree** with payload, message frequency, retain status and the other properties of §4 | User |
| T2 | **Generate topics and documentation by subscribing to a wildcard path** and listening, then keep editing by hand | User |
| T3 | The documentation is **part of the `Project`**, like the simulation. It documents the namespace of the project's broker, is saved with the project and marks it as changed (§4.5). Exchange with others goes through export and import. Projects for different brokers (test, production) each keep their own copy | User |
| T4 | The unit of documentation is the **topic template**: a topic path whose segments may hold one parameter each, with an optional literal prefix and suffix (`m{machine}`). A concrete topic belongs to the template that matches it with the most literal segments (§4.3) | Design |
| T5 | Every node keeps **documented** values (owned by the user) and **observed** values (owned by discovery) apart. Discovery always replaces the observed values. It writes a documented value only when the field is empty and the user never edited it; otherwise it reports a difference (§4.4) | Design |
| T6 | **Templates are proposed, never applied silently.** Discovery suggests parameters; the user accepts, renames or rejects them in the review | Design |
| T7 | Payload structure is a **JSON Schema** (draft 2020-12 subset, §5.4) stored as typed `SchemaNode`s, edited as a field table, with the raw JSON as a fallback. Units are `x-unit` | Design |
| T8 | **AsyncAPI 3.0** is the exchange format. The model maps onto it without loss; everything AsyncAPI has no field for goes into `x-mqttstudio-*` extensions (§10.2) | Design |
| T9 | Discovery and the check use **their own MQTT connection**, built from the project's broker settings like the recorder's (R6), with the client id `<clientId>-doc-<suffix>`. The topic viewer's subscriptions and buffer stay untouched | Design |
| T10 | Discovery subscribes with **QoS 2**, so the delivered QoS is the publisher's QoS, and on MQTT 5 with **Retain As Published**, so the retain flag of live messages is the publisher's. On 3.1.1 retain is known only from the retained snapshot (§5.2) | Design |
| T11 | One analyzer (`DocumentationAnalyzer`) serves all three sources: live broker, `.mqttrec` recording and the topic viewer buffer (§5.1) | Design |
| T12 | Discovery and the check never publish. Nothing in this feature writes to the broker | Design |
| T13 | Limits, as settings: 5,000 topic nodes per documentation, 200 stored instances and 20 parameter examples per template, 3 examples of at most 4 KB per topic (§4.5) | Design |
| T14 | MQTT 5 fields are shown in a `Mqtt5Section` that is disabled for 3.1.1 projects, as in the other dialogs | Design |
| T15 | Exports never contain credentials, client certificates or the client id. The broker address is included only when the user ticks it | Design |
| T16 | Check findings have two severities, **error** and **warning**. A new semantic color `warning` is added to `CustomColors` and the design system | Design |
| T17 | **All documentation features are free**, including the check, AsyncAPI import and export, and the CLI commands. None of them is a commercial add-on (like recorder R23) | User |
| T18 | **Sparkplug B is not decoded in v1.** Discovery recognizes `spBv1.0/…` topics and documents them as `binary` with the note "Sparkplug B". Decoding and metric-level documentation come later | User |
| T19 | **The check runs only in the documentation tab and the CLI.** The topic viewer shows documentation (§8.1) but does not validate messages | User |
| T20 | **AsyncAPI is the only import format.** Exports stay Markdown, HTML, AsyncAPI, JSON Schema and CSV; other tools (Confluence, Excel) take one of those exports | User |

## 3. Current state (for reference)

- `main_appbar.dart` already has the DOCUMENTATION tab (`visible: false`) and the label
  `topicviewerpage.menuitem.documentation`. It becomes `IndexedStack` index 3.
- `RecorderService` builds its own connection from the project's broker settings (client id
  `-rec-<suffix>`) and handles reconnects. That code moves into a shared `SideConnection` (§13)
  so discovery and the check reuse it.
- `PayloadUtils.detectPayloadType` classifies payloads as Text, Number, Json, Image or
  GnssCoordinates. `SummaryBuilder` uses it for recordings, and `IntervalHistogram`
  (`recording_summary.dart`) buckets inter-arrival times logarithmically. Both are reused.
- `RecordingReader` streams the messages of a `.mqttrec` file, and `MQTTMessageBuffer` holds the
  topic viewer's messages.
- `Simulation` and its `PayloadGenerator`s (§9.2) and `SimulationRules` (topic validation) exist.
- There is no YAML package. AsyncAPI import needs `yaml` (pure Dart, read only). Export writes
  YAML with a small writer of its own.

## 4. Domain model

### 4.1 Overview

```
Project
 └─ documentation: TopicDocumentation
     ├─ title, description, owner, revision, discovery settings, ignore filters
     └─ nodes: List<DocNode>                      sorted by path
         ├─ path            'plant/{line}/m{machine}/temp'
         ├─ documented      title, description, status, owner, tags, links, parameters
         ├─ topic?          TopicSpec: payload, delivery, MQTT 5, access   (null = namespace node)
         ├─ observed?       ObservedTopic: statistics from the last discovery
         └─ review          new | changed | notSeen | none, plus editedFields
```

A node is either a **namespace node** (no `topic`, only text) or a **topic node**. In MQTT a
topic can have children (`a/b` and `a/b/c` both carry messages), so a topic node can have
children too. Intermediate paths without a node are shown in the tree as plain path segments.

### 4.2 Classes (persisted, `json_serializable`)

```dart
class TopicDocumentation {
  int formatVersion = 1;
  int revision = 0;                       // +1 on every applied review, edit session or import
  String title = '';
  String description = '';                // Markdown
  String owner = '';
  List<DocNode> nodes = [];
  List<String> discoveryFilters = [];     // none by default (§5.1); remembered for the next discovery and the check
  List<String> ignoreFilters = ['\$SYS/#'];
  DiscoverySettings discoverySettings;    // duration, message limit, options (§5.1)
  DateTime? lastDiscoveryAt;
  DateTime? lastCheckAt;
}

class DocNode {
  String path;                            // template, validated by DocPath (§4.3)
  String title = '';
  String description = '';                // Markdown
  DocStatus status = DocStatus.draft;     // draft, stable, deprecated
  String? replacedBy;                     // path, when deprecated
  String owner = '';
  List<String> tags = [];
  List<DocLink> links = [];               // label + url
  List<DocParameter> parameters = [];     // one per {name} in the path, in path order
  TopicSpec? topic;
  ObservedTopic? observed;
  DocReviewState review = DocReviewState.none;
  Set<String> editedFields = {};          // field keys the user changed (§4.4)
}

class DocParameter { String name; String description; String? pattern; List<String> examples; }

class TopicSpec {
  PayloadSpec payload;
  MqttQos? qos;                           // intended QoS, null = not documented
  RetainMode retain;                      // unknown, never, always, mixed
  IntervalSpec interval;                  // kind (periodic, event, onChange, unknown), nominalMs, staleAfterMs
  Mqtt5Spec mqtt5;                        // contentType, utf8Payload, messageExpirySec, responseTopic,
                                          // correlationData, userProperties: List<DocUserProperty>
  List<String> producers = [];
  List<String> consumers = [];
  String accessNotes = '';
  Sensitivity sensitivity;                // none, personal, confidential, safety
  bool lastWill = false;
}

class PayloadSpec {
  PayloadFormat format;                   // json, number, boolean, string, binary, image, gnss, empty, unknown
  String? unit;                           // for number payloads; JSON fields carry x-unit
  double? min, max;
  List<String> allowedValues = [];        // enums for string and number payloads
  String? encoding;                       // e.g. 'utf-8', 'base64 in JSON', free text for binary
  SchemaNode? schema;                     // json only
  List<DocExample> examples = [];         // payload text (or base64), topic, capturedAt, note
}

class SchemaNode {                        // the JSON Schema subset of §5.4
  SchemaType type;                        // object, array, string, number, integer, boolean, null, mixed
  String description = '';
  String? unit;                           // x-unit
  String? format;                         // date-time, uri, email, uuid
  double? minimum, maximum;
  List<String> enumValues = [];
  Map<String, SchemaNode> properties = {};
  Set<String> required = {};
  SchemaNode? items;
}

class ObservedTopic {                     // never edited by the user
  DiscoverySource source;                 // live, recording (+ name), buffer
  DateTime from, to;
  int messages;
  int instanceCount;
  List<String> instances;                 // the first 200 concrete topics (T13)
  DateTime firstSeen, lastSeen;
  Map<int, int> qosCounts;                // delivered QoS (T10)
  int retainedSnapshot;                   // messages delivered from the retained store
  int retainedLive;                       // live messages with retain set (MQTT 5 only)
  IntervalStats interval;                 // median, p10, p90, min, max per instance; rate per template
  SizeStats size;                         // min, avg, max bytes
  Map<String, int> formats;               // PayloadFormat name -> count
  double? numericMin, numericMax;
  SchemaNode? schema;                     // inferred, with presence counts per field
  Map<String, int> userPropertyKeys;
  Map<String, int> contentTypes;
  String? lastPayload;                    // for the observed panel; text or base64, max 4 KB
}
```

`DocStatus`, `RetainMode`, `IntervalKind`, `PayloadFormat`, `Sensitivity` and `SchemaType` are
enums. No `dynamic`: the schema is typed, and JSON examples are stored as text.

### 4.3 Topic templates (T4)

- A path is a list of `/` separated segments. A segment is either literal (`temp`) or holds one
  parameter `{name}` with an optional literal prefix and suffix (`m{machine}`, `{id}.json`).
  Wildcards `+` and `#` are not allowed in a path. Parameter names are `[a-zA-Z][a-zA-Z0-9_]*` and
  unique within a path.
- A parameter matches one non-empty level. An optional `pattern` (a regular expression, e.g.
  `\d+`) restricts it. `DocPath.matches(topic)` returns the captured parameter values.
- **Precedence:** a concrete topic belongs to the matching template with the most literal
  segments; on a tie, the one whose first difference is literal earlier (`a/b/{x}` beats
  `a/{y}/c` for `a/b/c`). An exact literal node always wins. `DocIndex` holds the compiled
  templates in a trie, so matching costs one walk per message.
- Paths are validated with `SimulationRules`' topic rules plus the template syntax. Two nodes
  may not have the same path, and a template may not be fully covered by another one with the
  same literal count (ambiguous); the editor shows both conflicts as validation errors.
- Renaming a parameter or changing a literal segment of a namespace node moves all nodes below it
  (with a confirmation that names the count).

### 4.4 Documented and observed (T5)

- Each documented field has a key (`payload.format`, `topic.qos`, `payload.schema.$.temp.unit`,
  …). When the user changes a field, its key goes into `editedFields`.
- **Discovery writes observed values only**, with one exception: when it creates a node, or when a
  documented field is empty and its key is not in `editedFields`, it prefills the field from the
  observed value: format, schema, QoS, retain, interval kind and nominal interval, stale
  threshold (3 × the median interval) and two examples. Units, ranges and allowed values are
  never prefilled; the observed range is only a hint.
- Every other difference between a documented and an observed value is a **difference**. The
  review lists it with an "Adopt" checkbox; the editor shows the observed value as helper text
  under the field (`Observed: At least once (100 %)`).
- `review` marks nodes in the tree until the user opens them or clears the marks: `new` (created
  by the last discovery), `changed` (has differences), `notSeen` (inside the discovery filters
  but no message during the last discovery).

### 4.5 Project integration and limits

- `Project.documentation` with `@JsonKey(fromJson: TopicDocumentation.fromJsonOrEmpty)`, so old
  projects load with an empty documentation (like `Simulation.fromJsonOrEmpty`).
- `Project.getHash()` includes the documentation, so edits mark the project as changed and the
  unsaved-changes prompt covers them. Observed values are part of the hash as well: applying a
  discovery is a change the user saves.
- Size: limits of T13 keep a large namespace around a few MB of JSON. When discovery reaches the
  node limit, it stops creating nodes and the review says how many topics were left out.
  Example payloads over 4 KB are cut, with a note.

## 5. Discovery

### 5.1 Sources and settings (T11)

| Source | How | Notes |
|---|---|---|
| **Live broker** | `SideConnection` to the project's broker, subscribe to the filters, listen | Needs an open project. Doesn't need the main connection to be connected |
| **Recording** | `RecordingReader` streams a `.mqttrec` from the library | Uses the recorded receive times, QoS, retain and snapshot flags. Runs as fast as the file reads |
| **Topic viewer** | The messages currently in `MQTTMessageBuffer` | Limited to what the buffer holds. QoS and retain are as delivered to the main connection's subscriptions |

`DiscoverySettings`: filters (several, include and exclude, like the recorder's), stop after a
duration (default 5 min), after N messages, or manually; options: detect templates (on), infer
JSON schemas (on), keep examples (on), ignore `$SYS/#` (on). There is **no default filter**: `#`
on a busy broker would flood the app, so the dialog starts with one empty filter and a discovery
needs at least one include filter. The filters of an applied discovery are remembered in
`TopicDocumentation.discoverySettings` and prefilled next time. Overlapping filters are normalized
like the recorder's (R22) and shared subscriptions are rejected (R21).

### 5.2 Live connection (T9, T10)

- Subscribes every filter with QoS 2 so a message arrives with the publisher's QoS. On MQTT 5 it
  sets Retain As Published, so live messages show the publisher's retain flag, and No Local is
  irrelevant (discovery never publishes, T12).
- The retained snapshot arrives first, right after SUBACK. A message is counted as a snapshot
  message when it has the retain flag and arrives before the first non-retained message on that
  topic or within 2 s of SUBACK. Topics that only send a retained value appear in the snapshot,
  so a short discovery already finds most of the tree.
- On 3.1.1 the broker clears the retain flag of live messages. Retain is then `always` when the
  topic delivered a snapshot value, `unknown` otherwise.
- Reconnect: like the recorder (R7), with the gap marked so it doesn't count as an interval.
- A running discovery shows a status in the command bar (§12.3). One discovery or check at a time
  per app window.

### 5.3 Analyzer

`DocumentationAnalyzer.add(message)` runs per message, keeps a bounded state per concrete topic and
builds `ObservedTopic`s per template at the end (or on every UI refresh, 1/s).

- **Per concrete topic:** count, first and last time, QoS counts, retain counts, size min/avg/max,
  format counts (`detectPayloadType`, mapped to `PayloadFormat`; `true`/`false` and `0`/`1`-only
  topics become boolean, an empty payload is `empty`), numeric min and max, an
  `IntervalHistogram` of inter-arrival times, the user property keys and content types, the
  first and the last payload (for examples).
- **Interval:** the median, p10 and p90 come from the histogram. `periodic` when
  (p90 − p10) / median < 0.4 and at least 5 intervals; `onChange` when consecutive payloads are
  never equal and the topic is not periodic; otherwise `event`. With fewer than 3 messages the
  kind is `unknown`. The template's rate is the sum of its instances' rates.
- **Producers:** if a user property key named `source`, `sender`, `device`, `producer` or
  `client` exists on all messages of a topic, its values are offered as producer suggestions.
- **Per template:** the instance statistics are merged (counts and histograms add, min/max
  combine, medians come from the merged histogram), plus the instance list (T13) and the observed
  values of each parameter.

### 5.4 JSON schema inference (T7)

- Every JSON payload (up to 64 KB, like `SummaryBuilder.maxDetectLength`) is merged into a
  `SchemaNode`: types per path, presence count per property, min/max for numbers, distinct values
  for strings (up to 16), array item schemas merged.
- Result: `required` = properties present in every sample; `enum` when a string field has at most
  8 distinct values over at least 20 samples; `integer` when every number is whole;
  `format: date-time` when every value parses as ISO 8601; a field with several types becomes
  `mixed` (exported as `type: [..]`). Numeric fields get the observed range as `observed`, never
  as `minimum`/`maximum` (those are documented values the user sets).
- Exported as JSON Schema draft 2020-12 with `type`, `properties`, `required`, `items`, `enum`,
  `minimum`, `maximum`, `format`, `description` and `x-unit`. Anything else (`oneOf`,
  `$ref`, patterns) is preserved as raw JSON when imported, shown read-only, and exported
  unchanged.

### 5.5 Template detection (T6)

Runs on the trie of concrete topics at the end of a discovery:

1. For each node with at least 3 children, compute every child's **shape**: the set of relative
   topic suffixes below it, plus whether the child itself carries messages.
2. Children whose shapes are equal or similar (Jaccard ≥ 0.8) form a group. A group with at least
   3 members that covers at least half of the children becomes a **parameter proposal** for that
   level. Literal children with a shape of their own stay literal (`plant/line1/status` next to
   `plant/line1/m12/…`).
3. The members' longest common prefix and suffix become the literal part when the rest is digits,
   hex or a UUID (`m12`, `m51` → `m{…}`), and the pattern is set to `\d+`, `[0-9a-f]+` or the UUID
   pattern; otherwise the whole segment is the parameter without a pattern.
4. The name comes from the parent segment (`machines` → `machine`, `devices` → `deviceId`),
   otherwise `id`, made unique within the path. The user can rename it in the review.
5. The merged group is analyzed again from step 1, so several levels can become parameters
   (`plant/{line}/m{machine}/temp`).
6. Existing templates in the documentation are matched first (§4.3); proposals are only made for
   topics no existing template covers, and for documented literal nodes that now fit a proposal
   ("collapse 24 documented topics into one template", which keeps the first node's text).

### 5.6 Review and apply

At the end, the `DiscoveryResult` is compared with the documentation and the **review dialog**
(§12.5) lists:

| Group | What | Default |
|---|---|---|
| **Templates** | Proposed parameters, with the topics they collapse and the parameter name | Accepted |
| **New** | Templates and topics with no node yet | Accepted |
| **Changed** | Nodes whose observed values differ from documented ones: format, schema (field added, removed, type changed), QoS, retain, interval more than ±50 % off the nominal one, new user property keys, values outside the documented range | Observed values accepted, "Adopt" unticked per difference |
| **Not seen** | Documented topic nodes inside the filters with no message | Mark only |

Rejecting a new topic offers "Ignore in future discoveries", which adds it to `ignoreFilters`.
APPLY writes all accepted items in one step: new nodes (status `draft`, prefilled per §4.4),
observed values for every matched node, adopted differences, review marks, `lastDiscoveryAt`
and `revision + 1`. CANCEL discards the result (it can be reopened until the next discovery
from the command bar's ⋮ "Last discovery result").

### 5.7 Lifecycle and errors

- Starting needs an open project (live source) or a selected recording. The DISCOVER button is
  disabled otherwise, never hidden.
- Connection errors show `errorSnackBar` with the reason code text (`describeReasonCode`).
  Subscribe failures per filter are listed in the status and in the review header.
- Closing or switching the project while discovery runs asks to stop it (like recorder R16);
  stopping keeps the partial result and opens the review.
- Memory: per concrete topic about 1 KB of state plus two payloads. At 100,000 concrete topics
  discovery stops collecting new topics, tells the user, and keeps counting the known ones.

## 6. Editing

- **Tree:** select a node to edit it. Context menu (`more_vert` and right click): add child topic,
  add child namespace, rename or move (path edit with the count of affected nodes), turn a
  segment into a parameter, split a template back into literal topics (from its instances),
  duplicate, delete (confirmation with `SrxDialog.yesNo`), ignore in discovery.
- **Add topic dialog:** path (with `{param}` syntax help and live validation), title, and "copy
  from" an existing node. ADD and ADD & NEW, like the subscribe dialog.
- **Editor:** one scrolling form per node with sections in a fixed order (§12.4). Every field is a
  reactive form control. Changes are applied to the node on field change, like the simulator's
  editors, so the project's unsaved state reflects them.
- **Schema table:** one row per field path (`$.temp`, `$.alarms[].code`): type, unit, minimum,
  maximum, allowed values, required, description. Rows from inference are added automatically;
  the user can add and remove rows. "Edit as JSON" opens the raw schema (validated on save).
- **Examples:** "Pin" in the observed panel copies the observed last payload into the examples;
  the topic viewer's detail view can pin a message too (§9.1).
- **Descriptions:** Markdown text field with a PREVIEW toggle. Links to other topics are written
  as `[label](topic:plant/line1/m{machine}/temp)` and open that node.
- **Bulk edit:** with several nodes selected (Ctrl/Shift click), status, owner, tags and
  sensitivity can be set together.

## 7. Conformance check

The check subscribes to `discoveryFilters` on a `SideConnection` (T9) and validates every message
against the matching node. It runs until stopped, for a duration, or (CLI) for a duration with an
exit code.

| Rule | Severity | When |
|---|---|---|
| Undocumented topic | warning | No template matches (and not ignored) |
| Format mismatch | error | Detected format differs from `payload.format` |
| Schema violation | error | JSON breaks the schema: missing required field, wrong type, value not in enum. The finding names the JSON path |
| Out of range | warning | A number or a schema field is outside `min`/`max` |
| Value not allowed | error | A string or number payload is not in `allowedValues` |
| Parameter mismatch | error | A parameter value breaks its pattern |
| QoS differs | warning | Delivered QoS differs from the documented QoS |
| Retain differs | warning | Retain flag differs from `retain` (MQTT 5, or snapshot on 3.1.1) |
| Stale | error | No message within `staleAfterMs` (checked after the check has run that long) |
| Deprecated in use | warning | A message on a `deprecated` node |
| Expiry / content type differ | warning | MQTT 5 properties differ from the documented ones |

Findings are aggregated per node, instance and rule: count, first and last time, one example
payload and the message. The findings panel (§12.6) lists them; selecting one selects the node.
Results are kept in memory until the next check (not in the project). EXPORT writes them as CSV
or JSON lines.

## 8. Viewer integration with the rest of the app

### 8.1 Topic viewer
- **Detail view (dropped, see §15.1 phase 4):** a "Documentation" section under the topic chip (collapsed when the user
  collapsed it last time): title, the first paragraph of the description, status, and the unit
  next to the payload value. The documented range is drawn as two dashed lines in the chart.
  Actions: OPEN IN DOCUMENTATION, or DOCUMENT for an undocumented topic (creates a node from this
  topic and its message, then switches to the tab). PIN AS EXAMPLE adds the payload to the node.
- **Tree viewer:** the node chip's tooltip shows the documented title.
- **Chart:** the Y axis shows the unit.

### 8.2 Simulator
"CREATE SIMULATION" (⋮ on a node or the selection) adds a device per selected template:

| Documented payload | Generator |
|---|---|
| number with min/max | Random walk between min and max |
| number without range | Random number around the observed range |
| boolean | Bool |
| allowed values | Value list |
| string | Random string, or Timestamp for `date-time` |
| json | Template generator: each schema field mapped with the rules above |
| image | Random image (desktop) |
| gnss | GPS track |

The interval is the nominal interval (event-driven topics get a random interval between p10 and
p90). The first parameter becomes the device's `{n}` with the observed instance count as the
number of instances; other parameters take their first example. QoS and retain come from the
documentation.

### 8.3 Recorder
- The recording list's ⋮ menu gets "Discover documentation", which opens the discover dialog
  with the recording as the source.

## 9. Export and import

### 9.1 Formats

| Format | Content |
|---|---|
| **Markdown** | One file: title, description, broker summary (optional), table of contents by tree, then per node: path, status, description, parameters table, payload (format, unit, range, schema table, examples as code blocks), delivery table, MQTT 5, access, observed statistics (optional) |
| **HTML** | The same content, self-contained, styled with the design system's tokens and a print stylesheet. PDF comes from printing it in a browser |
| **AsyncAPI 3.0** | YAML or JSON (§9.2) |
| **JSON Schema** | One bundle file with a `$defs` entry per JSON topic, keyed by path |
| **CSV** | One row per topic node: path, title, status, format, unit, min, max, QoS, retain, interval kind, nominal interval, stale after, owner, tags, first line of the description |

Options (export dialog): scope (whole documentation, selected subtree, or by status), include
examples, include observed statistics, include the broker address (T15).

### 9.2 AsyncAPI mapping (T8)

| MQTT Studio | AsyncAPI 3.0 |
|---|---|
| title, description, revision | `info.title`, `info.description`, `info.version` (`1.<revision>`) |
| broker (optional) | `servers.broker`: `host`, `protocol` (`mqtt`, `mqtts`, `ws`, `wss`), `protocolVersion` (`3.1.1`, `5`) |
| topic node | `channels.<id>`: `address` = path, `title`, `description`, `messages`, `tags`, `externalDocs` |
| parameter | `channels.<id>.parameters.<name>`: `description`, `examples`; pattern as `x-pattern` |
| payload | `components.messages.<id>`: `payload` (JSON Schema, or `type: number/string/boolean` with `x-unit`, `minimum`, `maximum`, `enum`), `contentType`, `examples` |
| QoS, retain | `operations.<id>` (`action: receive`) `bindings.mqtt`: `qos`, `retain` |
| MQTT 5 properties | message `bindings.mqtt`: `payloadFormatIndicator`, `contentType`, `messageExpiryInterval`, `responseTopic`, `correlationData` |
| status, interval, stale, sensitivity, owner, producers, consumers, last will, access notes | `x-mqttstudio-*` on the channel |
| namespace nodes | `x-mqttstudio-namespaces` on the root |
| observed statistics | `x-mqttstudio-observed` on the channel, only with "include observed statistics" |

`<id>` is the path with `/` and `{}` replaced to form a valid key, kept stable across exports.

### 9.3 Import
- AsyncAPI 3.0 and 2.6 (YAML or JSON). 2.6 channels are keyed by address and their
  `publish`/`subscribe` bindings carry QoS and retain. Unknown parts are skipped and listed.
- The import is shown in the same review dialog as a discovery (new, changed), so importing into
  a filled documentation merges instead of replacing. "Replace all" is an option in the dialog.
- Importing an MQTT Studio export restores everything, including `x-mqttstudio-*` fields.

## 10. CLI

Commands under `doc` (details to be added to `cli-design.md` §7):

```
mqttstudio doc discover -p <project> [--filter <f>]... [--duration 5m] [--count N] [--from-recording <name>] [--apply] [--save]
mqttstudio doc check    -p <project> [--duration 10m] [--fail-on error|warning] [--output text|json]
mqttstudio doc export   -p <project> --format md|html|asyncapi-yaml|asyncapi-json|jsonschema|csv [--out <file>] [--observed] [--broker]
mqttstudio doc import   -p <project> <file> [--replace] [--save]
```

- `discover` prints the review summary. The implementation writes files instead of saving the
  project: `--out <file>` replaces `--apply` and `--save` (§15.1, phase 5).
- `check` exits with 8 (`mismatch`, C6) when a finding at or above `--fail-on` occurs, 0 when
  clean. `--output json` writes one JSON line per finding.

## 11. Commercial scope

Everything is free (T17). No feature is gated, and the app needs no licence check for this tab.

## 12. UI

Screens: see the canvas (§12.9). All text through `en.json` with the prefix `documentationpage.`,
`discoverdialog.`, `docreviewdialog.`, `docexportdialog.`, `docaddtopicdialog.`.

### 12.1 Tab plumbing
- Show the DOCUMENTATION tab (`main_appbar.dart`) as `IndexedStack` index 3, with
  `DocumentationPage` and `DocumentationViewmodel`.
- A running discovery or check shows its status in the tab's command bar only. It needs no app
  bar indicator: it doesn't write anything that could be lost.

### 12.2 Documentation page

```
┌───────────────────────────────────────────────────────────────────────────────────────────────────┐
│ [⌕ DISCOVER] [■] │ [✓ CHECK] [■] │ [+ ADD TOPIC] │ [filter: search……] [All ▾] │      [IMPORT] [EXPORT] [⋮] │
├────────────────────────┬─────────────────────────────────────────────────┬────────────────────────┤
│ Topics      87 · 12 ✎  │ ( plant/{line}/m{machine}/temp            ⧉ )   │ Observed               │
│ ▾ plant                │ Title [Spindle temperature   ]  Status [Stable▾]│ live · 24.10. 09:12    │
│   ▾ {line}             │ Description (Markdown)                          │ 12,340 msgs · 24 inst. │
│     ▾ m{machine}       │ PARAMETERS  line  …   machine  \d+ …            │ interval 1.0 s ±0.1    │
│       ● temp   Stable  │ PAYLOAD  Number  °C  min 0  max 120             │ size 4 B · QoS 1       │
│       ● state  Changed │ DELIVERY QoS 1 · not retained · periodic 1 s    │ ▁▂▅█▅▂▁ histogram      │
│       ● alarms New     │ MQTT 5 (section)                                │ last payload 75.6      │
│   ▸ qa                 │ ACCESS & NOTES                                  │ [PIN AS EXAMPLE]       │
└────────────────────────┴─────────────────────────────────────────────────┴────────────────────────┘
```

- **Topic tree** (left, 320 px, `divider` border, `DocTree`): the path tree with parameter
  segments in italics, a status tag per topic (`Draft`, `Stable`, `Deprecated`), and the review
  marks `New`, `Changed`, `Not seen` as tags. A topic with an empty description shows the
  `edit_note` icon in `ink-hint`. The header shows the counts (topics, undocumented). Empty
  state: the watermark "Topics", like the subscription panel.
- **Editor** (middle, flexible): §12.4. For a namespace node: title, description, owner, tags, and
  a table of the topics below it (path, title, format, interval, status). For the root: the
  documentation's title, description, owner, broker summary, statistics and the last discovery
  and check.
- **Observed panel** (right, 360 px, `ObservedPanel`, can be closed with `close` and reopened
  from ⋮): source and time range, a key/value grid (messages, instances, rate, interval median
  and p10–p90, size, QoS seen, retained), the interval histogram, the value range chart for
  numbers, the instances with their parameter values, user property keys, and the last payload
  in the payload viewer with PIN AS EXAMPLE.

### 12.3 Command bar (`DocumentationCommandBar`)
Same style as `TopicsViewCommandBar`, groups separated by `VerticalDivider`s:
- **Discover:** DISCOVER (`travel_explore`, opens the dialog), stop (`stop`). While running, the
  group shows "DISCOVERING 02:31 · 12,340 messages · 87 topics, 34 new" (`bodyMedium`, tabular
  numbers) and the tree marks new topics live.
- **Check:** CHECK (`rule`), stop. While running: "CHECKING 04:10 · 3 errors · 5 warnings".
- **Edit:** ADD TOPIC (`add`).
- **Filter:** the 300 px "search topics" field (path, title, description, tags) and a dropdown:
  All, Undocumented, New, Changed, Not seen, Deprecated, With findings.
- **Right:** IMPORT (`file_upload`), EXPORT (`file_download`), ⋮ (last discovery result, show
  observed panel, documentation settings).
- DISCOVER, CHECK and ADD TOPIC are disabled without an open project. CHECK is disabled while the
  documentation has no topic nodes.

### 12.4 Topic editor (`TopicDocEditor`)
Sections in this order, `titleSmall` headings, 24 px apart, fields per the dialog rules
(`OutlineInputBorder`, dense, `SrxFormRow`):
1. **Header:** the path as a wide topic chip (topic color of a matching subscription, else
   `topic-group`) with copy and ⋮ (node menu); Title, Status, Owner; Tags; Description with
   PREVIEW; Links.
2. **Parameters:** one row per parameter: name (read-only, renamed from the path), pattern,
   description, observed examples as small tags.
3. **Payload:** Format, Unit, Min, Max, Allowed values, Encoding; for JSON the schema table with
   "EDIT AS JSON"; Examples (code block per example, remove, note).
4. **Delivery:** QoS, Retain, Interval kind, Nominal interval, Stale after; Last will checkbox.
5. **MQTT 5** (`Mqtt5Section`, T14): Content type, UTF-8 payload, Message expiry, Response topic,
   Correlation data, User properties table (key, description, example).
6. **Access & notes:** Producers, Consumers (tag inputs), Sensitivity, Access notes.

Fields with a difference to the observed value show the helper text "Observed: …" with the
`sync_problem` icon and an ADOPT text button.

### 12.5 Dialogs
- **Discover** (640 px): source (Live broker, Recording, Topic viewer) as `ToggleButtons`; the
  broker from the project (read-only) or a recording picker; the filter list (filter, include or
  exclude, ✕, "+ FILTER"); stop after (duration, messages, manually); options (detect templates,
  infer JSON schemas, keep examples, ignore `$SYS`). CANCEL, DISCOVER.
- **Review discovery** (960 × up to 720 px): a summary line ("87 topics in 5 min, 12,340
  messages · 3 templates · 34 new · 5 changed · 3 not seen"), tabs TEMPLATES, NEW, CHANGED, NOT
  SEEN with counts, a list with checkboxes on the left and the selected item's details on the
  right (template: collapsed topics and parameter names; changed: a table field / documented /
  observed / Adopt). CANCEL, APPLY.
- **Add topic** (480 px): path, title, copy from. CANCEL, ADD, ADD & NEW.
- **Export** (480 px): format, scope, options, file name. CANCEL, EXPORT.
- **Import** opens the file picker, then the review dialog.

### 12.6 Findings panel
While a check runs or after it, a 280 px panel docks under the editor and observed panel
(`FindingsPanel`): a sortable table with severity icon (`error` in `error`, `warning_amber` in
the new `warning` color, T16), topic, rule, count, last seen and the detail text. Selecting a
row selects the node; the tree shows a small severity icon on affected nodes. CLEAR, EXPORT and
`close` in the panel header: CLEAR empties the findings and the check goes on (stale topics count
from then), `close` hides the panel after the check stopped. A namespace's menu in the tree has
**Check this branch**: a check of only the documented topics at or below it, listening only to
them. A check listens to the documented topics and the filters of the last applied discovery.

### 12.7 Detail view section (topic viewer, dropped)
Under the topic chip in `MessageDetailView`: "Documentation" (`titleMedium`) with the status tag,
the title (`headlineSmall`), the first paragraph of the description (`bodyMedium`, 3 lines), unit
next to the payload value, and the actions OPEN IN DOCUMENTATION or DOCUMENT, PIN AS EXAMPLE.

### 12.8 Design system
New components, to be added to the design system when built: DocTree, TopicDocEditor (sections),
ObservedPanel, FindingsPanel, DocumentationCommandBar, the review dialog, and the detail view
section. New token `warning` (`#ef6c00`, icons only; text stays `ink`). New icons:
`travel_explore` (discover), `rule` (check), `edit_note` (undocumented), `sync_problem`
(difference to observed), `warning_amber` and `error` (findings), `file_download` (export).

### 12.9 Screens
The canvas "MQTT Studio Topic Documentation" (https://claude.ai/artifact/LnGv7TegEdUt1NtsSqAXAf)
holds the screens. They use the design system's tokens and component styles; the new components
of §12.8 are in its `project/doc.css`. While discovery runs, the observed panel shows the live
discovery statistics instead.
1. Documentation tab with a topic selected (tree, editor, observed panel).
2. Discovery running, root node selected (documentation overview, live "New" marks).
3. Discover dialog.
4. Review discovery dialog (CHANGED tab).
5. Conformance check with the findings panel.
6. Export dialog.
7. Topic viewer detail view with the Documentation section.

## 13. Files

```
lib/documentation/
  model/                       topic_documentation.dart, doc_node.dart, topic_spec.dart, payload_spec.dart,
                               schema_node.dart, observed_topic.dart (+ .g.dart)
  engine/
    doc_path.dart              template parsing, validation, matching (§4.3)
    doc_index.dart             trie of templates for fast matching
    documentation_analyzer.dart  per-topic state, interval classification, observed values (§5.3)
    schema_inferrer.dart       JSON schema inference (§5.4)
    template_detector.dart     parameter proposals (§5.5)
    discovery_service.dart     sources, SideConnection, lifecycle (§5.1, §5.2, §5.7)
    discovery_merger.dart      review items and apply (§4.4, §5.6)
    conformance_checker.dart   rules and findings (§7)
    simulation_builder.dart    documentation → Simulation (§8.2)
  export/                      markdown_exporter.dart, html_exporter.dart, asyncapi_exporter.dart,
                               asyncapi_importer.dart, json_schema_exporter.dart, csv_exporter.dart, yaml_writer.dart
  documentation_page.dart, documentation_viewmodel.dart
  discover_dialog.dart, discover_viewmodel.dart
  review_dialog.dart, review_viewmodel.dart
  add_doc_topic_dialog.dart, add_doc_topic_viewmodel.dart
  export_dialog.dart, export_viewmodel.dart
  widgets/                     doc_tree.dart, topic_doc_editor.dart, schema_table.dart, observed_panel.dart,
                               findings_panel.dart, documentation_command_bar.dart, doc_detail_section.dart
lib/mqtt/side_connection.dart  extracted from RecorderService (T9)
lib/cli/commands/doc_command.dart
test/documentation/
```

Changes elsewhere: `project.dart` (field), `main_appbar.dart` (tab), `message_viewer_page.dart`
(`IndexedStack` child), `message_detail_view.dart` (section), `custom_theme.dart` (`warning`),
`recorder_service.dart` (uses `SideConnection`), `recording_list.dart` (menu item), `main.dart`
(GetIt registrations), `pubspec.yaml` (`yaml`), `en.json`.

## 14. Testing

- `DocPath`: parsing, validation errors, matching with prefix/suffix and patterns, precedence.
- `SchemaInferrer`: required vs optional, enums, integer, date-time, mixed types, nested arrays.
- `DocumentationAnalyzer`: interval classification (periodic, event, onChange) from synthetic
  timestamps, retain snapshot detection, boolean detection.
- `TemplateDetector`: the demo-factory tree, literal siblings that must stay literal, multi-level
  templates, prefix/suffix and pattern derivation, existing templates take precedence.
- `DiscoveryMerger`: edited fields are never overwritten, empty fields are prefilled, differences
  and not-seen marks, ignore filters.
- `ConformanceChecker`: one test per rule.
- Exporters: golden files for Markdown, CSV and AsyncAPI; AsyncAPI round trip (export → import →
  equal documentation); import of a 2.6 sample.
- Discovery from a `.mqttrec` file end to end, and the CLI commands with a fake broker like the
  recorder tests.

## 15. Implementation phases

1. **Model and editor:** model, `DocPath`, tab, tree, editor, add topic, project integration.
2. **Discovery:** `SideConnection`, analyzer, schema inference, template detection, review and
   merge, all three sources.
3. **Export and import:** Markdown, HTML, CSV, JSON Schema, AsyncAPI export and import.
4. **Check and integration:** conformance check, findings panel, detail view section, simulator
   and recorder links.
5. **CLI:** `doc discover`, `check`, `export`, `import`.

## 15.1 Implementation notes (2026-10-24)

All five phases are implemented in `lib/documentation/` (the CLI in `lib/cli/commands/doc_command.dart`); tests in
`test/documentation/` and `test/cli/doc_cli_test.dart`.

**Phase 1 (model and editor)**


- **Model:** `model/topic_documentation.dart` (`TopicDocumentation`, `DocNode`, `DocLink`, `DocParameter`) and
  `model/topic_spec.dart` (`TopicSpec`, `PayloadSpec`, `SchemaNode`, `IntervalSpec`, `Mqtt5Spec`, `DocUserProperty`,
  `DocExample`). `Project.documentation` loads old projects through `TopicDocumentation.fromJsonOrEmpty`.
- **`IntervalKind`** has a fifth value, `periodicAndOnChange`, for topics that send on a timer and on every change.
- **Edited fields** are keyed by the editor's form control names (`title`, `qos`, `nominalInterval`, …) and
  `schema:<field path>` for schema fields, not by dotted paths as §4.4 suggests: reactive_forms reads dots as nesting.
- **Engine:** `engine/doc_path.dart` (parsing, validation, matching, `compareSpecificity`), `engine/doc_index.dart`
  (trie of templates, §4.3), `engine/doc_tree.dart` (the tree with implicit namespaces and counts) and
  `engine/schema_paths.dart` (field paths `$.a.b`, `$.list[]`). Ambiguity (§4.3) is checked as "same shape": two
  templates that match exactly the same topics. Other overlaps are resolved by precedence.
- **Service:** `DocumentationService` (GetIt) adds, moves (with everything below, parameters carried over by
  position), deletes, duplicates and converts nodes, and broadcasts `documentationChangedEvent`.
- **UI:** `DocumentationPage` with `DocumentationCommandBar` (ADD TOPIC, search with 300 ms debounce, filter All /
  Undocumented / Draft / Stable / Deprecated), `DocTree` (320 px, context menu on right click and in the editor's ⋮),
  `TopicDocEditor` (all sections of §12.4), `DocOverview` (root) and `SchemaTable`. Dialogs: `DocPathDialog` (add topic,
  add namespace, rename or move) and `SchemaFieldDialog`. `ReactiveTagField` edits tags, allowed values, producers and
  consumers. `NumberValueAccessor` moved from the generator editor to `common/utils/` for reuse. New color
  `CustomColors.topicGroup`.
- **Not yet:** the Markdown PREVIEW of descriptions (no Markdown package in the app), bulk edit of several nodes,
  and `[label](topic:…)` links. EDIT AS JSON came with phase 3.

**Phase 2 (discovery)**

- **`SideConnection`** (`lib/mqtt/side_connection.dart`) holds the own connection, the client id tag
  (`-rec-`, `-doc-`), the reconnect delays and resubscribing. `RecorderService` uses it now; its behaviour is unchanged.
- **Model:** `model/observed_topic.dart` with `ObservedTopic`, `ObservedInterval` and `DiscoverySettings` (filters are
  `RecorderFilter`s, normalized with `RecorderRules` like the recorder's). `DocNode` got `observed` and `review`
  (`DocReviewState`: none, added, changed, notSeen), `TopicDocumentation` got `discoverySettings`, `ignoreFilters` and
  `lastDiscoveryAt`. `Project.getHash()` leaves the review marks out, so opening a marked topic (which clears its mark)
  doesn't ask to save.
- **Engine:** `ClassifiedPayload` and `DocumentationAnalyzer` (§5.3; intervals from the last 32 per concrete topic
  instead of a histogram, exact enough for percentiles at a bounded size), `SchemaInferrer` (§5.4), `TemplateDetector`
  (§5.5) and `DiscoveryMerger` (comparison, review items, prefill and apply, §4.4 and §5.6). Template detection
  differs from §5.5 in two ways: two numbered siblings with identical subtrees (`area1`, `area2`) also become a
  parameter, and sibling leaves are only collapsed when their names follow a pattern (digits, hex, UUID), so
  `temp`, `speed` and `state` stay separate topics.
- **Service:** `DiscoveryService` (GetIt) runs one discovery from a live broker, a recording or the topic viewer
  buffer, stops by duration, message count or by hand, and keeps the last result until it is applied or the next
  discovery starts. Closing the project cancels a running discovery without a result instead of asking (§5.7).
- **UI:** DISCOVER and stop in the command bar with a live status and progress, `DiscoverDialog`, `ReviewDialog`
  (opens when a result is ready; REVIEW reopens it), review tags in the tree and filters New / Changed / Not seen,
  `ObservedPanel` (360 px, closable, reopened from the editor header) and "Observed: …" helper texts on format, QoS,
  retain, nominal interval and minimum.
- **Not yet:** live "New" marks in the tree while a discovery runs (the status counts new topics instead), and showing the observed interval histogram (the
  panel shows min, p10–p90 and max instead).

**Phase 3 (export and import)**

- **Export** (`export/`): `DocExport.run` writes Markdown and HTML from one block model (`DocBlocks`: table of
  contents with anchors, facts, tables, code blocks), AsyncAPI 3.0 as YAML (`YamlWriter`, own writer) or JSON
  (`AsyncApiExporter`), a JSON Schema bundle and CSV (`CsvExporter`). `SchemaJson` converts payloads and schemas to
  JSON Schema and back. The exported texts are English: they are documents, not app UI, and the CLI (phase 5) writes
  them without the app's translations. Channel ids are the path with other characters replaced by `_`, made unique
  with a number. Credentials, certificates and the client id are never written (T15).
- **HTML** shows descriptions as plain paragraphs, not rendered Markdown (no Markdown package). It is styled like the
  app and has a print stylesheet for PDF.
- **Import** (`AsyncApiImporter`, `yaml` package): AsyncAPI 3.x and 2.x, YAML or JSON, local `$ref`s, `x-mqttstudio-*`
  extensions; in 2.x the operation summary becomes the title. Schema keywords outside the subset (§5.4) are left out
  and listed as warnings instead of kept as raw JSON. An MQTT Studio export imports again without loss (tested).
- **Import dialog instead of the review dialog** (§9.3): imported topics are documentation, not observations, so they
  get a dialog of their own (`ImportDialog`, `ImportPlan`): new, changed, unchanged and conflicting topics (a
  documented template with the same shape), a checkbox per new or changed topic, and "Replace the whole
  documentation". Changed topics take the imported texts and keep their observed values; replacing keeps observed
  values of topics with the same path.
- **UI:** IMPORT and EXPORT in the command bar, `ExportDialog` (format, whole documentation or the selected subtree,
  examples, observed statistics, broker address, file name that follows the format) and EDIT AS JSON in the schema
  table (`SchemaJsonDialog`). Files are saved with the file picker on the desktop and downloaded in the browser.

**Phase 4 (check and integration)**

- **Engine:** `SchemaValidator` checks a JSON value against a `SchemaNode` (type, enum, range, required, properties,
  items; `null` passes for every type, as discovery infers optional fields). `ConformanceChecker` applies the rules
  of §7 and aggregates findings per concrete topic and rule (schema findings also per JSON path). Its detail texts are
  English, like the exports and the CLI. Without a discovery its filters are the documented topics with `+` for
  parameters. `DocIndex(patterns: false)` matches templates without their parameter patterns, so a value that breaks
  a pattern is a parameter mismatch instead of an undocumented topic.
- **Service:** `CheckService` (GetIt) runs one check on its own `SideConnection` (client id tag `-chk-`), checks
  stale topics every second and keeps the findings in memory until the panel is closed or the next check starts. A
  check and a discovery don't run at the same time in the tab.
- **UI:** CHECK and stop with a live status in the command bar, `FindingsPanel` (280 px under the editor, counts,
  EXPORT as CSV, a click selects the topic), severity icons in the tree and the filter "With findings". New color
  `CustomColors.warning`.
- **Topic viewer:** the tree viewer's chips have the documented title as tooltip. The detail view's documentation
  section (§8.1, §12.7) was built and then removed again on request: the detail view stays as it was, without
  OPEN IN DOCUMENTATION, DOCUMENT, PIN AS EXAMPLE or the documented unit. `DocumentationService.requestDiscover`
  switches the main window to the tab for the recorder's "Discover documentation".
- **Simulator:** "Create simulation" in a node's menu adds a device per documented topic at or below it
  (`SimulationBuilder`, §8.2). Event-driven topics get a random interval between p10 and p90 of the observation, else
  between the nominal interval and three times it. A string topic gets a random string; `date-time` maps to a
  timestamp inside JSON templates only.
- **Recorder:** "Discover documentation" in the recording list's menu.
- **Not yet:** the documented range as dashed lines in the chart and the unit on its Y axis, and exporting findings as JSON lines in the app (the CLI writes them).

**Phase 5 (CLI)**

- `mqttstudio doc discover|check|export|import`, see `cli-design.md` §7.3. They use `DiscoveryService` and
  `CheckService` without the app's projects, like `record` uses the `RecorderService`.
- **Deviation from §10:** the CLI never writes to the project store (cli-design C2), so there is no `--save`.
  `discover --out <file>` applies the result with the review defaults (§5.6) and `import --out <file>` merges; both
  write the documentation as an MQTT Studio AsyncAPI file that the app's IMPORT reads back without loss.
  `--apply` is implied by `--out`.

## 16. Known limitations

- Producers and consumers can't be discovered (MQTT hides the publisher).
- On MQTT 3.1.1, the retain flag of live messages is unknown (T10).
- Delivered QoS is the minimum of the publish and the subscribe QoS, and brokers may downgrade it
  (for example AWS IoT has no QoS 2), so the observed QoS can be lower than the published one.
- A short discovery classifies slow topics as `unknown` and may miss event-driven topics.
- Template detection is a heuristic. It needs at least 3 instances and similar subtrees.
- Binary formats (Protobuf, Sparkplug B, CBOR) are not decoded.

## 17. Open questions

None. The former questions are decided:

| # | Question | Decision |
|---|---|---|
| Q1 | Free, or are parts commercial add-ons? | All free (T17) |
| Q2 | Store the documentation in the project, or in a separate shared file? | In the project (T3) |
| Q3 | Decode Sparkplug B in v1? | Later (T18) |
| Q4 | Run the check in the topic viewer too? | Documentation tab and CLI only (T19) |
| Q5 | Which exchange formats do customers need? | AsyncAPI only (T20) |
