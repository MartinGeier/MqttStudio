# VDA 5050 Support – Detailed Design

Status: **Draft**. Scope and the former open questions are decided (V1, V5, V7, V13, V14, V16, V17); the other
decisions are proposed, see §2 and §18. Phases 0 (simulated robots), 1 (presets), 2 (profile engine and rules),
3 (topic viewer) and 4 (fleet view) are implemented, see §16.1 · Branch: `mqtt5` · Last updated: 2026-10-26

Related: `documentation-design.md` (presets go through the AsyncAPI import, protocol rules extend the check, T19),
`recorder-design.md` (JSON paths and conditions, §10; `MessageSource`, §7.2), `simulator-design.md` (no
request/response simulation) and `cli-design.md` (`doc` commands).

## 1. Purpose

VDA 5050 is the open interface between mobile robots (AGVs, AMRs) and a fleet control (master control), published
by VDA and VDMA. It runs on MQTT with JSON payloads and a fixed topic layout, so MQTT Studio already receives it.
But a VDA 5050 `state` message is a large JSON document with nested arrays, and the topic name alone says nothing
about what a robot is doing. Today users read raw JSON to answer "why did robot 0001 stop?".

This feature makes MQTT Studio understand VDA 5050: the topic viewer shows what each message means, a fleet view
shows all robots at a glance, the documentation tab gets a ready-made VDA 5050 documentation, and the check finds
protocol violations. It is built on a generic **protocol profile** layer, so other protocols (Sparkplug B, T18) can
follow without touching the viewers again.

Two major versions are in use: 2.x (2.0 from 2022, 2.1) in most installed fleets, and 3.0 (released March 2026),
which adds freely navigating robots, zones, shared paths and requests, and renames many fields. Plants will run
both for years, often side by side, so MQTT Studio supports both (V14).

Typical uses: commissioning a fleet control against robots from several manufacturers, testing a robot's
VDA 5050 implementation before an acceptance test, migrating a fleet from 2.x to 3.0, support and troubleshooting
in a running plant.

### Goals (v1)
- Detect VDA 5050 messages by their topic and header, without any setting, for versions 2.x and 3.0.
- Show a one-line **summary** per message in the topic viewer (`0001 | AUTOMATIC | DRIVING | 78 % | order 4711
  node 5/12 | 2 errors`) and mark messages in which the robot reports a warning or an error.
- Show an **interpreted detail view** per message type: status, errors, action states, order progress, nodes and
  edges, and for 3.0 paths, zones, requests and responses, with a switch back to the raw payload.
- Chart the numeric values of a message type (state of charge, velocity, position) in the detail view.
- A **fleet view**: all robots in a table with connection, mode, battery, order and errors, and their positions on
  a 2D plane per map, with the selected robot's order and, for 3.0, its planned path and the zones drawn.
- **VDA 5050 documentation presets** (v2 and v3) for the documentation tab: topic templates, JSON schemas, QoS,
  retain and the state heartbeat, imported through the existing AsyncAPI import.
- **Protocol rules** for the documentation check and the CLI: header consistency, header id sequence, timestamp
  skew, order structure and order updates, and for 3.0 the request/response pairing.
- **Simulated robots** in the simulator: a fleet of 2.x or 3.0 robots that drive orders on a grid layout, with
  fault injection, so every other goal can be tried without a real VDA 5050 system (§10).
- Versions 2.0, 2.1 and 3.0; 1.1 is read where the fields are the same as in 2.0 (§6.6).

### Non-goals (v1)
- Simulated robots that follow orders from an outside fleet control. The v1 simulation plays both sides (§10.1);
  following outside orders needs subscriptions in the simulator (§10.7).
- Acting as a fleet control: MQTT Studio does not plan routes, grant zone requests or send orders. Users can still
  send any message with the publish dialog, prefilled from a received one.
- Validating messages in the topic viewer (T19). The topic viewer shows what a robot reports; protocol violations
  are found by the check in the documentation tab and the CLI (V5).
- Converting messages between 2.x and 3.0.
- Layout backgrounds (VDMA LIF files, CAD drawings) in the fleet view.
- Robot-specific extensions beyond showing unknown fields as raw JSON.
- A time slider for the fleet view of recordings (later, §16).

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| V1 | **Interpret VDA 5050 messages in the topic viewer** | User |
| V2 | Interpretation is a generic **protocol profile** layer (`lib/protocol/`). VDA 5050 is the first profile; the viewers know profiles, not VDA 5050 | Design |
| V3 | A profile **detects** its messages from the topic first (cheap, cached per topic) and only then parses the payload. No setting, no project field. The user can switch a topic back to the raw payload for the session | Design |
| V4 | Interpreting **only reads**. It never changes messages, the buffer, filters or the project. Results are cached per message like decoded payloads | Design |
| V5 | The topic viewer shows what a message says, including the errors the robot reports itself, but **does not check the protocol** (keeps T19), not even header id gaps or a missing heartbeat. Protocol rules run in the documentation check and the CLI | User |
| V6 | Messages are read **tolerantly**: missing fields are blank, unknown fields are shown as raw JSON, wrong types and unknown enum values are shown as sent (3.0 enums are extensible). The interpreter never rejects a message; that is the check's job | Design |
| V7 | The fleet view is a fourth **view mode** of the topic viewer ("Fleet"), next to Grouped, Tree and Sequential. It is disabled, not hidden, while the buffer holds no VDA 5050 messages. No tab of its own | User |
| V8 | Robot positions are local coordinates in meters on a `mapId`, so the fleet view draws them on a **plain 2D canvas per map**, not on OpenStreetMap | Design |
| V9 | The documentation presets are **built in code from the official JSON schemas**, which are bundled unchanged as assets (one folder per version), and imported through the existing import and review (documentation-design §9.3). Version and interface name are chosen in the dialog | Design |
| V10 | The presets document QoS, retain and the state heartbeat, so the existing check rules (QoS differs, retain differs, stale) cover them. Protocol rules only add what documentation can't express (§9.3) | Design |
| V11 | Status colors come from the theme: `error` for errors, `custom.warning` for warnings, `custom.connectedColor` for `ONLINE`, `custom.disconnectedColor` for `OFFLINE` and a broken connection, `custom.watermark` for hibernating and unknown. No new tokens | Design |
| V12 | Protocol terms (`DRIVING`, `FATAL`, `CONNECTION_BROKEN`, field names) are shown as sent and not translated. Labels around them are localized | Design |
| V13 | **All VDA 5050 features are free**, including the interpreter, the fleet view, the presets, the protocol rules and the CLI options. None of them is a commercial add-on (like recorder R23 and documentation T17) | User |
| V14 | **Support VDA 5050 3.0 as well as 2.x.** One profile reads both; the major version comes from the topic and the header. The UI uses one set of labels for both and shows a field only when the message's version has it | User |
| V15 | One **version-neutral model**: `vda5050_reader.dart` maps 2.x and 3.0 field names onto the same read-only views (§6.6), so summaries, sections, fleet view and rules are written once. Version-specific parts (paths, zones, requests, responses) are optional in the model | Design |
| V17 | **The simulator simulates VDA 5050 robots** as a third device kind (simulator D26), built first (phase 0) so the other phases can be tested against it | User |
| V18 | In v1 the simulation is **self-contained**: it plays a minimal fleet control and the robots, and publishes every topic. Following outside orders comes later | Design |
| V19 | **Fault injection** per robot while running: robot, connection and protocol faults. Runtime only, not saved | Design |
| V20 | "Connection broken" is **published by the simulator** as the broker would publish the last will; no connection per robot in v1 | Design |
| V21 | The simulated robots write messages through a `Vda5050Writer` on the version-neutral model, so the writer and the reader (V15) are tested against each other and the official schemas | Design |
| V16 | **Later 3.x versions (3.0.x patches, 3.1) are handled in the 3.0 reader**, not by a reader of their own. Additions it doesn't know yet show as Other fields until they are supported | User |

## 3. VDA 5050 in short (for reference)

Topic: `{interfaceName}/{majorVersion}/{manufacturer}/{serialNumber}/{topic}`, e.g. `uagv/v2/KUKA/0001/state` or
`vda5050/v3/KIT/0001/state`. The interface name is chosen by the plant (`uagv` was the usual default for 2.x, the 3.0
text uses `vda5050`); the major version is `v1`, `v2` or `v3`. The topic names are mandatory, the levels in front
may be adapted for cloud brokers.

| Topic | Direction | Content | Versions | QoS | Retain |
|---|---|---|---|---|---|
| `order` | fleet → robot | `orderId`, `orderUpdateId`, `nodes[]` (even `sequenceId`), `edges[]` (odd `sequenceId`). Released nodes and edges are the **base**, the others the **horizon**. Nodes and edges carry `actions[]` | all | 0 | no |
| `instantActions` | fleet → robot | `actions[]` (`instantActions` in 1.1): pause, cancel order, init position, factsheet request, … | all | 0 | no |
| `state` | robot → fleet | operating mode, driving, paused, position, velocity, battery, safety state, order progress (`lastNodeId`, `nodeStates[]` and `edgeStates[]` still to traverse), action states, loads, `errors[]`, `information[]`. Sent on every relevant change and at least every 30 s | all | 0 | no |
| `visualization` | robot → fleet | position and velocity at a higher rate. In 3.0 also `plannedPath`, `intermediatePath` and `referenceStateHeaderId` (the state it is based on), and usable for traffic control | all | 0 | no |
| `connection` | robot / broker → fleet | `connectionState`, retained, the broken state is the last will | all | 1 | yes |
| `factsheet` | robot → fleet | type, physical parameters, protocol limits and features, geometry, load specification | 2.0+ | 0 | — |
| `zoneSet` | fleet → robot | a zone set (`zoneSetId`, one `mapId`, `zones[]`): blocked areas, speed limits, one-way and priority rules, areas that need permission | 3.0 | 0 | — |
| `responses` | fleet → robot | `responses[]`, each answering one request of the robot's state by `requestId` with `grantType` `GRANTED`, `QUEUED`, `REVOKED` or `REJECTED`, optionally a `leaseExpiry` | 3.0 | 0 | — |

Every message starts with the header `headerId` (uint32, incremented per topic by the sender), `timestamp`
(ISO 8601, UTC; milliseconds in 3.0, hundredths in 2.x), `version` (`2.0.0`, `3.0.0`), `manufacturer` and
`serialNumber`.

An order update keeps the `orderId` and increases `orderUpdateId`; its first node is the last base node of the
previous update (the stitching node). In 3.0 the first message of an order always has `orderUpdateId` 0, a cancelled
order must not be updated, and a repeated `orderUpdateId` must have the same content.

**What 3.0 changes for this feature** (from the 3.0.0 change log and specification):

- **Enums:** operating modes add `STARTUP` and `INTERVENED` (`TEACHIN` becomes `TEACH_IN`); error levels are
  `WARNING`, `URGENT`, `CRITICAL`, `FATAL`; action status adds `RETRIABLE`; blocking type adds `SINGLE`; connection
  states are `ONLINE`, `OFFLINE`, `HIBERNATING`, `CONNECTION_BROKEN`. Enums are extensible.
- **State:** `instantActionStates` and `zoneActionStates` are split off `actionStates`; new `plannedPath`,
  `intermediatePath`, `zoneRequests`, `edgeRequests`, `zoneSets`, `maps`; errors get `errorDescriptionTranslations`
  and `errorHintTranslations`.
- **Renames (breaking):** the `…Description` fields of nodes, edges, actions and maps become `…Descriptor`,
  `resultDescription` → `actionResult`, `agvPosition` → `mobileRobotPosition`, `positionInitialized` → `localized`,
  `batteryState` → `powerSupply`, `batteryCharge` → `stateOfCharge`, `eStop` → `activeEmergencyStop` (no `AUTOACK`),
  `rotationAllowed` → `reachOrientationBeforeEntering` (inverted), edge height limits → `maximumMobileRobotHeight`
  and `minimumLoadHandlingDeviceHeight`, `maxSpeed` → `maximumSpeed` (but `maxRotationSpeed` stays); edges no longer
  have `startNodeId` and `endNodeId` (the sequence ids connect them); the order and the state lose `zoneSetId`, the
  state gets `zoneSets[]`; factsheet sections are renamed (`agvGeometry` → `mobileRobotGeometry`, `speedMax` →
  `maximumSpeed`, `maxStringLens` → `maximumStringLengths`, …). Zone requests have the status `REQUESTED`, `GRANTED`,
  `REVOKED` or `EXPIRED`.
- **New instant actions:** `startHibernation`, `stopHibernation`, `shutdown`, `updateCertificate`, `trigger`,
  `retry`, `skipRetry`, `clearInstantActions`, `clearZoneActions`.

Sources: the specification and JSON schemas at `github.com/VDA5050/VDA5050` (MIT licence; branch `main` holds
3.0.0, earlier versions are tagged), the 3.0.0 change log (discussion #596). The PDF on the VDA website is the
normative text where the Markdown or the schemas differ. **The field names in this note were read from the
Markdown and the change log; the implementation follows the JSON schemas of each version** and the tests use
samples that validate against them.

## 4. Current state (for reference)

- `PayloadDecoding` (`common/utils/payload_decoder.dart`) turns bytes into data (text, hex, Base64, gzip,
  MessagePack, CBOR), chosen per topic in `MessageViewerViewmodel.decoderOf`, cached per message with an `Expando`.
  Interpretation sits one step later: decoded data in, meaning out.
- `FastTopicChip` paints only the topic. The sequential row shows time and chip; the tree shows the chip, the
  documented title as tooltip and the topic statistics; the grouped viewer shows chips in a `Wrap`.
- The detail view (`message_detail_view.dart`) shows toolbar, chip, info rows, MQTT 5 properties, the payload with
  the decoder dropdown, changes since the previous message, and a chart of the last 100 **numeric** payloads
  (`getChartValues`). JSON fields can't be charted in the topic viewer yet (the recorder's CHARTS tab can).
- The command bar filter's Condition mode accepts the `MessageCondition` syntax without a topic filter, so
  `$.batteryState.batteryCharge < 20` already filters 2.x state messages. JSON paths have no wildcards.
- `MessageSource` feeds the viewer widgets from the live buffer or a recording.
- The documentation tab imports AsyncAPI 2.x/3.x (`AsyncApiImporter`, `ImportPlan`, review dialog), follows
  references inside the document, and turns JSON Schema into `SchemaNode`s (type, enum, range, required,
  properties, items, `date-time`; several types become `mixed`). `ConformanceChecker` applies the rules of
  documentation-design §7, including stale topics, QoS and retain.

## 5. Protocol profiles (V2, V3, V4)

### 5.1 Interface

```dart
abstract class ProtocolProfile {
  String get id;                                   // 'vda5050'
  String get name;                                 // 'VDA 5050'

  // from the topic alone; null when the topic can't belong to this profile
  ProtocolTopic? matchTopic(String topic);

  // null when the payload doesn't confirm the match (e.g. no VDA 5050 header)
  Interpretation? interpret(ProtocolTopic topic, Object? data, InterpretationContext context);

  // protocol rules for the documentation check (§9.3); empty for profiles without rules
  List<ProtocolRule> get rules;
}

class ProtocolTopic {
  final ProtocolProfile profile;
  final String messageType;                        // 'state', 'order', …
  final String deviceKey;                          // 'uagv/v2/KUKA/0001', groups the topics of one device
  final Map<String, String> parameters;            // interfaceName, majorVersion, manufacturer, serialNumber
}

class Interpretation {
  final String protocolVersion;                    // from the header, e.g. '3.0.0'; shown in the detail view
  final String summary;                            // one line, plain text
  final InterpretationLevel level;                 // none, warning, error: what the device reports
  final List<InterpretedSection> sections;         // detail view
  final Map<String, double> values;                // chartable values by label, e.g. 'State of charge %': 78
}

abstract class InterpretationContext {
  // the last message of a sibling topic of the same device, e.g. the order for a state
  ReceivedMqttMessage? lastMessage(String deviceKey, String messageType);
  Object? decode(ReceivedMqttMessage message);
}
```

`InterpretedSection` is data, not widgets, so the engine is testable without Flutter and the CLI could print it:
`KeyValueSection` (label, value, optional level), `TableSection` (columns, rows, a level per row) and `RawSection`
(JSON). Every section has a stable `key` for its collapsed state.

### 5.2 Registry and caching

`ProtocolRegistry` (GetIt) holds the profiles in a fixed order and caches `matchTopic` per topic string
(`Map<String, ProtocolTopic?>`, cleared when the buffer is cleared). `MessageViewerViewmodel.interpret(message)`
decodes with the topic's decoder, asks the matched profile and caches the result in an `Expando` like `decode`.
Interpretation runs lazily for what is on screen: visible rows, the selected message and the fleet view's input.

A topic the user switched to raw (`setInterpreted(topic, false)`) is not interpreted for the session, like the
decoder choice.

## 6. VDA 5050 profile

### 6.1 Detection

- **Topic:** at least five levels; level −4 matches `v\d+`; the last level is one of `order`, `instantActions`,
  `state`, `visualization`, `connection`, `factsheet`, `zoneSet`, `responses`. Only the last five levels are used, so
  a plant prefix in front of the interface name still matches. `deviceKey` is the topic without the last level.
- **Payload:** a JSON object with `headerId`, `manufacturer` and `serialNumber`. Otherwise `interpret` returns null
  and the message is shown as before.
- **Version:** the major version of the header's `version` selects the reader (`1`, `2` → 2.x reader, `3` → 3.0
  reader). Without a usable `version`, the topic's version level decides. An unknown higher major version is read
  with the newest reader (V6).

### 6.2 Summaries

| Type | Summary |
|---|---|
| `state` | `{serialNumber} \| {operatingMode} \| DRIVING/STOPPED[/PAUSED] \| {stateOfCharge} % [charging] \| order {orderId}#{orderUpdateId} at {lastNodeId} [{done}/{total}] \| {n} errors [\| {r} open requests]` |
| `order` | `order {orderId}#{orderUpdateId} \| {nodes} nodes ({base} base, {horizon} horizon) \| {actions} actions` |
| `instantActions` | the action types, comma separated: `startPause, cancelOrder` |
| `visualization` | `x {x} y {y} θ {theta}° \| {speed} m/s \| {mapId}` |
| `connection` | `{connectionState}` |
| `factsheet` | `{seriesName} \| {kinematic} \| max {speedMax} m/s` |
| `zoneSet` (3.0) | `zone set {zoneSetId} \| {mapId} \| {n} zones` |
| `responses` (3.0) | `{requestId} {responseType}`, comma separated, e.g. `r-17 GRANTED, r-18 QUEUED` |

The labels are the 3.0 terms; the values come from the version-neutral model (§6.6), so `{stateOfCharge}` is
`batteryState.batteryCharge` in a 2.x message. Parts whose fields are missing are left out. `[{done}/{total}]` needs
the robot's last order (from the context): total is the number of base nodes, done is total minus the base nodes
still in `nodeStates`. Without an order it is left out. "Open requests" are 3.0 zone and edge requests without a
final response.

Level: `error` when `errors[]` holds `FATAL` or `CRITICAL`, `warning` when it holds `URGENT` or `WARNING`. For
`connection`: `error` for a broken connection, `warning` for `OFFLINE`, `none` for `ONLINE` and `HIBERNATING`. For
`responses`: `warning` when one is `REJECTED` or `REVOKED`.

### 6.3 Detail sections

| Type | Sections |
|---|---|
| `state` | **Errors** (table: level, type, description, hint, references; first, only when present; a translation in the app's language when the message has one, else the description as sent) · **Status** (operating mode, driving, paused, emergency stop, field violation, state of charge, voltage, current (3.0), charging, range, new base request) · **Position** (x, y, θ, map, localized, localization score, velocity) · **Order** (order id and update id, last node and its sequence id, base nodes done/total, nodes and edges still to traverse) · **Actions** (table: type, id, status, result; `FAILED` as error, `RETRIABLE` as warning, `RUNNING` bold) · **Instant actions** and **Zone actions** (3.0, same table) · **Requests** (3.0: zone and edge requests with type, zone or edge, status and the last response from `responses`) · **Paths** (3.0: planned and intermediate path, point count and length) · **Loads** · **Information** |
| `order` | **Order** (ids, zone set) · **Route** (table in sequence order: sequence id, node or edge id, released, position, max speed, actions; horizon rows in `watermark` grey) · **Actions** (table: where, type, id, blocking type, parameters) |
| `instantActions` | **Actions** (table: type, id, blocking type, parameters) |
| `visualization` | **Position** · **Paths** (3.0) · the referenced state header id (3.0) |
| `connection` | **Connection** (state, colored per V11) |
| `factsheet` | one key-value section per top-level object |
| `zoneSet` | **Zone set** (id, map) · **Zones** (table: id, type, name, point count, parameters) |
| `responses` | **Responses** (table: request id, type, lease expiry, and the request it answers from the robot's last state) |

Every type starts with a **Header** section (version, header id, timestamp and its offset from the receive time,
manufacturer, serial number). Fields the reader doesn't know go into a final **Other fields** `RawSection`.

### 6.4 Chart values

`state`: state of charge, battery voltage, battery current (3.0), velocity (√(vx² + vy²)), x, y, θ, localization
score. `visualization`: velocity, x, y, θ. The other types have none.

### 6.5 Correlation

The context gives the interpreters the robot's last messages of other types, read only:

- state → last `order`: order progress and the node ids of action states.
- state → last `responses` (3.0): the answer to each zone and edge request.
- responses → last `state` (3.0): the request each response answers.
- visualization → the `state` with `referenceStateHeaderId` (3.0), when it is still the last one: shown as "based on
  state #{id}", or "based on an older state" otherwise.

Sequences, order updates and request pairing over time are the check's (§9.3).

### 6.6 Versions (V14, V15)

`vda5050_reader.dart` reads each message into version-neutral views (`VdaState`, `VdaOrder`, `VdaPosition`,
`VdaPowerSupply`, `VdaError`, …) named after the 3.0 terms. The 2.x reader maps the old names:

| Model (3.0 name) | 2.x name |
|---|---|
| `mobileRobotPosition` | `agvPosition` |
| `mobileRobotPosition.localized` | `agvPosition.positionInitialized` |
| `powerSupply.stateOfCharge` | `batteryState.batteryCharge` |
| `powerSupply.range` | `batteryState.reach` |
| `safetyState.activeEmergencyStop` | `safetyState.eStop` (`AUTOACK` shown as sent) |
| edge `maximumSpeed`, `maximumMobileRobotHeight`, `minimumLoadHandlingDeviceHeight` | `maxSpeed`, `maxHeight`, `minHeight` |
| edge `reachOrientationBeforeEntering` | `rotationAllowed`, inverted |
| `connectionState` `CONNECTION_BROKEN` | `CONNECTIONBROKEN` |
| `operatingMode` `TEACH_IN` | `TEACHIN` |
| factsheet `mobileRobotGeometry`, `mobileRobotConfiguration` | `agvGeometry`, `vehicleConfig` |
| instant actions `actions` | `instantActions` (1.1) |

The mapping table is verified against the 2.0, 2.1 and 3.0 JSON schemas when the reader is written; fields the
table misses fall into **Other fields** instead of being lost. The detail view shows the field names of the
message's version in the raw view and in tooltips, so a user comparing against the specification finds them.

Version-only data is optional in the model: 2.x messages have no paths, zones, requests, instant or zone action
states; 3.0 edges have no start and end node (the route table derives them from the sequence ids for both
versions). 2.1 additions (corridors on edges, maps in the state) are read by the 2.x reader when present.

## 7. Topic viewer integration

- **Sequential viewer:** the summary follows the chip in the row (`bodyLarge`, one line, ellipsis). A level other
  than `none` shows a 16 px `error`/`warning` icon before the summary.
- **Tree viewer:** a topic node shows the summary of its last message after the chip, before the statistics. The
  documented title stays the chip's tooltip.
- **Grouped viewer:** chips stay as they are, for density and speed. The chip's tooltip is the summary, and a chip
  whose message has a level gets a 3 px bottom border in the level's color, painted by `ChipPainter` (new optional
  `marker` color on `FastTopicChip`).
- **Detail view:** when the selected message is interpreted, the payload area shows the sections (`titleMedium`
  headers, collapsible; values `bodyLarge`; tables dense) instead of the JSON viewer, with the protocol version
  (`VDA 5050 3.0.0`) as a small `labelLarge` tag. A two-state `ToggleButtons` "VDA 5050 | Raw" sits next to the
  decoder dropdown; Raw shows today's viewer and switches the topic to raw (§5.2). Changes since the previous
  message and the compare dialog keep working on the raw JSON.
- **Chart:** when the message has `values`, a dropdown above the chart picks the series (remembered per message type
  for the session) and `getChartValues` reads that value from the topic's last 100 interpreted messages.
- **Filter:** no change; conditions work on the raw JSON, so they use the field names of the message's version. The
  help text of the Condition mode gets examples for both: `$.batteryState.batteryCharge < 20` (2.x),
  `$.powerSupply.stateOfCharge < 20` (3.0), `$.operatingMode != "AUTOMATIC"`,
  `$.connectionState ~ /BROKEN/` (both spellings).
- **Recorder:** the MESSAGES tab uses the same widgets through `MessageSource`, so it shows summaries and the
  interpreted detail view without extra work.

## 8. Fleet view (V7, V8)

A fourth button in the view-mode `ToggleButtons` (`Icons.precision_manufacturing`, tooltip "Fleet"), enabled while
the buffer holds a VDA 5050 `state`, `visualization` or `connection` message. The grouping-period dropdown and the
tree buttons are hidden in this mode as they are in Sequential mode.

```
┌──────────────────────────────────────────────────────────┬──────────────────────────────────────┐
│ Robot        Ver. Conn.        Mode        Drive Bat. Order│ Map [warehouse-1 ▾] [Zones ✓] [⤢]  │
│ KUKA 0001    2.1  ONLINE       AUTOMATIC   ▶    78 % 4711 │   ·  ·  ·  ·  ·  ·  ·  ·  ·  ·      │
│ KIT  0002    3.0  ONLINE       INTERVENED  ■ ⚠  41 % 4712 │  ░░░░    ▲0001 ━━●━━●╍╍●╍╍●         │
│ SEW  A17     3.0  HIBERNATING  —           —    —    —    │  ░░░░         ▼0002 ┄┄┄┄┄┄          │
│ SEW  A18     2.0  BROKEN       —           —    —    —    │   ·  ·  ·  ·  ·  ·  ·  ·  ·  ·      │
└──────────────────────────────────────────────────────────┴──────────────────────────────────────┘
```

- **Data:** `FleetState` folds VDA 5050 messages into one `VehicleState` per device key, from the version-neutral
  model: last connection, last state, last visualization, last order, the last zone set per map (3.0), a trail of
  the last 200 positions, and the time of the last state. It is updated incrementally from `messageReceivedEvent`,
  rebuilt from the buffer when the mode is opened or the buffer is cleared, and notifies at most 4 times per second.
  Robots of both versions appear in one fleet.
- **Robot table (left, 600 px):** manufacturer and serial number, protocol version, connection state, operating
  mode, driving or paused, state of charge, order and last node, error count with the highest level, open requests
  (3.0), and the age of the last state (grey after 35 s, like the stale rule). Columns sort. A click selects the
  robot and opens its last state in the detail view.
- **Canvas (right):** one map at a time (`mapId` dropdown when there are several). Grid in meters, pan and zoom
  (`InteractiveViewer`), "fit" to all positions, order nodes and zones. A robot is a triangle pointing along θ,
  colored by status (V11; driving `connectedColor`, idle and hibernating `watermark`), labeled with its serial
  number, with its trail as a thin line. The selected robot's last order is drawn: base edges solid, horizon edges
  dashed, nodes as dots, the last reached node filled. For 3.0 robots, the planned path is drawn dotted and the
  intermediate path as a thin solid line in the robot's status color, and zones of the shown map are drawn as
  translucent polygons (a "Zones" checkbox hides them; the zone's type is its tooltip). Painted with a
  `CustomPainter`.
- The detail view stays docked on the right of the body as in the other modes.

## 9. Documentation presets and check

### 9.1 Presets (V9, V10)

`Vda5050Preset.build(version, interfaceName)` (`lib/documentation/presets/`) builds the documentation at runtime from
the official JSON schemas of 2.1.0 and 3.0.0, bundled unchanged in `assets/vda5050/<version>/` with their MIT licence
(`assets/vda5050/LICENSE.txt`). `Vda5050Schemas.flatten` turns a schema into the documentation's subset: references
into `#/definitions` are inlined, the zone type parameters of the 3.0 `allOf`/`if`/`then` become optional properties
of the zone, the custom `unit` keyword becomes `x-unit`, and keywords outside the subset are left out. Each preset
holds:

- Namespace nodes for `{interfaceName}/{majorVersion}` and `…/{manufacturer}/{serialNumber}` with short descriptions
  written for MQTT Studio (not copied from the specification).
- Topic nodes for the topics of the version (v2: six, v3: eight with `zoneSet` and `responses`) with the schemas,
  QoS and retain of §3, producers and consumers ("Fleet control", "Mobile robot"), the parameters `manufacturer` and
  `serialNumber` with descriptions, and the intervals: `state` onChange with `staleAfterMs` 35,000; `visualization`
  periodic without a nominal interval; `order`, `instantActions`, `zoneSet` and `responses` event; `connection` event
  and last will.

The documentation tab's **IMPORT** button opens a menu: "AsyncAPI file" or "VDA 5050 documentation". The second
opens the import dialog with a version dropdown and the interface name (default `uagv` for 2.x, `vda5050` for 3.0,
switched with the version unless the user typed another name) instead of the file field; the plan, merge or replace
and the item list are the same as for a file. A plant that runs both versions adds both presets; their paths differ
in the version level.

### 9.2 Discovery

Discovery is unchanged. When the analyzed topics match the VDA 5050 profile, the review dialog shows a hint
"These topics look like VDA 5050 {version}. ADD PRESET" that opens the dialog of §9.1 with the preset, interface
name and version taken from the topics.

### 9.3 Protocol rules

`ConformanceChecker` runs the rules of the profile that matches a message, whether or not the documentation holds
a preset. Findings are aggregated like the others (per concrete topic and rule).

| Rule | Severity | Versions | When |
|---|---|---|---|
| Header differs from topic | error | all | `manufacturer` or `serialNumber` in the payload differ from the topic levels, or the major version of `version` differs from the version level |
| Header id out of order | warning | all | `headerId` is not greater than the previous one on the topic (a restart of the robot) |
| Header id gap | warning | all | `headerId` skips values (lost messages; normal at QoS 0 under load, so a warning). The finding counts the missing ids |
| Timestamp skew | warning | all | `timestamp` differs from the receive time by more than 5 s (setting) |
| Order structure | error | all | Sequence ids aren't continuous (even for nodes, odd for edges, N nodes and N − 1 edges), a released element follows an unreleased one, or (2.x) an edge's start or end node differs from its neighbours |
| Order update | error | all | Same `orderId` with a lower `orderUpdateId` than one seen before, or an update whose first node isn't the last base node of the previous update |
| Order update content | error | 3.0 | A new order whose first message has an `orderUpdateId` other than 0, a repeated `orderUpdateId` with different content, or an update of an order cancelled by `cancelOrder` |
| Duplicate action id | error | all | An `actionId` occurs twice in one order |
| Response without request | warning | 3.0 | A `responses` entry whose `requestId` was never in the robot's state during the check |
| Unanswered request | warning | 3.0 | A zone or edge request still without a response after 10 s (setting) |
| Visualization ahead of state | warning | 3.0 | `referenceStateHeaderId` is greater than the last state header id seen |
| Heartbeat missing | error | all | A robot whose last connection state is `ONLINE` (or that sent none) sends no `state` for more than 35 s. Reported once per silence; offline, broken or hibernating robots may be silent |

Schema, QoS, retain and stale findings come from the presets through the existing rules (V10). The rules' texts are
English like the other check details.

## 10. Simulated robots (V17–V21)

Without a VDA 5050 source nothing else in this design can be tried or tested, so the simulator gets a third kind of
device: **VDA 5050 robots** (simulator D26). A JSON template generator can't do it: the values of a state message
depend on each other and on the order, and the fleet view, order progress and protocol rules need robots that
behave consistently. The documentation's "Create simulation" on a preset still produces random values, which is
only useful for load tests.

### 10.1 Scope (V18)

In v1 the simulator plays **both sides**: a minimal fleet control that sends orders (and for 3.0 zone sets and
responses) and the robots that drive them. Every topic of §3 is published, so the whole feature can be tried with
nothing but a broker. Robots that obey orders from an outside fleet control or from the publish dialog need
subscriptions in the simulator and come later (§10.7).

### 10.2 Model (persisted, `json_serializable`)

```dart
enum DeviceKind { generated, recorded, vda5050 }        // simulator D26

class Vda5050Source {
  VdaVersion version = VdaVersion.v3;     // v2 (writes 2.1.0) | v3 (writes 3.0.0)
  String interfaceName = 'vda5050';       // 'uagv' is offered for v2
  String manufacturer = 'MQTTStudio';
  String serialNumber = 'SIM-{n}';        // {n} is the device instance (simulator §6.1)
  String mapId = 'sim-map';
  VdaLayout layout;                       // grid: columns 6, rows 4, spacing 5 m, charging nodes 1
  double speed = 1.0;                     // m/s
  double batteryPerHour = 20;             // % used per hour of driving; charging adds 60 %/h
  int stateHeartbeatSec = 30;             // 1–30, state is also sent on every event
  int visualizationMs = 500;              // 0 = no visualization topic
  bool factsheet = true;                  // published once at start
  VdaOrderSettings orders;                // nodes per order 4–10, horizon nodes 0–3, action probability 0.3,
                                          // action duration 2–8 s, idle time between orders 0–10 s
  bool zones = true;                      // 3.0: publish a zone set with a blocked, a speed limit and a
                                          // permission zone
  bool requests = true;                   // 3.0: robots request permission zones, the fleet answers
  VdaRandomFaults randomFaults;           // off by default: warnings and fatal errors per robot hour
  int? seed;                              // null = new random run each start; set for repeatable runs
}
```

`SimulatedDevice` gets `Vda5050Source? vda5050`, set when `kind == vda5050`; its `topics` stays empty like a
recorded device's. `instanceCount` is the number of robots. Validation (shared `SimulationRules`): manufacturer,
serial number and interface name without `/`, `+`, `#`; the serial number must contain `{n}` when there is more
than one robot; at most 200 robots (the layout must have at least as many nodes as robots plus charging nodes).

### 10.3 Behavior engine

`lib/simulator/vda5050/`, without Flutter, driven by the runner's clock so tests run in fake time:

- **`SimulatedFleet`** (one per running device) holds the layout graph (grid nodes `N{x}-{y}`, edges between
  neighbours, positions in meters on `mapId`), the robots and the fleet controller.
- **`FleetController`** (the simulator's fleet control role): gives each idle robot a route to a random target
  (shortest path), sends it as an `order` with the first nodes released (base) and the rest as horizon, and extends
  the base with **order updates** (`orderUpdateId` + 1, starting at the stitching node) as the robot advances. A
  node is reserved for one robot's base at a time; a robot whose next node is reserved waits (`driving` false), which
  gives realistic stops. Robots below 20 % get a route to a charging node with a `startCharging` action. For 3.0 it
  publishes the zone set at start and answers zone requests on `responses` after 0.5–2 s (`GRANTED`, sometimes
  `QUEUED` first).
- **`SimulatedRobot`**: a state machine. Start: `connection` `ONLINE` (retained), 3.0 `STARTUP` mode for 2 s, then
  `AUTOMATIC`; factsheet. Driving: the position moves along the edge at `speed` (scaled by elapsed time like
  simulator D17), θ follows the edge, battery drains. At a node: its actions run through `WAITING` → `INITIALIZING`
  → `RUNNING` → `FINISHED` with the configured duration; blocking `HARD` actions stop driving. Order done: idle.
  3.0: `plannedPath` (the remaining base edges) and `intermediatePath` (the next few meters), a zone request before
  entering a permission zone, waiting until it is granted, speed limited inside a speed limit zone.
- **Messages:** `state` on every event (order accepted, node reached, action status changed, error or mode changed)
  and at least every `stateHeartbeatSec`; `visualization` every `visualizationMs` (3.0 with
  `referenceStateHeaderId`). Header ids count per topic and robot. QoS and retain follow §3.
- **`Vda5050Writer`** writes the version-neutral model (V15) as 2.1.0 or 3.0.0 JSON, the counterpart of the reader
  (§6.6), so the engine has no version-specific code. The timestamps have hundredths of a second for 2.x and
  milliseconds for 3.0.
- **Stop:** each robot publishes `connection` `OFFLINE` (retained). The toolbar's **Clear retained** removes the
  connection messages like other retained simulated topics.

### 10.4 Fault injection (V19)

While a VDA 5050 device runs, each robot row has a **Faults** menu (`Icons.bolt`). Injected faults are runtime
state, not saved (simulator D5).

| Group | Faults |
|---|---|
| Robot | warning error, fatal error (the robot stops and keeps its order until cleared), 3.0 urgent and critical errors, emergency stop, field violation, pause and resume, low battery (5 %), clear errors |
| Connection | connection broken (§10.5), offline, hibernate (3.0), reconnect |
| Protocol | skip header ids, clock skew (+10 s), wrong serial number in the header, broken order (sequence gap), order update with a lower id, 3.0: response without request, unanswered request |

The robot faults show the interpreter and the fleet view at work; the protocol faults give each rule of §9.3 a
case to find. `randomFaults` injects robot faults on its own for long runs.

### 10.5 Connection broken (V20)

A last will belongs to an MQTT connection, and the simulator publishes over the main connection (simulator §7.3).
In v1 "connection broken" makes the simulator publish `CONNECTION_BROKEN` (`CONNECTIONBROKEN` for 2.x) retained with
QoS 1 for that robot, as the broker would, and the robot publishes nothing until **reconnect** (`ONLINE`). MQTT
Studio's viewers and the check can't tell the difference. A real connection per robot with a real last will is a
later option (§10.7).

### 10.6 UI

- **+ Device** offers "Generated device", "Recorded device" and "VDA 5050 robots".
- **Device header:** `precision_manufacturing` icon, `VDA 5050 3.0 · 5 robots · vda5050/v3/MQTTStudio/SIM-{n}`.
- **Rows:** one per robot instead of topics: serial number, a status line from the robot's last state (the summary of
  §6.2, so it uses the same code), messages sent, and the actions Faults (§10.4) and 👁. 👁 on the header subscribes
  `{interfaceName}/{version}/{manufacturer}/+/#` in the topic viewer; when the fleet view exists it also switches the
  topic viewer to Fleet mode.
- **Device dialog** (own viewmodel, reactive form), centered, with two tabs of the same height so it neither scrolls
  nor changes size: **ROBOTS** (name, robot count, first instance; version, interface name, manufacturer, serial
  number; layout: columns, rows, spacing, charging stations, map id) and **SIMULATION** (orders; speed, battery,
  charging, random faults; heartbeat, visualization, seed, factsheet; the 3.0 zones and requests, visible but
  disabled for v2, like `Mqtt5Section`). Below the tabs a line shows the resolved topics, e.g.
  `vda5050/v3/MQTTStudio/SIM-1/state … SIM-5/state`, and the rate. SAVE with an error opens the tab that has it.
- **Faults menu** (`widgets/robot_fault_menu.dart`): two columns, robot faults on the left, connection and protocol
  faults on the right; toggled faults show a check mark in a fixed leading column.
- **Rate estimate** (simulator §7.2): per robot `1000 / visualizationMs` plus 2 msg/s for state and order traffic,
  so the D11 warning and limit apply.

### 10.7 Later

- **External orders:** robots subscribe to their `order`, `instantActions`, `zoneSet` and `responses` topics and
  follow a real fleet control or the publish dialog, while the simulator's own fleet controller is off. Needs a
  subscribe path for the simulator (`SimulatorPublisher` only publishes today).
- **Real last will:** an own connection per robot (`SideConnection`), up to about 20 robots.
- **Fault injection from the CLI.** `mqttstudio simulate` already runs VDA 5050 devices through the runner.

## 11. CLI

- `doc check` runs the protocol rules automatically (§9.3); no new options.
- `doc import --preset vda5050-v2|vda5050-v3 [--interface <name>] --out <file>` writes a preset as an MQTT Studio
  AsyncAPI file, like `doc import --out`. Update `cli-manual.md`.
- No command prints interpretations in v1.

## 12. Commercial scope

Everything is free (V13). No feature is gated, and the app needs no licence check for it.

## 13. UI

- Localization keys are prefixed `protocol.` (generic: `protocol.view.interpreted`, `protocol.view.raw`,
  `protocol.chart.series`), `vda5050.` (section and field labels, the 3.0 terms for both versions) and
  `fleetview.`. Plural texts are flat keys (`vda5050.summary.errors.one`, `.other`).
- Every icon-only control has a localized tooltip; the fleet mode button is disabled, not hidden (V7).
- No new color tokens (V11). The design system artifact gets the interpreted detail view, the summary row and the
  fleet view as components when they are built.

## 14. Files

```
lib/protocol/
  protocol_profile.dart          ProtocolProfile, ProtocolTopic, Interpretation, sections, InterpretationContext
  protocol_registry.dart         ProtocolRegistry (GetIt), topic match cache
  protocol_rule.dart             ProtocolRule interface for the check
  vda5050/
    vda5050_profile.dart         detection, summaries, sections, values (§6)
    vda5050_model.dart           version-neutral read-only views (VdaState, VdaOrder, VdaZoneSet, …)
    vda5050_reader.dart          2.x and 3.0 readers, the name mapping of §6.6
    vda5050_writer.dart          writes the model as 2.1.0 or 3.0.0 JSON (§10.3)
    vda5050_rules.dart           protocol rules (§9.3)
    fleet_state.dart             FleetState, VehicleState (§8)
  widgets/
    interpreted_payload_view.dart  renders sections in the detail view
    fleet_viewer.dart            table and canvas
    fleet_canvas.dart            CustomPainter for the map
lib/simulator/model/
  vda5050_source.dart            Vda5050Source and its settings (persisted, §10.2)
lib/simulator/vda5050/
  fleet_layout.dart              FleetLayout: the grid, charging stations, zone set, routes
  simulated_fleet.dart           SimulatedFleet: timer, publishing, faults
  fleet_controller.dart          orders, order updates, node reservations, zone sets, responses
  simulated_robot.dart           robot state machine
  robot_fault.dart               RobotFault (§10.4)
lib/simulator/
  vda5050_device_dialog.dart, vda5050_device_viewmodel.dart
  widgets/simulation_list.dart   robot rows with the Faults menu (_RobotRow)
lib/protocol/vda5050/
  vda5050_schemas.dart           loads, corrects and flattens the official schemas
lib/documentation/presets/
  vda5050_preset.dart            Vda5050Preset (§9.1); import_dialog.dart and import_viewmodel.dart have a preset mode
assets/vda5050/
  2.1.0/*.schema, 3.0.0/*.schema, LICENSE.txt
```

Changed for the simulator: `simulation.dart` (`DeviceKind.vda5050`, `vda5050`), `simulator_runner.dart` (runs a
`SimulatedFleet` per device), `simulation_rules.dart` (§10.2 validation and rate), `simulator_page.dart` and its
viewmodel (+ Device menu, header, robot rows).

Changed for the viewers: `message_viewer_viewmodel.dart` (`interpret`, raw toggle, chart series, `TopicViewMode.Fleet`),
`message_detail_view.dart`, `sequential_messages_viewer.dart`, `tree_messages_viewer.dart`,
`grouped_messages_viewer.dart`, `fast_topic_chip.dart` (marker), `topics_viewer_command_bar.dart`,
`conformance_checker.dart` (profile rules), `review_dialog.dart` (hint), `doc_command.dart` (`--preset`),
`main.dart` (registry), `pubspec.yaml` (assets), `en.json`.

## 15. Testing

- `test/protocol/vda5050_reader_test.dart`: the same robot situation as a 2.0, 2.1 and 3.0 message gives equal
  models; every row of the mapping table; unknown fields go to Other fields; 1.1 instant actions.
- `test/protocol/vda5050_profile_test.dart`: detection (topic shapes, prefixes, wrong last level, missing header,
  version from header vs topic), summaries and levels per type and version, sections, chart values, tolerant
  reading of broken payloads and unknown enum values. Sample messages are written for the tests and validated
  against the official schemas of their version, not copied from vendor traces.
- `test/protocol/vda5050_rules_test.dart`: every rule with a passing and a failing case per version, order updates
  across several messages, header id restart vs gap, request/response pairing.
- `test/protocol/fleet_state_test.dart`: folding a mixed 2.x/3.0 fleet, trails, zones per map, rebuild from a
  buffer, throttled notifications.
- `test/documentation/`: both presets import without warnings, their schemas validate the sample messages, the
  path rewrite.
- Viewmodel tests: the raw toggle, the interpretation cache, chart series.
- `test/simulator/vda5050/`: with a fake publisher, fake time and a fixed seed: every published message validates
  against the schema of its version; a robot needs the expected time for a route; order updates are stitched and
  ids increase; reserved nodes make robots wait; the heartbeat comes at the latest after `stateHeartbeatSec`;
  charging; 3.0 zone requests are answered; stop publishes `OFFLINE`; each fault changes the expected fields. The
  writer → reader round trip gives the same model.
- **End to end:** a simulated fleet runs through `ConformanceChecker` with the presets: no findings without faults,
  and each protocol fault produces exactly its rule's finding.

## 16. Implementation phases

0. **Simulated robots (V17):** the version-neutral model with reader and writer, `SimulatedFleet`, the device kind,
   dialog and rows, fault injection. Done when a 3.0 and a 2.x fleet run side by side and their messages validate
   against the official schemas.
1. **Presets:** bundled official schemas, preset builder, VDA 5050 entry in the IMPORT menu, CLI `--preset`. Gives
   schema, QoS, retain and heartbeat checks for both versions with almost no new engine code.
2. **Profile engine and rules:** `lib/protocol/`, the VDA 5050 profile without widgets, protocol rules in the check
   and the CLI, discovery hint. Done when a clean simulation gives no findings and each protocol fault exactly its
   finding.
3. **Topic viewer:** summaries, markers, interpreted detail view, raw toggle, chart series.
4. **Fleet view**, including 3.0 paths and zones.
5. **Later:** external orders and real last will for simulated robots (§10.7), a time slider for the fleet view of
   recordings, LIF layouts, a Sparkplug B profile.

## 16.1 Implementation notes (2026-10-25)

**Phase 0 (simulated robots)** is implemented as designed in §10, with these differences:

- **Field names** were checked against the official 2.1.0 and 3.0.0 JSON schemas; §3 and the mapping in §6.6 are
  corrected where the change log was wrong or incomplete (`grantType`, `actionResult`, `…Descriptor`,
  `maxRotationSpeed`, factsheet names). `Vda5050Reader` accepts both spellings and 1.1's `instantActions`;
  `Vda5050Writer` writes 3.0 values that 2.x lacks as their closest 2.x value (`URGENT` → `WARNING`, `CRITICAL` →
  `FATAL`, `RETRIABLE` → `FAILED`, `PAUSED` → `RUNNING`, `SINGLE` → `SOFT`, `STARTUP` → `AUTOMATIC`, `INTERVENED` →
  `MANUAL`, `HIBERNATING` → `OFFLINE`) and puts 2.x instant action states into `actionStates`.
- **The official schemas are not bundled yet.** `test/protocol/vda5050_shapes.dart` encodes their required fields and
  enums by hand; every simulated message of both versions passes it. Validating against the schema files themselves
  needs them as test fixtures (Q2).
- **Settings:** `Vda5050Source` lives in `lib/simulator/model/` next to `Simulation`. It adds `chargePerHour` (default
  120 %/h), so a demo charge doesn't take hours. The dialog shows the action probability as a percentage.
- **Robots freeze while not `ONLINE`** (broken, offline, hibernating): they neither move nor publish until reconnect.
- **Faults:** "cancel order" was added to the robot faults; the fleet control sends `cancelOrder`, and a robot on an
  edge stops at the next node. Toggles (emergency stop, field violation, pause, clock skew, wrong serial number) are
  check items in the menu. Random faults are `randomFaultsPerHour` per robot: 70 % warnings, 30 % fatal errors,
  cleared after 20 to 60 s.
- **Order updates** release two nodes at a time once the robot is one node before the end of its base. A robot that
  waits 10 s for a node another robot holds gets a new route from the stitching node; that route may turn back
  through a node it passed.
- **Zones** need at least 4 × 3 nodes; the blocked zone removes the node in the middle of the grid, the release zone
  covers the node at the right of row 1, the speed limit zone the last row at half speed.
- **CLI:** `simulate` runs VDA 5050 devices and `--clear-retained` removes their `connection` messages; faults are app
  only. `cli-manual.md` is updated.
- **Not verified against a broker in the app** during implementation: the dialog, device rows and validation were
  checked in the web build; the fleet itself is tested in fake time through the real `SimulatorRunner`.

**Phase 1 (presets)** is implemented as designed in §9.1, with these differences:

- **No AsyncAPI asset and no build script:** the preset is built at runtime from the official schema files, which
  are bundled unchanged. That keeps one source of truth and lets the tests validate simulated messages against the
  real schemas (`test/documentation/vda5050_preset_test.dart`: every message of both versions passes).
- **The 3.0.0 schemas have mistakes**, corrected in `Vda5050Schemas.correct` while the files stay as published:
  `factsheet` requires `mobileRobotKinematic` although the property is `mobileRobotKinematics`, and types
  `pauseAllowed` and `cancelAllowed` as strings although they are true or false. `factsheet`, `order` and
  `visualization` have trailing commas, so all schemas are read with the YAML parser.
- **No ⋮ menu:** "Add preset" is the second entry of the IMPORT menu; a separate button didn't fit the command bar at
  1500 px.
- **2.1.0 schemas have no units**, so only 3.0 fields carry `x-unit`.
- **CLI:** `doc import --preset vda5050-v2|vda5050-v3 [--interface <name>]` instead of a file; `run_cli` already
  initializes the binding the asset bundle needs.

**Phase 2 (profile engine and rules)** is implemented as designed in §5, §6, §9.2 and §9.3, with these differences:

- **Engine:** `lib/protocol/protocol_profile.dart` (profile, topic, interpretation with sections and values,
  `ProtocolChecker`), `protocol_registry.dart` (`ProtocolRegistry.standard()` with the VDA 5050 profile, topic cache;
  not a GetIt service yet, the topic viewer phase can register it), `vda5050/vda5050_profile.dart` and
  `vda5050_rules.dart` (`Vda5050Checker`).
- **Texts:** summaries, section titles and labels are English strings made by the engine, so it stays free of Flutter
  and the CLI could print them; the app is English only. Localizing them would mean keys in the engine.
- **Order progress:** the state summary says how many nodes are still to go (`order o7#2 at N3, 4 nodes to go`)
  instead of `done/total`, which would need every update of the order.
- **No receive-time offset** in the Header section yet: the interpreter doesn't get the receive time; the detail view
  can add it in phase 3.
- **New rule `heartbeatMissing`** (§9.3): the documentation's stale rule works per template, so one silent robot among
  others that keep sending wasn't found. The rule checks every robot.
- **Findings:** protocol rules are `FindingRule.protocol` with the profile's rule id (`vda5050.headerIdGap`) and
  severity; the findings panel, CSV and the CLI show the id. The check runs the rules on every message it receives,
  documented or not.
- **A check that starts after the robots:** retained messages the broker sends on subscribing (`snapshot`) are not
  checked for timestamp skew, they are as old as they are. "A new order starts with update id 0" is only reported
  when the robot's last state showed another order, since the first update a check sees may belong to an order that
  began before it. Header id gaps stay warnings: QoS 0 messages do get lost, e.g. on a busy public broker.
- **Check filters:** a check listened only to the last discovery's filters once a discovery was applied, so the
  topics of an imported preset outside them were never checked. `ConformanceChecker.filtersOf` now listens to the
  documented topics and the discovery's filters (documentation-design §7).
- **Discovery hint:** the review dialog shows the hint when a new topic is a VDA 5050 topic. Its button closes the
  review without applying and opens the preset dialog with the version and interface name of the topics; after the
  import, the user discovers again for the other topics, so the discovered VDA 5050 topics don't compete with the
  preset's templates.
- **Tests:** `test/protocol/vda5050_profile_test.dart` (detection, interpretation, every rule failing and passing) and
  `test/documentation/vda5050_check_test.dart`: a simulated fleet of both versions through the real
  `ConformanceChecker` with the preset gives no findings, each protocol fault exactly its rule, and robot and
  connection faults none.

**Phase 3 (topic viewer)** is implemented as designed in §7, with these differences:

- **No GetIt service:** `MessageViewerViewmodel` holds its own `ProtocolRegistry.standard()`. It caches the
  interpretation per message in an `Expando` (dropped when the topic's decoder changes, so a gzip-compressed state is
  interpreted after choosing the decoder) and gives the interpreter the buffer's last message of the device's other
  topics for correlation (§6.5). The recorder's MESSAGES tab gets the same through `MessageSource`.
- **Detail view header:** the 500 px panel has no room for a version tag, the toggle and the decoder. The toggle's
  first button carries the version (`VDA 5050 3.0.0 | Raw`) and replaces the kind chip, and the decoder dropdown is
  shown only in Raw. Changes since the previous message (the diff button) show the raw JSON diff, also for an
  interpreted topic.
- **Sections** fold by their key for the session, so a folded "Paths" stays folded while new states arrive.
- **Chart:** the series dropdown sits above the chart; the first value of the message type (state of charge for a
  state) is charted until another is chosen.
- **Filter help:** the Condition tooltip is already long, so the VDA 5050 examples of §7 are not added to it.
- **Tests:** `test/message_viewer/vda5050_viewer_test.dart` (summaries in the sequential and tree viewers, marker and
  tooltip of grouped chips, sections, folding, raw toggle, chart series).

**Phase 4 (fleet view)** is implemented as designed in §8, with these differences:

- **Data:** `FleetState` and `VehicleState` (`lib/protocol/vda5050/fleet_state.dart`) are plain Dart and generic over
  the message type, so the view can select a robot's last state. `MessageViewerViewmodel` builds the fleet from the
  buffer only while the Fleet mode is shown and adds each new message to it; leaving the mode drops it. Updates follow
  the viewmodel's 500 ms refresh, twice a second instead of four times. An `order` alone doesn't add a robot (it may be
  addressed to one that never answers), zone sets are kept per map and zone set id.
- **Fleet button:** `ToggleButtons` can't disable a single button, so the Fleet button is greyed out with its own
  tooltip and ignores clicks until a robot sent its connection, state or visualization.
- **Table:** robot, connection (a dot in the connection's color; the state as sent only when it isn't `ONLINE`), mode,
  drive (driving, paused or standing icon), battery (with a charging icon), errors (count and highest level), the
  state's age, order and update id with the last node, open requests and version. The table takes the width of its
  columns, at most 55 % of the view, instead of a fixed 600 px; what tells whether a robot is fine comes first, as the
  last columns need the horizontal scrollbar while the detail view is open. Robots of a single manufacturer show only
  their serial number, with the full name as tooltip. Clicking a header sorts, clicking a row selects the robot's last state (else its
  last visualization or connection). Selecting any message of a robot in another mode selects the robot too.
- **Canvas:** its own pan (drag) and zoom (mouse wheel, around the pointer) instead of an `InteractiveViewer`, so robots
  and labels keep their size. It fits all robots, order nodes and zones until the user moves it; the Fit button fits
  again. A grid label in the corner gives the grid step; there are no axis lines. Lines are drawn **only for the
  selected robot**, as trails of every robot made the map unreadable: its trail (thin grey), its order (dark grey,
  released edges solid, horizon dashed, reached nodes filled) and for 3.0 its planned path (dotted) and intermediate
  path in the accent color. Robots keep their status color; idle robots are drawn grey with an outline, as the watermark
  color disappears on white, and robots that are offline or lost the connection are only a red outline, so they don't
  look like robots that report an error. Zones carry their id and type as a label instead of a tooltip.
- **Legend:** a legend in the canvas's lower right corner explains the robot colors and the lines; the map bar's legend
  button hides it. A map at least three legend widths wide fits the robots left of it.
- **Disabled controls say why:** the map dropdown is disabled while the robots report a single map, the Zones checkbox
  (then unchecked) while no zone set of the map was received. Zone sets aren't retained, so a topic viewer that
  subscribes after the robots started never sees them; the checkbox's tooltip says so.
- **Recordings:** the recorder's MESSAGES tab offers the Fleet mode too: the robots as they were at the end of the
  recording, without a time slider.
- **Filter:** the command bar's filter doesn't apply to the fleet view.
- **Tests:** `test/protocol/fleet_state_test.dart` (folding both versions, status, trail, zones and maps, a simulated
  fleet of both versions) and `test/message_viewer/fleet_viewer_test.dart` (the Fleet button, table, sorting,
  selection, map choice and selecting by a click on the map, clearing).

## 17. Known limitations

- Positions are local coordinates without a layout, so the canvas shows only robots, trails, order nodes, paths and
  zones.
- Topic colors belong to subscriptions; one wildcard subscription colors all robots alike, so the fleet view colors
  by status instead.
- JSON paths have no wildcards, so the filter can't express "any error is FATAL"; `$.errors[0].errorLevel` checks
  only the first. Conditions use the raw field names, which differ between 2.x and 3.0.
- Only JSON payloads are interpreted. A robot that sends VDA 5050 compressed or binary is shown raw unless the
  topic's decoder turns it into JSON first (gzip, Base64 work).
- Extensible 3.0 enums: a value the app doesn't know is shown as sent, with the neutral status color.
- The tool sees messages, not behavior: it can't tell whether a robot really drove the route it reports.
- Header id and timestamp rules can't tell a robot's clock or counter problem from a broker problem.
- Zones come from the `zoneSet` topic and the state's `zoneSets`; a zone set sent before MQTT Studio subscribed is
  missing until it is sent again (it isn't retained).

## 18. Open questions

| # | Question | Proposal |
|---|---|---|
| Q1 | Free, or a commercial add-on? | Decided: all free (V13) |
| Q2 | May the official JSON schemas be bundled? | Decided: yes, bundled with the MIT licence in `assets/vda5050/` and used as test fixtures. Recheck when 3.0.1 or later changes the licence |
| Q3 | Which versions? | Decided: 2.0, 2.1 and 3.0 (V14); 1.1 read on a best-effort basis, no 1.1 preset |
| Q4 | Should the topic viewer mark protocol problems live (header id gaps, missing heartbeat), as an exception to T19? | Decided: no (V5) |
| Q5 | Fleet view as a view mode, or as a tab of its own? | Decided: a view mode (V7) |
| Q6 | Which 3.x minor versions? | Decided: handled in the 3.0 reader (V16) |
| Q7 | Default robot count, layout size and speed of a new VDA 5050 device? | 5 robots on a 6 × 4 grid with 5 m spacing at 1 m/s: busy enough to see waiting and order updates, slow enough to follow |
