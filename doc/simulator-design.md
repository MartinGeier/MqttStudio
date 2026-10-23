# MQTT Simulator – Detailed Design

Status: **Final** (all sections reviewed). Amended for the headless CLI with D20–D21, see `cli-design.md`, and for recorded devices with D22–D25, see `recorder-design.md` · Branch: `mqtt5` · Last updated: 2026-10-24

## 1. Purpose

The simulator publishes generated MQTT messages on a schedule. It lets users test dashboards,
backends and the MQTT Studio viewers without real devices. It lives in the existing (currently hidden)
**SIMULATOR** tab and is saved as part of the `Project`.

### Goals (v1)
- Define simulated topics with a typed payload generator, an interval, QoS and the retain flag.
- **Simulated devices:** one definition expands to N instances (`plant/{n}/temp`), each with its own
  generator state.
- Generators: random string, random number, counter, bool, value list, random walk, wave, timestamp,
  GPS track, random image and template (JSON or any text) built from named fields.
- Start and stop everything, one device or one topic. Show live stats (messages sent, last payload, errors).
- MQTT 5 publish properties: content type, message expiry, user properties.
- Store everything in the `Project` as typed JSON. Older projects without a simulation still load.
- Generated data shows up correctly in the existing viewers: numbers chart, `lat,lon` shows on the map,
  JPG/PNG shows as an image.

### Non-goals (v1)
- Exporting or importing a simulation as a separate file (it travels with the project).
- Auto-start when a project is opened.
- Replaying recorded messages in a simulation was a non-goal and is now covered by recorded
  devices (D22). Recording itself belongs to the RECORDER tab (`recorder-design.md`).
- Scripting or expressions beyond the generator set.
- Request/response simulation (reacting to incoming messages).
- Stop conditions ("stop after N messages / after T minutes").
- Time-based placeholders in topics (`{ts}`), because topics are resolved once at start.
- Per-instance statistics.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| D1 | Replace the `key=value;` definition-string format with a typed model serialized via `json_serializable` | User |
| D2 | Simulation is stored in `Project` only, no separate file export | User |
| D3 | Simulated devices (N instances via `{n}`) are in v1 | User |
| D4 | v1 adds random walk, wave, timestamp, GPS track and random image | User |
| D5 | Configuration (persisted) and runtime state (counters, walk positions) are separate objects | Design, see §4.4 |
| D6 | JSON templates use **named fields** edited with the normal generator editor instead of an inline mini-syntax | Design, see §5.3 |
| D7 | `IncrementingNumber` and `IncrementingCode` merge into one **Counter**. `DiscreteStrings` and `DiscreteNumbers` merge into one **Value list** | Design |
| D8 | Simulation stops on disconnect and on project close. No auto-resume | User (accepted default) |
| D9 | Counters and walks reset on every start | User (accepted default) |
| D10 | The existing `simulated_messages_definition.dart` and its test are deleted, not migrated (never shipped, never persisted) | Design |
| D11 | Rate limits: warning above 100 msg/s (web: 50), start refused above 1000 msg/s | User (accepted default) |
| D12 | At most 1000 instances per device | User (accepted default) |
| D13 | No stop conditions and no `{ts}` in topics in v1 (see non-goals) | User (accepted default) |
| D14 | Every topic belongs to a device. A new simulation starts with a device named "Default" (count 1). The device header is always shown | User |
| D15 | New topics default to QoS 0 | User |
| D16 | Statistics are aggregated per topic across all instances | User |
| D17 | Random walk and GPS movement are scaled by elapsed time, not per message | User |
| D18 | No persisted `enabled` flag. A topic is only running or stopped. **Start all** starts every topic, ▶ on a device or topic starts only that | User |
| D19 | Saving an edit to a running topic or device restarts it right away with the new config (state resets per D9) | User |
| D20 | Device names are unique within a simulation (validated in the device dialog), so the CLI can select devices by name | Design, for the CLI (draft) |
| D21 | `SimulatorRunner` reports connection loss but does not act on it. The owner decides: the app's viewmodel stops (D8), the CLI stops or reconnects. Rate estimation and validation are shared functions | Design, for the CLI (draft) |
| D22 | A device is either **generated** (topics with generators, as before) or **recorded**: it replays a recording from the recordings library through the recorder's `RecordingPlayer` (§4.5) | User (recorder R4) |
| D23 | A recorded device references its recording by id, with the file name as a fallback. A missing recording doesn't stop the project from loading; it is a start error for that device, like a missing image folder | Design, for the recorder (draft) |
| D24 | Recorded devices use `instanceCount` and `firstInstance`. With more than one instance, a topic remap target must contain `{n}` (§6.2). One player runs per instance, started staggered, aligned or at a random position | Design, for the recorder (draft) |
| D25 | Recorded devices play at 0.1×–100×, not at Max speed, so their rate can be estimated (recorder R12). Statistics are per recorded topic, aggregated over instances (D16) | Design, for the recorder (draft) |

## 3. Current state (for reference)

- `lib/simulator/model/simulated_messages_definition.dart`: generator classes with a string
  format. Not referenced by the app. Known defects: the JSON template result is discarded, the
  string round trip is broken by `"; "` separators, a few crash cases. All of it is replaced by
  this design (D10).
- `main_appbar.dart` already has the SIMULATOR tab (`visible: false`). `MessageViewerPage` sets up
  `DefaultTabController(length: 4)`, but the body **ignores the selected tab**, so tab switching
  has to be added.
- `MqttAdapter.publish` supports string, bool and binary payloads, plus QoS and retain, and casts
  string payloads with `as String`. It has no user properties or other MQTT 5 properties.
- `Project.getHash()` hashes the full JSON to detect unsaved changes. Anything in `Project` that
  changes while running would mark the project dirty, which is why D5 exists.
- Viewer detection in `message_detail_view.dart`: a plain number payload becomes a chart, a plain
  `lat,lon` payload becomes the map, and JPG magic bytes become an image.
- Correction to the earlier analysis: importing `dart:io` does **not** break the web build. The
  app already imports it in several files. `File` and `Directory` throw at runtime on web, so the
  image generator must be disabled on web (§5.2).

## 4. Domain model

### 4.1 Overview

```
Project
 └─ simulation: Simulation
     └─ devices: List<SimulatedDevice>        (a "device" with instanceCount 1 is just a group)
         ├─ name, instanceCount, firstInstance
         ├─ kind: generated | recorded        (D22)
         ├─ recorded: RecordedSource?         recorded devices only (§4.5)
         └─ topics: List<SimulatedTopic>      generated devices only
             ├─ topic template  ("plant/{n}/temp")
             ├─ qos, retain, interval
             ├─ mqtt5: Mqtt5PublishProperties
             └─ generator: PayloadGenerator   (sealed hierarchy, §5)
```

Why a two-level device/topic model instead of a flat topic list with a per-topic instance count:
real devices publish several topics (temp, humidity, position). With a device level, the user
sets the instance count once, and all topics of instance 7 share `{n}=7`.

Every topic belongs to a device (D14). There are no loose topics, so the model, runner and UI each
have one code path. A new simulation is created with one device named "Default"
(`instanceCount 1`). For a quick single-topic test, the user just adds a topic to it.

### 4.2 Classes (persisted)

```dart
@JsonSerializable(explicitToJson: true)
class Simulation {
  int schemaVersion = 1;
  List<SimulatedDevice> devices = [];
}

@JsonSerializable(explicitToJson: true)
class SimulatedDevice {
  String id;              // uuid, stable key for runtime state and UI
  String name;            // "Weather station"
  int instanceCount;      // 1..1000, default 1
  int firstInstance;      // default 1, so {n} runs firstInstance..firstInstance+count-1
  DeviceKind kind;        // generated (default) | recorded (D22)
  RecordedSource? recorded;       // set when kind == recorded, then topics is empty
  List<SimulatedTopic> topics;
}

@JsonSerializable(explicitToJson: true)
class SimulatedTopic {
  String id;              // uuid
  String topic;           // template, may contain {n}, {n:3}, {device}
  MqttQos qos;            // default atMostOnce (QoS 0, D15)
  bool retain;            // default false
  PublishInterval interval;
  Mqtt5PublishProperties mqtt5;
  @JsonKey(fromJson: PayloadGenerator.fromJson, toJson: PayloadGenerator.toJsonStatic)
  PayloadGenerator generator;
}

@JsonSerializable()
class PublishInterval {
  int minMs;              // default 1000
  int maxMs;              // == minMs for a fixed interval, > minMs for a random interval
}

@JsonSerializable(explicitToJson: true)
class Mqtt5PublishProperties {
  String? contentType;            // null = auto (see §7.3)
  int? messageExpirySeconds;      // null = none
  List<KeyValue> userProperties;  // values may contain placeholders
}
```

### 4.3 Project integration and backward compatibility

```dart
// in Project
@JsonKey(fromJson: Simulation.fromJsonOrEmpty)
Simulation simulation = Simulation();

static Simulation fromJsonOrEmpty(Map<String, dynamic>? json) =>
    json == null ? Simulation() : Simulation.fromJson(json);
```

Projects saved before this feature have no `simulation` key and load with an empty simulation.
`schemaVersion` allows later migrations. `getHash()` covers the simulation automatically, so
editing it marks the project as changed, which is what we want. Devices saved without `kind`
load as `generated`.

### 4.4 Config vs. runtime state (D5)

Generators are **immutable configuration**. On start, each generator creates a
`GeneratorInstance` that holds the mutable state (counter value, walk position, GPS position,
cached image list). There is one instance per (topic × device instance). Runtime state never
enters `Project`, so running the simulator does not mark the project as changed, and two devices
never share a counter.

```dart
sealed class PayloadGenerator {
  String get typeKey;
  GeneratorInstance createInstance(GeneratorContext ctx);
  Map<String, dynamic> toJson();
  static PayloadGenerator fromJson(Map<String, dynamic> json) => switch (json['type']) {
        'randomString' => RandomStringGenerator.fromJson(json),
        // ...
        _ => throw FormatException('Unknown generator type ${json['type']}'),
      };
}

abstract class GeneratorInstance {
  // now: current time. elapsed: time since this instance's previous message,
  // or since its start for the first message (used by random walk and GPS, D17).
  GeneratedValue next(DateTime now, Duration elapsed);
}

class GeneratedValue {
  final String? text;                 // text payloads (UTF-8 encoded on publish)
  final Uint8List? bytes;             // binary payloads (image)
  final Map<String, String> parts;    // named sub-values, e.g. GPS lat/lon for templates
}

class GeneratorContext {
  final Random random;                // injected: seeded in tests
  final int instanceNumber;           // value of {n}
  final String deviceName;
  final DateTime startedAt;           // time base for wave
}
```

Polymorphic JSON uses a `type` discriminator in a hand-written `fromJson` switch. Subclasses use
normal `@JsonSerializable`. This doesn't depend on `json_serializable`'s union support.

### 4.5 Recorded devices (D22–D25)

```dart
@JsonSerializable(explicitToJson: true)
class RecordedSource {
  String recordingId;             // RecordingHeader.id in the recordings library (D23)
  String fileName;                // fallback when the id is not found, e.g. after a copy
  PlaybackOptions playback;       // from recorder-design.md §6.2: topics, speed, loop, range,
                                  // gaps, remaps (with {n}), snapshot, retain, QoS, instanceStart
}
```

- The recording itself stays in the library (recorder R2). The project only holds this reference
  and the options, so editing them marks the project as changed and running doesn't (D5).
- The recorder tab's **ADD TO SIMULATION** creates a recorded device named after the recording,
  with its current playback options and `instanceCount 1`.
- Placeholders (§6.1) work in remap targets. The validation of §6.2 applies to the remapped
  topics: no wildcards, and `{n}` is required when `instanceCount > 1` (D24).

## 5. Generators

All numeric generators default to **no prefix or postfix**, so payloads stay pure numbers and
show up as charts in the viewer. Prefix and postfix are still available (`21.4 °C`).

| Key | Name | Parameters (defaults) | Output | Notes |
|---|---|---|---|---|
| `randomString` | Random string | `minLength 3`, `maxLength 10` (both inclusive), `charSet [A-Za-z0-9]`, prefix, postfix | text | Validation: 0 ≤ min ≤ max, non-empty charSet |
| `randomNumber` | Random number | `min 0`, `max 100`, `decimals 0`, prefix, postfix | text | Uniform distribution; `min ≤ max` |
| `counter` | Counter | `start 1`, `step 1`, `decimals 0`, `resetAfter null`, prefix, postfix | text | Replaces IncrementingNumber/Code (`ORD-` prefix gives codes). `resetAfter`: wrap to start after N values |
| `bool` | Boolean | `trueProbability 0.5`, `trueText "true"`, `falseText "false"` | text | `1`/`0` or `ON`/`OFF` through the texts |
| `valueList` | Value list | `values ["A","B","C"]`, `mode random\|sequential` | text | Replaces DiscreteStrings/Numbers. Stored as a JSON list, so no escaping is needed |
| `randomWalk` | Random walk | `start 20`, `min 0`, `max 40`, `volatility 0.5` (per √second), `decimals 1`, prefix, postfix | text | Time-scaled (D17, §5.1). Reflects at bounds. Looks like a real sensor |
| `wave` | Wave | `shape sine\|square\|triangle\|sawtooth`, `offset 0`, `amplitude 1`, `periodSeconds 60`, `phaseDegrees 0`, `noise 0`, `decimals 2`, prefix, postfix | text | Uses wall-clock time since start, so the curve does not depend on the publish interval |
| `timestamp` | Timestamp | `format iso8601\|epochMillis\|epochSeconds\|pattern`, `pattern` (intl `DateFormat`), `utc true` | text | Mostly used inside templates |
| `gpsTrack` | GPS track | `mode wander\|route`, `centerLat`, `centerLon`, `radiusMeters 1000` and `turnRateDegPerSecond 15` (wander), `waypoints` (route, loops), `speedMps 10`, `decimals 6`, `format latLon\|json` | text + parts `lat`, `lon` | Default `latLon` → `"48.137154,11.576124"`, which the map viewer recognizes. Each instance starts at a different random position |
| `randomImage` | Random image | `folderPath`, `extensions [.jpg,.jpeg,.png]`, `mode random\|sequential` | bytes | Desktop only (§5.2). Not allowed inside templates |
| `template` | Template | `template` text, `fields: Map<String, PayloadGenerator>`, `validateJson true` | text | §5.3 |

### 5.1 Behavior details
- **Rounding:** `decimals` formats with `toStringAsFixed`. `decimals 0` prints an integer
  (`42`, not `42.0`).
- **Random walk step (D17):** `step = uniform(−1, 1) × volatility × √elapsedSeconds`. The square
  root keeps the spread of values over a given time span the same whatever the interval. A topic
  publishing every 100 ms and one publishing every 10 s drift equally far in a minute; the faster
  one just shows more points along the way. The parameter is called `volatility`, not
  `maxStep`, because the step per message now depends on the interval.
- **Random walk reflection:** if `v + step` leaves `[min, max]`, mirror it back inside. If
  `start` is outside the range, clamp it.
- **Wave:** `value = offset + amplitude * shape(2π·t/period + phase) + uniform(−noise, +noise)`,
  with `t` = time since start.
- **GPS wander (D17):** heading changes by up to ±`turnRateDegPerSecond × elapsedSeconds`.
  Distance moved = `speedMps × elapsedSeconds`. The track turns back toward the center when it
  would leave `radiusMeters`.
- **GPS route:** moves along the waypoint polyline at `speedMps` and loops back to the first
  waypoint. It needs at least 2 waypoints. In v1 waypoints are entered as text, one `lat,lon` per line.
- **Value list sequential:** cycles in order. Each instance has its own index.

### 5.2 Random image (desktop only)
- On `kIsWeb` the generator is hidden from the type dropdown. If a project with an image topic is
  opened on web, the topic shows the error "not supported in browser" and is skipped on start.
- The folder is listed **once** when the instance is created, not on every message. An empty
  folder or a missing path is a start error for that topic.
- Files over 500 KB are skipped. This matches the publish dialog limit. If no usable file remains,
  that is an error.
- Publishes the raw bytes (binary), so the viewer's JPG/PNG detection shows the image.

### 5.3 Template generator (D6)
The template is free text with `{{field}}` and `{{field.part}}` references, plus the placeholders
from §6.1. Each field is a normal generator, edited in the same UI.

```
template:
{
  "deviceId": "ws-{n:3}",
  "ts": "{{ts}}",
  "temperature": {{temp}},
  "status": "{{status}}",
  "position": { "lat": {{pos.lat}}, "lon": {{pos.lon}} }
}

fields:
  ts     → timestamp(iso8601)
  temp   → randomWalk(start 20, min 15, max 30, decimals 1)
  status → valueList(["ok","warning","error"])
  pos    → gpsTrack(wander, center 48.137,11.575)
```

Rules:
- Each field is generated **once per message**. `{{pos.lat}}` and `{{pos.lon}}` therefore come
  from the same position.
- Allowed field types: every generator **except** `template` (no nesting) and `randomImage`
  (binary).
- Field names: `[A-Za-z_][A-Za-z0-9_]*`. A reference to an unknown field is a validation error in
  the editor, not a runtime error.
- The user writes the quotes. `{{temp}}` stays a JSON number and `"{{status}}"` a string. This
  keeps the generator format-agnostic (CSV, XML, plain text all work).
- `validateJson` (on by default): the editor preview runs `jsonDecode` on a sample and shows a
  warning if it fails. At runtime no validation is done, to keep it cheap.

Why named fields instead of `{{rn min=1 max=10}}` inline syntax: there's only one serializer and
one editor, so no second parser can drift (that drift caused the old bugs). It also supports
multi-value generators (GPS parts) and gives typed validation.

## 6. Placeholders and devices

### 6.1 Placeholders
They are resolved in the topic, in template text and in user property values:

| Placeholder | Meaning | Example (`n = 7`) |
|---|---|---|
| `{n}` | instance number | `7` |
| `{n:3}` | instance number zero-padded to width 3 | `007` |
| `{device}` | device name, with `/`, `+`, `#` replaced by `_` | `Weather_station` |

`{n}` and `{device}` are fixed per instance, so the topic string is resolved **once at start**,
not per message. Template placeholders are resolved per message, together with the fields.

### 6.2 Topic validation
- A topic must not contain `+` or `#` after resolution (same rule as the publish dialog).
- If `instanceCount > 1`, the topic must contain `{n}`. Otherwise all instances would publish to
  the same topic. This is a validation error with a hint.
- Duplicate resolved topics across the whole simulation are a warning, not an error. It can be
  intentional, e.g. two generators writing one topic.

## 7. Runtime engine

### 7.1 Components

```
SimulatorRunner (GetIt singleton, lib/simulator/engine/simulator_runner.dart)
 ├─ start(simulation) / startDevice(id) / startTopic(id) / stop…
 ├─ Map<topicId, TopicRun>            one per running SimulatedTopic
 │    └─ List<InstanceRun>            one per device instance: resolved topic, GeneratorInstance, Timer
 ├─ Map<deviceId, RecordedDeviceRun>  one per running recorded device (D22)
 │    └─ List<RecordingPlayer>        one per device instance (D24), from lib/recorder/engine
 ├─ SimulatorPublisher (interface)    production: MqttAdapter, tests: fake recorder
 ├─ stats: Map<topicId, TopicStats>   aggregated over all instances (D16): total sent,
 │                                    last payload + its instance number + time, error
 └─ events: runStateChanged, statsChanged (throttled)
```

`SimulatorRunner` does not depend on Flutter widgets. `SimulatorViewmodel` (an `SrxChangeNotifier`)
subscribes to its events, matching the `MessageViewer` / `MessageViewerViewmodel` split.

### 7.2 Scheduling
- One one-shot `Timer` per `InstanceRun`, rescheduled after each publish. One-shot rather than
  `Timer.periodic` because random intervals need a new delay each time.
- **Start stagger:** the first publish of each instance is delayed by uniform(0, interval). This
  stops 500 instances from firing in the same millisecond.
- Delay for each next message is uniform(`minMs`, `maxMs`).
- Minimum interval: 50 ms (validation).
- **Rate estimate:** Σ over the topics about to run (all for Start all, or one device or topic) of
  `instanceCount × 1000 / avgIntervalMs` (recorded devices: `instanceCount ×` the recording's
  rate for the selected topics and range `× speed`, recorder §6.2), plus what is already running,
  including playback in the recorder tab. Shown in the
  toolbar. Warning above **100 msg/s** (web: 50). Start is refused above **1000 msg/s**. Both are
  constants, open to tuning.

### 7.3 Publish path
1. `GeneratorInstance.next(now)` returns `GeneratedValue`.
2. Text is UTF-8 encoded and bytes are used as-is.
3. `SimulatorPublisher.publish(topic, bytes, qos, retain, properties)`.
4. Update the topic's aggregated stats: increment the total and overwrite the last payload and
   instance number. Text is truncated to 200 chars, binary is shown as `<binary 12.3 KB>`.

`MqttAdapter` gets a new method. The existing `publish` stays unchanged for the publish dialog:

```dart
void publishBytes(String topic, Uint8Buffer data, MqttQos qos, bool retain,
    {String? contentType, int? messageExpirySeconds, List<MqttUserProperty>? userProperties,
     bool? payloadIsUtf8});
```

Implementation: if only user properties are set, use `publishMessage(..., userProperties:)`. If
content type or expiry are set, build an `MqttPublishMessage` with `withContentType`,
`withMessageExpiryInterval` and `withPayloadFormatIndicator`, then call `publishUserMessage`. Both
APIs exist in `mqtt5_client` 5.1.0.

**Auto content type** (when `contentType == null`): `template` with `validateJson` →
`application/json`; `randomImage` → `image/jpeg` or `image/png` from the file extension; others →
none. The payload format indicator is set to UTF-8 for all text generators.

### 7.4 Lifecycle and errors

| Event | Behavior |
|---|---|
| Start while disconnected | Start buttons disabled. Tooltip "Connect to a broker first" |
| Disconnect (`onDisconnectedEvent`) | The runner reports it (D21). The app's viewmodel stops all, keeps stats, snackbar "Simulation stopped: disconnected" |
| Project closed / another project opened | Stop all, clear stats |
| Topic edited while running (D19) | On save, that topic restarts with the new config (its state resets, D9). Others keep running |
| Device edited while running (D19) | On save, all running topics of that device restart. A changed instance count adds or removes instances |
| Topic/device deleted while running | Stopped first, then removed |
| Generator throws (e.g. image folder deleted) | That `TopicRun` stops, the error shows in its row. Others continue |
| Recording of a recorded device missing or unreadable (D23) | That device doesn't start, the error shows in its header row. Others continue |
| Recorded device reaches the end of its range without loop | That device stops and shows "finished". Others continue |
| Publish throws (`MqttConnectionException`) | Treated like a disconnect |
| App closed | Timers die with the process. Nothing is persisted |

**Retained messages:** stopping does not remove retained messages from the broker. The toolbar
offers **Clear retained**: for each resolved topic of retained simulated topics, it publishes an
empty retained payload. It's an explicit action, not automatic.

## 8. UI

### 8.1 Tab plumbing
- `main_appbar.dart`: make the SIMULATOR tab visible.
- `MessageViewerPage`: switch the body on `DefaultTabController.of(context).index`, either with a
  `TabBarView` or an `IndexedStack`. Index 0 is the existing topic viewer, 1 is the new
  `SimulatorPage`. The connect button stays in the app bar. Recorder and documentation tabs stay
  hidden.
- Use an `IndexedStack`, so the topic viewer keeps its state and scroll position while you are on
  the simulator tab.

### 8.2 Simulator page

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ [▶ Start all] [■ Stop all]  [+ Device] [+ Topic]  [Clear retained]   ≈ 42 msg/s   │
├──────────────────────────────────────────────────────────────────────────────────┤
│ ▼ ● Weather station   ×10 (1–10)                              [▶] [✎] [⧉] [🗑]  │
│     ● temp      weather/{n}/temp      Random walk   1 s      12,340  21.4 (#7)  [▶][✎][⧉][🗑][👁] │
│     ● humidity  weather/{n}/humidity  Random number 5 s       2,468  63 (#2)    [▶][✎][⧉][🗑][👁] │
│     ○ position  weather/{n}/pos       GPS track     2 s–4 s       0  –          [▶][✎][⧉][🗑][👁] │
│ ▼ ● Default           ×1                                      [▶] [✎] [⧉] [🗑]  │
│     ● status    factory/line1/status  Template      10 s        123  {"deviceId…        │
│     ⚠ images    cams/1/snapshot       Random image  30 s     Folder not found           │
│ ▼ ● Line 1 night shift ×20 (1–20)  ⟲ recorded · 2× · loop · 02:14:05 / 8:00:00  [▶] [✎] [⧉] [🗑]  │
│     ● plant/line1/temp  → test/line{n}/temp                       57,600  21.4 (#3)  [👁] │
│     ● plant/line1/state → test/line{n}/state                         624  {"status…  [👁] │
└──────────────────────────────────────────────────────────────────────────────────┘
 ● running  ○ stopped  ⚠ error     ⧉ duplicate   👁 subscribe in Topic Viewer
```

- The device header is always shown (D14). **+ Topic** adds to the selected device, or to the
  first device if none is selected. If the simulation has no devices (the user deleted them
  all), it creates "Default" first.
- The last payload of a multi-instance topic shows which instance sent it, e.g. `21.4 (#7)`
  (D16). Instance-count-1 devices show no `(#n)`.
- **👁 Subscribe in Topic Viewer:** adds a subscription with `{n}` replaced by `+` (for example
  `weather/+/temp`) through `MessageViewer.addTopicSubscription`. If it already exists, it is not
  added again.
- The row's last payload and counter refresh **at most every 500 ms**. Updating once per message
  would hurt UI performance, especially on web.
- With no project open, the page shows an empty state "Open a project to create simulations".
- **Recorded devices (D22):** the header shows the `history` icon, the playback summary (speed,
  loop) and the position in the recording (of the first instance). The rows below are the
  selected recorded topics with their remapped target, read-only: they have only 👁. Editing goes
  through the device dialog. **+ Topic** is disabled when a recorded device is selected.
- **+ Device** offers "Generated device" and "Recorded device".

### 8.3 Device dialog
Name, instance count (1–1000), first instance number. A live line shows the resolved range, for
example "Instances 1–10: `weather/1/temp` … `weather/10/temp`".

For a recorded device the dialog adds a recording picker (from the library: name, date, duration,
messages), the topic selection, and the recorder's `PlaybackOptionsEditor` (recorder §11.4)
without Max speed (D25) and with the instance start option. The resolved-range line shows the
remapped topics of the first and last instance.

### 8.4 Topic dialog (reactive_forms, like `PublishTopicViewmodel`)

```
Topic        [weather/{n}/temp                 ]   Resolved: weather/1/temp
QoS          (0●) (1) (2)     Retain [ ]
Interval     [1000] ms   [ ] random up to [ ] ms
Generator    [Random walk          ▾]
  ┌ Random walk ───────────────────────────────┐
  │ Start [20]  Min [0]  Max [40]  Max step [0.5]  Decimals [1]
  │ Prefix [  ]  Postfix [  ]
  └─────────────────────────────────────────────┘
▸ MQTT 5 properties   (content type, message expiry, user properties)
Preview  [Generate]   21.0 · 21.3 · 20.9 · 21.4 · 21.8     (5 samples, instance 1)
                                                      [Cancel] [Save]
```

- **Layout (from the screen designs):** the dialog is 960px wide with two tabs, so it fits a
  900px-high window without scrolling.
  - **PAYLOAD:** topic, interval, up to, generator in one row, then the generator's parameters
    and the preview.
  - **MQTT:** QoS, retain, content type, message expiry and user properties.
  - The subtitle under the title summarizes the MQTT tab (e.g. "QoS 1, retained · 2 user
    properties"), so nothing set there is hidden.
  - A random interval is set by filling in **Up to (ms)**. Leaving it empty means a fixed
    interval, so no separate checkbox is needed.
- `GeneratorEditor` is a widget that switches on the generator type and renders that type's
  form. It is reused for template fields.
- Changing the generator type shows that type's defaults. Values entered for other types are kept
  while the dialog is open, so switching back and forth loses nothing. Only the selected type is
  saved.
- **Preview** builds a throwaway `GeneratorInstance` with a fresh `Random` and calls `next()` five
  times. For templates it shows one formatted sample plus a JSON validity check.
- Template editor: a multi-line text field, a list of fields (name, type, ✎ opens a nested
  `GeneratorEditor` dialog, 🗑), and a "+ Field" button. Unknown `{{refs}}` are highlighted as
  errors.

## 9. Files

New:
```
lib/simulator/model/simulation.dart              Simulation, SimulatedDevice, DeviceKind, RecordedSource, SimulatedTopic, PublishInterval, Mqtt5PublishProperties (+ .g.dart)
lib/simulator/model/payload_generators.dart      sealed PayloadGenerator + 11 subclasses (+ .g.dart)
lib/simulator/engine/generator_instances.dart    GeneratorInstance implementations, GeneratedValue, GeneratorContext
lib/simulator/engine/placeholders.dart           {n}, {n:3}, {device} resolution and validation
lib/simulator/engine/simulator_runner.dart       SimulatorRunner, TopicRun, InstanceRun, TopicStats
lib/simulator/engine/simulator_publisher.dart    interface + MqttAdapter-backed implementation
lib/simulator/simulator_page.dart
lib/simulator/simulator_viewmodel.dart
lib/simulator/widgets/simulation_list.dart
lib/simulator/widgets/simulator_command_bar.dart
lib/simulator/device_edit_dialog.dart (+ viewmodel)
lib/simulator/topic_edit_dialog.dart (+ viewmodel)
lib/simulator/widgets/generator_editor.dart
lib/simulator/widgets/template_editor.dart
test/simulator/payload_generators_test.dart
test/simulator/placeholders_test.dart
test/simulator/simulation_serialization_test.dart
test/simulator/simulator_runner_test.dart
```

Changed:
```
lib/model/project.dart (+ regenerated project.g.dart)   simulation field with fallback
lib/mqtt/mqtt_adapter.dart                              publishBytes with MQTT 5 properties
lib/main.dart                                           register SimulatorRunner
lib/common/widgets/main_appbar.dart                     show SIMULATOR tab
lib/message_viewer/message_viewer_page.dart             IndexedStack body by tab index
assets/i18n/en.json                                     simulator.* strings
pubspec.yaml                                            dev dependency fake_async (runner tests), uuid if not already transitive
```

Deleted: `lib/simulator/model/simulated_messages_definition.dart` and
`test/simulated_messages_defintion_test.dart` (D10).

## 10. Testing

- **Generators:** each generator with a seeded `Random` covers bounds, inclusivity, rounding,
  prefix and postfix, sequential modes, counter `resetAfter`, random walk reflection, wave values
  at known `t`, GPS staying inside the radius and following the route.
- **Time scaling (D17):** a random walk run for 60 s at 100 ms and at 10 s intervals (many seeds)
  ends with a similar spread. GPS distance after 60 s is `speed × 60` whatever the interval
  (route mode).
- **Template:** field references, `.part` access, one evaluation per field per message, unknown
  field validation, JSON validity.
- **Placeholders:** `{n}`, `{n:3}`, `{device}` sanitizing, validation (`{n}` required when count
  > 1, wildcards).
- **Serialization:** round trip of a full simulation including every generator type. Loading a
  pre-feature project JSON without the `simulation` key. An unknown generator `type` fails with
  `FormatException`.
- **Runner** (with `fake_async` and a fake publisher): stagger and interval timing, random
  intervals within range, per-instance state independence, stop on disconnect, error isolation
  (one failing topic doesn't stop others), restart on edit, rate cap refusal.
- **Project dirty check:** running the simulator for N ticks leaves `hasProjectChanged()` false.
- **Recorded devices:** serialization round trip, old devices without `kind` load as generated,
  missing recording is a start error for that device only, `{n}` remap per instance, the three
  instance start modes, rate estimate, end of range stops the device, Max speed is rejected.
- Manual: a local broker (e.g. Mosquitto) with the Topic Viewer subscribed. Check chart, map and
  image rendering, on desktop and web.

## 11. Implementation phases

| Phase | Content | Done when |
|---|---|---|
| 1 | Model, generators, placeholders, serialization, tests | All unit tests green, no UI |
| 2 | `SimulatorPublisher`, `MqttAdapter.publishBytes`, `SimulatorRunner`, runner tests | Runner tests green with fake publisher |
| 3 | Project field, tab plumbing, simulator page list with start/stop and stats, delete old code | A hard-coded sample simulation can be started from the UI and appears in the Topic Viewer |
| 4 | Device and topic dialogs, `GeneratorEditor`, preview, template editor | Simulations can be created and edited fully in the UI and survive save/reopen |
| 5 | MQTT 5 properties UI, image generator (desktop), Clear retained, Subscribe in viewer, rate warnings, i18n, web check | Feature complete. Manual test on desktop and web |
| 6 | Recorded devices (D22–D25). Built in recorder phase 4, after the recorder's player exists | A recording runs as a device with 10 instances |

## 12. Known limitations

- **Background browser tabs (web):** browsers throttle timers in background tabs, often to one
  run per second or less. A web simulation slows down while its tab is hidden. The desktop app
  is not affected. The simulator page shows a hint on web.
- **Watching your own simulation:** subscribing to simulated topics in the Topic Viewer means
  every message also comes back to this client. At high rates, the viewer's message buffer and
  rendering become the bottleneck before the broker does. The rate warning (D11) mentions this.

## 13. Open questions

None at the moment. The former open questions are resolved as D8 to D13.
