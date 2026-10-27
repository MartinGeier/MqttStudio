# Sparkplug B Support – Design

Status: **Phase 1 implemented** (profile, topic viewer, protocol rules). Later phases are proposals, see §8; the
simulated edge nodes (phase 2, §10) are implemented, see §10.10 and §10.11 ·
Branch: `mqtt5` · Last updated: 2026-10-27

Related: `vda5050-design.md` (the protocol profile layer this builds on, §5), `documentation-design.md` (T18: discovery
documents `spBv1.0/…` topics as `binary`), `recorder-design.md`, `simulator-design.md`.

## 1. Purpose

Sparkplug B (Eclipse Foundation, specification 3.0, also ISO/IEC 20237) is the most used MQTT convention in
industrial IoT: edge nodes and their devices announce their metrics in a *birth* message, then send only changed
values, by alias, in Protobuf. Without decoding, MQTT Studio shows Sparkplug traffic as hex, and even decoded data
messages are numbers without names, because the names are only in the birth.

Phase 1 makes the topic viewer and the documentation check understand Sparkplug B, on the protocol profile layer
built for VDA 5050, so the viewers needed no changes of their own.

## 2. Sparkplug B in short (for reference)

- Topics: `spBv1.0/{group_id}/{message_type}/{edge_node_id}[/{device_id}]`; host applications publish
  `spBv1.0/STATE/{host_id}` (3.0, JSON `{"online": true, "timestamp": …}`, retained) or `STATE/{host_id}` (2.2, the
  text `ONLINE`/`OFFLINE`).
- Message types: `NBIRTH`, `NDEATH`, `NDATA`, `NCMD` for edge nodes, `DBIRTH`, `DDEATH`, `DDATA`, `DCMD` for devices.
- Payload: Protobuf (`sparkplug_b.proto`): timestamp, metrics, `seq` (0–255, one counter per edge node over NBIRTH,
  NDATA, DBIRTH, DDATA and DDEATH), uuid, body. A metric has name and/or alias, timestamp, data type, flags
  (historical, transient, null), metadata, properties (e.g. `engUnit`) and a value of one of 34 data types, including
  arrays (3.0, little-endian bytes), DataSets and Templates.
- Session: NBIRTH carries `bdSeq`; the NDEATH (the edge node's MQTT last will) carries the same `bdSeq`. Births are
  not retained, so a client that subscribes later doesn't know the names of aliases until the edge node is asked to
  rebirth (`NCMD` with `Node Control/Rebirth = true`).
- Compression: `uuid = SPBV1.0_COMPRESSED`, the real payload compressed in `body`, the `algorithm` metric `GZIP` or
  `DEFLATE`.

## 3. Decisions

| # | Decision | Source |
|---|---|---|
| S1 | Sparkplug B is a **second protocol profile** (`SparkplugProfile`) next to VDA 5050, registered in `ProtocolRegistry.standard()`. The viewers, the detail view, charts and the check work through the profile layer unchanged | User |
| S2 | The Protobuf wire format is read and written by a **hand-written codec** (`sparkplug_payload.dart`), no generated code and no new dependency. 64-bit values are read without bit shifts, so the web build gets them right up to 2^53 | Design |
| S3 | Profiles get the **raw bytes** when a payload isn't JSON (or MessagePack, CBOR through the topic's decoder). `InterpretationContext.lastData` takes a **topic** instead of device key and message type, as Sparkplug puts the message type in the middle of the topic | Design |
| S4 | Data and commands are shown with **names, data types and units from the last birth** in the buffer. Without a birth, metrics are shown by alias with a warning in the header. Read births are cached per payload | Design |
| S5 | Like VDA 5050 (V4, V5), interpreting **only reads**: no rebirth requests, no commands. Protocol violations are the check's | Design |
| S6 | Texts are English strings of the engine, like VDA 5050; protocol terms (`NBIRTH`, data type names) as in the specification | Design |
| S7 | **Levels:** deaths and an offline host are warnings, a payload that isn't Sparkplug B is an error. Sparkplug has no error concept of its own; metric quality properties are shown, not judged | Design |
| S8 | **Chart values** are the numeric and boolean (0/1) metrics by name. As data messages report by exception, a series takes only the messages that contain its metric | Design |

## 4. Payload codec (`lib/protocol/sparkplug/sparkplug_payload.dart`)

`SparkplugReader.read(bytes)` returns an `SpbPayload` with `SpbMetric`s and throws a `FormatException` for anything
that isn't valid Protobuf. Values are converted by data type: Int8/16/32 from the two's complement in `int_value`,
Int64 from `long_value`, UInt64 above the int range as `BigInt`, DateTime as `DateTime` (UTC), the 3.0 arrays from
their little-endian bytes (BooleanArray with its count prefix, StringArray null-terminated), DataSets with typed rows,
Templates with members and parameters, PropertySets (nested too) and MetaData. Unknown fields are skipped; packed and
unpacked DataSet types are both read. `SparkplugWriter.write` writes the same model; the tests and a later simulator
use it.

## 5. Profile (`sparkplug_profile.dart`)

- **Detection:** the topic shapes of §2; node types need 4 levels, device types 5. `deviceKey` is
  `{group}/{edge node}[/{device}]`.
- **Summaries:** `BIRTH | edge node E1 | 42 metrics | bdSeq 3 | seq 0`, `E1 | Temperature = 21.5 °C, Running = true,
  … (+5) | seq 17`, `DEATH | device Pump on E1`, `COMMAND to E1 | Node Control/Rebirth = true`, `Host scada | ONLINE`.
- **Sections:** Header (message type and its meaning, group, edge node, device, timestamp, seq, bdSeq, uuid,
  compression, body size, the missing-birth warning) and a Metrics table (name, alias, type, value with unit,
  details: own timestamp, historical, transient, properties, file metadata). Historical metrics are muted. DataSets and
  Templates get a table each. At most 500 rows per table.
- **Compressed payloads** are unpacked (GZIP, and DEFLATE in the zlib format as Eclipse Tahu writes it); the header
  says so.

## 6. Protocol rules (`sparkplug_rules.dart`)

Run by the documentation check and the CLI's `doc check` for every Sparkplug topic, documented or not.

| Rule | Severity | When |
|---|---|---|
| `sparkplug.payload` | error | an edge node or device message that isn't a Sparkplug B Protobuf payload |
| `sparkplug.seqMissing` | error | NBIRTH, NDATA, DBIRTH, DDATA or DDEATH without `seq` |
| `sparkplug.seqGap` | warning | `seq` isn't the previous one + 1 (mod 256); lost or reordered messages |
| `sparkplug.timestampMissing` | warning | a birth, data or device death without payload timestamp |
| `sparkplug.bdSeqMissing` | error | NBIRTH or NDEATH without the `bdSeq` metric |
| `sparkplug.bdSeqMismatch` | warning | the NDEATH's `bdSeq` differs from the NBIRTH's |
| `sparkplug.afterDeath` | error | data, device birth or death of an edge node after its NDEATH and before its next NBIRTH |
| `sparkplug.deviceNotBorn` | error | DDATA of a device without DBIRTH since the NBIRTH, or after its DDEATH |
| `sparkplug.datatypeMissing` | error | a birth metric without data type |
| `sparkplug.duplicateAlias` | error | two metrics of a birth with the same alias |
| `sparkplug.unknownMetric` | error | data with a metric (name or alias) the birth doesn't define |
| `sparkplug.datatypeMismatch` | error | data with a data type that differs from the birth |

A check that starts while edge nodes are online has missed their births: the session rules (`afterDeath`,
`deviceNotBorn`, `unknownMetric`, `datatypeMismatch`, `bdSeqMismatch`) wait for the next NBIRTH, and the sequence is
followed from the first message seen. QoS and retain (NDEATH QoS 1 as last will, STATE retained) aren't checked: the
rules get the payload, not the delivery.

## 7. Phase 1 implementation notes (2026-10-27)

- Files: `lib/protocol/sparkplug/sparkplug_payload.dart`, `sparkplug_profile.dart`, `sparkplug_rules.dart`; changed
  `protocol_profile.dart` (context by topic, data comment), `protocol_registry.dart`, `vda5050_profile.dart` (context
  calls), `message_viewer_viewmodel.dart` (`protocolData`: decoded data, else bytes) and `conformance_checker.dart`
  (JSON, else bytes).
- The detail view's toggle reads "Sparkplug B | Raw"; Raw shows the hex viewer as before. The decoder dropdown shows
  only in Raw (vda5050-design §16.1, phase 3).
- No new UI texts in `en.json`: everything Sparkplug-specific comes from the engine (S6).
- Discovery still documents `spBv1.0/…` topics as `binary` (documentation-design T18); see §8.4.
- Tests: `test/protocol/sparkplug_payload_test.dart` (wire format, every scalar type, BigInt, arrays, properties,
  DataSets, Templates, unknown fields, broken payloads), `sparkplug_profile_test.dart` (detection, summaries,
  aliases from the birth, missing birth, devices, deaths, commands, DataSets, STATE 2.2 and 3.0, compression, every
  rule failing and passing, a check that starts late) and `test/message_viewer/sparkplug_viewer_test.dart` (the
  sequential viewer, detail view and chart with binary payloads; the documentation check with binary payloads).

## 8. Later phases (proposals)

Ordered by value for the effort:

1. **Rebirth request.** A "Request rebirth" action in the detail view and the tree's context menu of an edge node:
   publishes `NCMD` with `Node Control/Rebirth = true`. Solves the most common problem, metrics shown by alias after
   subscribing late. Needs the writer (exists) and a confirmation, as it acts on a real system.
2. **Sparkplug view mode** (like the VDA 5050 fleet view): groups, edge nodes and devices in a tree with online
   state from births and deaths, bdSeq, seq health, last message, and a live metric table per node or device that
   merges the birth with all data since (current value, unit, timestamp, quality). The most useful view for
   commissioning; a host application in miniature.
3. **Write metrics.** A command editor that lists the metrics of the birth with their data types and sends `NCMD` or
   `DCMD` with a typed value, instead of composing Protobuf by hand.
4. **Documentation from births.** Discovery documents each Sparkplug topic template with the metric names, data types
   and units of its births (T18), and the check compares data with the documentation as well as with the birth.
5. **Simulated edge nodes.** A simulator device kind that publishes NBIRTH/DBIRTH, data by exception from the
   existing generators, NDEATH as real last will (own connection per node), answers rebirth requests and runs a
   primary host's STATE. Lets users try 1 to 4 without a PLC. Designed in §10 (phase 2).
6. **Conditions and filters on metrics.** Map Sparkplug payloads to JSON (`{"Temperature": 21.5, …}` with names from
   the birth) for the filter's Condition mode, recorder triggers and the recorder's CHARTS tab, so
   `spBv1.0/+/NDATA/+ $.Temperature > 80` works.
7. **Primary host application checks.** STATE handling of 3.0 (retained, timestamps), and that edge nodes publish
   NBIRTH again after their primary host comes back online.
8. **Export decoded.** The recorder's export and the CLI write Sparkplug messages as JSON.

## 9. Known limitations

- Births are not retained: until the next birth, data is shown by alias and the session rules can't run.
- Only the zlib form of DEFLATE is unpacked; raw DEFLATE streams are shown as the outer payload.
- Template instances are shown with the members they send; definitions aren't merged into instances.
- Multi-part file metrics (MetaData `is_multi_part`) are shown part by part, not assembled.
- On the web, 64-bit integers above 2^53 lose precision.
- Units come from the usual property names (`engUnit`, `unit`, `engineeringUnits`); other conventions show as
  properties.

## 10. Simulated edge nodes (phase 2)

A simulator device kind that behaves like a real Sparkplug B 3.0 edge node with devices, close enough to the
specification to serve as a reference. Users can try the Sparkplug features without a PLC, and test a host
application (SCADA, MES, historian) or MQTT Studio's own rules against something that does it right, and, with
faults, against something that does it wrong in a known way.

### 10.1 Decisions

| # | Decision | Status |
|---|---|---|
| S9 | A fourth **device kind** `sparkplug` next to generated, recorded and VDA 5050 (simulator D26). A device's instances are **edge nodes**; each edge node has the same devices and metrics | Decided |
| S10 | **One MQTT connection per edge node** with the NDEATH as its real **last will**, so the broker reports a dropped node, as the specification requires. Not the main connection | Decided (Q1) |
| S11 | Edge nodes **subscribe** to their `NCMD`, `DCMD` and the primary host's `STATE`, and answer rebirth requests and writes from MQTT Studio's publish dialog or a real host application | Decided |
| S12 | **Metrics come from the simulator's generators** (wave, random walk, counter, boolean, value list, …) with a Sparkplug data type, unit and deadband each, and are published **by exception** | Decided (Q3) |
| S13 | **Sparkplug 3.0 only**: STATE as JSON under `spBv1.0/STATE/{host}`. The reader still understands 2.2 | Decided (Q5) |
| S14 | The simulator **can play the primary host** (publish its STATE), so a full system runs with nothing but a broker, like the VDA 5050 simulation plays the fleet control | Decided (Q2) |
| S15 | **Fault injection** per edge node while running; every protocol fault produces exactly one rule of §6, checked by an end-to-end test like `vda5050_check_test` | Decided |

### 10.2 What "follows the specification" means here

The behavior the edge node must get right, as a checklist for the implementation and its tests. Each point is
checked against the text of the Sparkplug 3.0 specification and the Eclipse Sparkplug TCK when it is implemented;
the TCK's edge node tests are the yardstick.

- **Connect:** clean session (3.1.1) or clean start with session expiry 0 (MQTT 5); a client id of its own per edge
  node; the will on `spBv1.0/{group}/NDEATH/{node}` with QoS 1, not retained, its payload holding the `bdSeq` metric
  (Int64) of this connection.
- **bdSeq:** 0 on the first connect, + 1 on every new connection (255 → 0); the NBIRTH carries the same value as the
  will of the connection it is sent on. A rebirth on the same connection keeps it.
- **Primary host:** with a primary host configured, the edge node subscribes to `spBv1.0/STATE/{host}` first and
  sends NBIRTH only after `online: true`. When the host goes offline, the edge node disconnects (with its NDEATH)
  and connects again once the host is back.
- **Subscriptions:** `spBv1.0/{group}/NCMD/{node}` and `spBv1.0/{group}/DCMD/{node}/+`, QoS 1, before the NBIRTH.
- **NBIRTH:** QoS 0, not retained; `seq` 0; payload timestamp; every node metric with name, alias (when aliases are
  on), data type and current value; `bdSeq`; `Node Control/Rebirth` (Boolean, false); units as `engUnit` properties.
- **DBIRTH** for every online device after the NBIRTH and before its first DDATA, with all device metrics.
- **NDATA/DDATA:** only changed metrics (report by exception), by alias when aliases are on, QoS 0, not retained,
  payload and metric timestamps.
- **seq:** one counter per edge node over NBIRTH, DBIRTH, NDATA, DDATA and DDEATH, + 1 per message, 255 → 0.
- **Rebirth:** `NCMD` with `Node Control/Rebirth = true` → a new NBIRTH (seq 0, same bdSeq) and all DBIRTHs, with
  the current values.
- **Writes:** `NCMD`/`DCMD` with a writable metric → the new value, confirmed in the next NDATA/DDATA (Q4).
- **Device offline:** `DDEATH` (with seq) when a device goes offline, `DBIRTH` when it comes back.
- **Stop:** an intentional stop publishes the NDEATH itself before disconnecting (the broker doesn't send the will
  on a clean disconnect); the fault "Drop connection" closes the socket, so the broker sends the will.

### 10.3 Model (persisted, `json_serializable`)

```dart
enum DeviceKind { generated, recorded, vda5050, sparkplug }

class SparkplugSource {
  String groupId = 'Plant1';
  String edgeNodeId = 'Edge{n}';          // {n}: the device instance = the edge node
  List<SparkplugMetricSpec> nodeMetrics;   // besides bdSeq and Node Control/Rebirth, which are always there
  List<SparkplugDeviceSpec> devices;      // the devices of every edge node
  int scanMs = 1000;                      // generators are sampled per scan, changed metrics are published
  bool aliases = true;
  String? primaryHostId;                  // wait for this host's STATE (Q2)
  bool simulateHost = true;               // publish the STATE of primaryHostId ourselves
  bool compress = false;                  // SPBV1.0_COMPRESSED with GZIP (Q10)
  int? seed;
}

class SparkplugDeviceSpec { String id = 'Device{d}'; int count = 1; List<SparkplugMetricSpec> metrics; }

class SparkplugMetricSpec {
  String name;                            // may contain '/' for folders, e.g. 'Motor/Speed'
  SpbDataType type;                       // scalar types in v1 (Q7)
  PayloadGenerator generator;             // the simulator's generators, checked against the type
  String? unit;                           // engUnit property
  double deadband = 0;                    // numbers: publish only changes larger than this
  bool writable = false;                  // accepts NCMD/DCMD writes (Q4)
}
```

A new device starts from a preset, "Example edge node":
- node metrics `Uptime` (counter, UInt64, s) and `Firmware` (String);
- a `Pump` device with `Temperature` (wave, Double, °C), `Pressure` (random walk, Float, bar), `Running` (Boolean,
  writable), `Speed` (random walk, Int32, rpm, writable) and `Mode` (value list, String).

Validation in `SimulationRules`: ids without `/`, `+`, `#`; `{n}` in the edge node id with more than one instance;
unique metric names; generators that fit the type; the limits of Q9.

### 10.4 Engine (`lib/simulator/sparkplug/`, without Flutter, on the runner's clock)

- **`SimulatedEdgeNode`**: the state machine of §10.2 (connecting, waiting for host, online, offline) with its
  connection, bdSeq, seq, alias table, current metric values and the online state of its devices.
- **`SparkplugConnection`**: a `SideConnection` with a will, created through a factory so the tests use fake
  adapters. This needs **last will support in `MqttAdapter`**, which has none today, in both protocol clients
  (mqtt5_client and mqtt_client, native and browser), plus an abrupt close for the fault.
- **`SimulatedHost`** (with `simulateHost`): its own connection with the retained will `{"online": false}`; publishes
  `{"online": true, "timestamp": …}` retained on start.
- **`SimulatedSparkplugDevice`** in the runner: starts and stops the edge nodes, collects statistics, injects faults.
  Messages are written with `SparkplugWriter`. The edge nodes publish on their own connections, not through
  `SimulatorPublisher`; the runner's rate limits still count them.

### 10.5 Faults (runtime, per edge node)

| Fault | What happens | Expected rule |
|---|---|---|
| Drop connection | socket closed without DISCONNECT; the broker sends the will; reconnect after 5 s with bdSeq + 1 | none (a correct NDEATH) |
| Restart | NDEATH, disconnect, reconnect with bdSeq + 1, births | none |
| Device offline / online | DDEATH, later DBIRTH | none |
| Skip a seq | the next message's seq + 2 | `seqGap` |
| Unknown metric | NDATA with an alias the birth doesn't have | `unknownMetric` |
| Wrong data type | DDATA with a metric's data type changed | `datatypeMismatch` |
| Data after death | NDEATH published, NDATA continues | `afterDeath` |
| Device data without birth | DDATA of a device before its DBIRTH | `deviceNotBorn` |
| Wrong bdSeq in death | the will carries bdSeq − 1 | `bdSeqMismatch` |
| No timestamp | payload timestamps left out | `timestampMissing` |
| Not Sparkplug | one NDATA with a JSON payload | `payload` |

### 10.6 UI

Like the VDA 5050 device:
- "+ Device" offers "Sparkplug edge node".
- A tabbed dialog with a fixed size (840 px): **Edge node** (group, edge node id, count, primary host, simulate host),
  **Metrics** (node metrics, and devices with their metrics, in an editable table: name, type, generator, unit,
  deadband, writable) and **Advanced** (scan, aliases, compression, seed).
- The device row lists its edge nodes with state (connecting, waiting for host, online, offline), bdSeq, seq and
  messages, and a two-column Faults menu.

### 10.7 CLI

`simulate` runs Sparkplug devices like the others, with a connection per edge node; faults stay app only, as for
VDA 5050. `cli-manual.md` documents it.

### 10.8 Testing

- Fake time and a fake broker that keeps wills, retained messages and subscriptions per connection, so connect,
  will, STATE and NCMD are tested without a real broker.
- Every published payload of a clean run goes through `SparkplugChecker` and gives no findings: for 1 and 20 edge
  nodes, with and without aliases, with compression.
- §10.2 point by point: the will per connection, bdSeq across reconnects, waiting for STATE, the order of births,
  report by exception and deadband, the seq wrap, rebirth, writes, DDEATH/DBIRTH, stop with NDEATH.
- Each fault of §10.5 produces exactly its rule, through `ConformanceChecker`.
- The model's JSON round trip and its validation.

### 10.9 Phases

- **2a:** last will in `MqttAdapter` and both clients, `SparkplugConnection`, the fake broker, the engine and its
  tests (no UI).
- **2b:** model, dialog, device rows, faults; `simulator-design.md` gets the device kind.
- **2c:** CLI, `cli-manual.md`, the end-to-end tests against the check, CLAUDE.md.

### 10.10 Implementation notes, phase 2a (2026-10-27)

Phase 2a is implemented as designed in §10.2 and §10.4, without UI and not yet a device kind of the simulator:

- **Last will:** `MqttAdapter.connect`, `MqttProtocolClient.connect` and `SideConnection.connect` take an optional
  `MqttWill` (`lib/mqtt/mqtt_will.dart`) with a binary payload. mqtt5_client takes the bytes as they are. mqtt_client
  (3.1.1) only writes a UTF-8 will text, which would break a Protobuf NDEATH, so `Mqtt311ProtocolClient` swaps the
  connect payload for a subclass that writes the bytes length-prefixed, as MQTT 3.1.1 allows.
  `test/mqtt/mqtt_will_test.dart` checks the bytes on the wire.
- **Model:** `lib/simulator/model/sparkplug_source.dart` (`SparkplugSource`, `SparkplugDeviceSpec`,
  `SparkplugMetricSpec`, the example preset), JSON round trip tested; not yet part of `SimulatedDevice`.
- **Engine:** `lib/simulator/sparkplug/simulated_edge_node.dart`, `simulated_host.dart` and `metric_values.dart`
  (generated texts to typed values, prefixes and postfixes removed, integers rounded and clamped to their type, writes
  coerced, deadband). The edge node uses its own `MqttAdapter` per connection, not `SideConnection`'s reconnect,
  because every new connection needs a new will with the next bdSeq.
- **Choices made while implementing**, to check against the specification and the TCK in phase 2c:
  - bdSeq counts every CONNECT that is sent, also one the broker refuses.
  - The NDEATH carries only the bdSeq metric, no timestamp (it is written when connecting).
  - Data and commands leave out the data type (the birth has it); `SpbMetric.encodeAs` tells the writer which field
    to use. `Node Control/Rebirth` gets alias 0 when aliases are on, the other metrics 1 and up, unique over the edge
    node and its devices.
  - A stop publishes the NDEATH (QoS 1) only when the edge node was born; a STATE older than the last one is
    ignored; a lost primary host means NDEATH, disconnect, and a new connection after 1 s that waits for the host.
  - A write is answered at once with an NDATA/DDATA of the written metrics.
- **A bug the tests found:** without a data type, the writer chose no Protobuf field and dropped the value, and the
  reader read a negative Int32 as its unsigned bits. `SparkplugReader.retype` now reads a value again as the birth's
  type; the profile and the edge node's write handling use it.
- **Fake broker** (`test/helpers/fake_broker.dart`): connections with wildcard subscriptions, retained messages, wills
  on a dropped connection, client id takeover and delivery in microtasks. `test/simulator/sparkplug/
  simulated_edge_node_test.dart` runs §10.2 point by point in fake time, and every run's messages through
  `SparkplugChecker` without findings.
- **Left for 2b:** the device kind in `Simulation` and the runner (rate limits, statistics, start and stop with the
  simulation), the dialog and device rows, the faults of §10.5 including the abrupt close of a connection, which the
  client packages don't offer directly.

### 10.11 Implementation notes, phases 2b and 2c (2026-10-27)

- **Device kind:** `DeviceKind.sparkplug` with `SimulatedDevice.sparkplug`. `SimulationRules.validateSparkplug` checks
  the ids (topic levels, `{n}` with several edge nodes, `{d}` for a device that is there more than once), metric names
  (not empty, not `bdSeq` or `Node Control/Rebirth`, unique per edge node or device), that the generator fits the data
  type (numbers from random number, counter, random walk and wave; booleans from boolean and value list; date times
  from the timestamp generator; texts from anything but images), scalar types only (Q7) and the limits of Q9.
- **Runner:** `SimulatorRunner` takes `SimulatorConnections` (`simulator_publisher.dart`): the broker settings and an
  adapter factory. The `Simulator` service passes the project's settings and `MqttAdapter.new` (tests pass fake
  adapters), the CLI its own settings and adapters. Each edge node connects with
  `SideConnection.settingsFor(settings, 'spb-<edge node id>')`, so it gets a client id of its own. Without connections
  a Sparkplug device reports `sparkplugNoConnections`; a simulated host that can't connect stops the device with
  `sparkplugHostFailed`. Edge nodes that can't connect keep trying and show it in their state.
- **Faults** (`sparkplug_fault.dart`), as in §10.5. "Drop connection" uses the client packages' own reaction to a
  broker that stopped answering (`disconnectOnNoPingResponse`), which closes the socket without DISCONNECT, through the
  new `MqttAdapter.dropConnection()`; the edge node then reconnects with the usual delays (1 s first), not after a
  fixed 5 s. "Devices offline" is one toggle for all devices of the edge node. "Device data without birth" uses a device
  `UnbornDevice`. "Death with a wrong bdSeq" leaves with the NDEATH of bdSeq − 1 and connects again.
  `test/simulator/sparkplug/sparkplug_runner_test.dart` checks through `ConformanceChecker` that each protocol fault
  gives exactly its rule and each session fault none.
- **UI:** "+ Device" offers "Sparkplug edge nodes" (`Icons.hub`), starting from the example with 2 edge nodes. The
  dialog (`sparkplug_device_dialog.dart`, 840 px, tabs EDGE NODE, METRICS, ADVANCED) lists the metrics of the edge node
  and of each device; a metric is edited in `sparkplug_metric_dialog.dart` with the simulator's `GeneratorEditor`
  (templates and images left out). The METRICS tab scrolls inside a fixed height. The device rows show each edge node's
  state, bdSeq, the seq of its last message, messages sent and how many devices are online, with the Faults menu
  (`SparkplugFaultMenu`, two columns like the robots'). The eye button subscribes the Topic Viewer to
  `spBv1.0/<group>/#`; it now works for VDA 5050 and Sparkplug devices alike. Clear retained removes the STATE of a
  simulated host.
- **CLI:** `simulate` runs Sparkplug devices with a connection per edge node and the plan names the edge nodes and
  their group (`cli-manual.md`). `test/cli/sparkplug_cli_test.dart`.
- **Still to check against the specification text and the TCK** (§10.10): bdSeq per CONNECT, the NDEATH without
  timestamp, data and commands without data type. The simulator hasn't run against a real broker or host application
  yet; the tests use fake connections and an in-memory broker.

## 11. Questions of the simulator (decided 2026-10-27)

All proposals were accepted as written.

| # | Question | Decision |
|---|---|---|
| Q1 | A real connection per edge node (needed for a real NDEATH last will), or all edge nodes on the main connection with a faked NDEATH, like VDA 5050's CONNECTION_BROKEN? | Real connections; that is the point of "follows the specification" |
| Q2 | Should the simulator also play the primary host (publish its STATE), or only wait for an external one? | Both: `primaryHostId` is optional; `simulateHost` is on by default when a host id is set |
| Q3 | Metrics from the simulator's generators (configurable), or a fixed example set only? | Generators, with the example preset as the start |
| Q4 | What does a write (NCMD/DCMD) do to a metric that has a generator: hold the written value until the next write, until the next scan, or for a set time? | Hold it until the next write; the generator pauses for that metric |
| Q5 | Sparkplug 3.0 only, or also 2.2 behavior (text STATE under `STATE/{host}`)? | 3.0 only |
| Q6 | MQTT 5 or 3.1.1 for the edge node connections? | The project's protocol version, like the main connection |
| Q7 | Which data types in v1: scalars only, or also arrays, DataSets, Templates and properties beyond `engUnit`? | Scalars and `engUnit`; the rest later |
| Q8 | Store and forward: while the host is offline, buffer data and send it as historical after the next birth? | Later |
| Q9 | Limits: edge nodes per device, devices per edge node, metrics per device? | 20 edge nodes (connections), 20 devices, 200 metrics; at most 2000 metric changes per second in total |
| Q10 | Offer compressed payloads? | Yes, a checkbox (GZIP); it tests the receivers' decompression |
| Q11 | Should "Request rebirth" (§8.1) come with this phase, since the simulator answers it? | Yes; it is small and the simulator makes it testable |
