# MQTT Recorder – Detailed Design

Status: **Draft**. Scope and the former open questions are decided (R1–R4, R16, R17, R23, R24); the other design decisions are proposed, see §2 · Branch: `mqtt5` · Last updated: 2026-10-24

Related: `simulator-design.md` (recorded devices, D22–D25) and `cli-design.md` (`record`, `replay`,
`recordings`, §7.1).

## 1. Purpose

The recorder captures every message of one or more topic filters from a broker into a
**recording**, plays it back at any speed, and helps analyze it. It lives in the existing (currently
hidden) **RECORDER** tab, runs headless from the CLI, and feeds the simulator: a recording can be
added to a simulation as a **recorded device** and played as N instances.

Typical uses: capture a customer's traffic to reproduce a bug at the desk, replay a production day
into a test system, turn one real machine into load-test traffic, and check in CI that a system
still produces the same output for the same input.

### Goals (v1)
- Record a single topic or a wildcard filter with all subtopics, or several filters with exclusions.
  Every message is stored with its payload, QoS, retain flag, MQTT 5 properties and receive time.
- A single recording is a device (R1). Its topics are the concrete topics seen during the capture.
- Play back a whole recording, one topic, or a selection of topics. Speed from 0.1× to 100× or
  as fast as allowed. Loop, play a time range, shorten idle gaps, rewrite topics, override retain
  and QoS. Pause, resume, seek and step.
- Add a recording to a simulation as a recorded device, with instance count and `{n}` topics.
- Start and stop recordings by condition (trigger with pre-roll, stop after duration, count, size
  or condition). A flight recorder keeps the last minutes in memory and saves on demand or on a
  condition. The topic viewer's buffer can be saved as a recording.
- Analyze a recording: per-topic statistics, a timeline, the existing viewers on recorded data,
  charts of numbers and JSON fields, a map for positions, inter-arrival histograms, gaps and
  duplicates, bookmarks.
- Edit without touching the original: trim, keep or delete topics, rename topics, merge, split and
  anonymize. Export to CSV and JSON lines, import from JSON lines, CSV and `mosquitto_sub` output.
- Compare two recordings (counts, payloads, timing) with a report and a CI exit code.
- Record, replay, inspect, export, import, edit and compare from the CLI.

### Non-goals (v1)
- Compressing payloads inside a recording (§16).
- Recording on the broker side or from several brokers into one recording (use merge).
- Editing single messages (payload editor). Edits work on topics, time ranges and rules.
- Live comparison while recording. Comparison works on finished recordings.
- Several recordings running at once in one app window (R8). The CLI can run any number.
- Request/response playback (reacting to incoming messages while replaying).

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| R1 | **A recording is a device.** One capture is one recording. Its topics are the concrete topics seen under its filters. Playback works on the whole recording or on single topics | User |
| R2 | **Recordings are files outside the project**, in a recordings library (desktop: a folder, web: IndexedDB). The project does not contain recordings | User |
| R3 | **All features listed in §1 are in v1**, delivered in the phases of §15 | User |
| R4 | **Recorded devices in the simulator:** a simulation device can replay a recording instead of generating payloads (`simulator-design.md` D22–D25) | User |
| R5 | Own binary format `.mqttrec`: append-only, framed records with CRC-32, a trailer that points to a footer with summary and seek index. JSON lines is the open exchange format (§4.2, §8.3) | Design |
| R6 | The recorder uses **its own MQTT connection**, built from the current project's broker settings, not the app's main connection (§5.1) | Design |
| R7 | In the app the recorder **reconnects automatically** and writes "connection lost" and "reconnected" markers. In the CLI, reconnect follows C4 (off unless `--reconnect`) | Design |
| R8 | One recording session at a time in the app (normal or flight recorder). Playback can run while recording | Design |
| R9 | A recording's messages are never changed in place. Only the mutable metadata in the footer (name, notes, bookmarks, topic colors) is rewritten. Every edit writes a new recording | Design |
| R10 | Playback in the app publishes on the **main connection**, to the broker of the open project. Playing to another broker means opening another project. The CLI has broker overrides | Design |
| R11 | Playback is scheduled from the recorded offsets against a monotonic clock, so it does not drift. When the player falls behind, it sends in order without waiting and reports the lag | Design |
| R12 | Speed 0.1×–100×, plus **Max**. Max sends as fast as the rate limit allows (D11, C3) and is only offered in the recorder tab and `replay`, not for recorded devices in a simulation | Design |
| R13 | Retained messages delivered on subscribe are flagged as the **retained snapshot**. Playback publishes the snapshot first, as retained (default), or skips it | Design |
| R14 | The analysis reuses the topic viewer widgets on recorded data through a `MessageSource` interface (§7.2) | Design |
| R15 | Summary statistics are computed while recording and stored in the footer, so the library and the overview open without reading all messages | Design |
| R16 | **A recording stops with its project.** Closing or switching the project, or closing the app, first warns that a recording is running. Confirming stops and saves the recording, cancelling keeps the project open and the recording running. The main connection's CONNECT button doesn't affect the recording (own connection, R6) | User |
| R17 | Default limits: a recording stops at **1 GB** (web 100 MB), the flight recorder holds at most **200 MB** in memory (web 50 MB). Both are settings | User |
| R18 | A recording shows a **REC indicator** in the app bar on every tab | Design |
| R19 | Recordings and the library are not part of `Project`, so recording never marks the project as changed. A recorded device in a simulation is configuration and is part of the project | Design |
| R20 | One small JSON path subset (`$.a.b[0].c`) and one condition syntax (§10) are shared by triggers, charts, compare, anonymize and export | Design |
| R21 | Shared subscriptions (`$share/…`) are not allowed as recorder filters. They would record only this client's share | Design |
| R22 | Overlapping filters are normalized before subscribing: a filter covered by another (`a/b/+` under `a/#`) is dropped with a hint, so no message is stored twice | Design |
| R23 | **All recorder features are free**, including compare, anonymize, the flight recorder and the CLI commands. None of them is a commercial add-on | User |
| R24 | The library folder defaults to `Documents\MQTT Studio\Recordings`, and recordings use the extension `.mqttrec` | User |

## 3. Current state (for reference)

- `main_appbar.dart` has the RECORDER menu item and tab (`visible: false`). There is no recorder
  code. The simulator design adds tab switching to `MessageViewerPage` (`IndexedStack`); the
  recorder becomes index 2.
- `MqttAdapter` is a GetIt singleton with one connection. Every received message is broadcast on
  `messageReceivedEvent`, and `MessageViewer` stores every message in `MQTTMessageBuffer` whatever
  subscription it came from. A recorder subscription on the main connection would therefore show
  up in the topic viewer, and unsubscribing it could remove a viewer subscription on the same
  filter. This is why the recorder has its own connection (R6).
- `MqttProtocolClient` (`mqtt3server`, `mqtt3browser`, MQTT 5 client) already delivers
  `ReceivedMqttMessage` with `qos`, `retain` and `MqttMessageProperties` (content type, response
  topic, correlation data, expiry, payload format, user properties, subscription identifiers), and
  publishes with properties. The recorder needs no new protocol code.
- `TopicSubscription` carries the MQTT 5 options `noLocal`, `retainAsPublished` and
  `retainHandling`, and has the filter matching (`isTopicSubscriptionMatch`, `topicFilterOf`).
- `MessageViewerViewmodel` reads everything from the `MessageViewer` singleton. The viewer widgets
  get the viewmodel through `ChangeNotifierProvider`, so they can show other data once the
  viewmodel reads from an interface (R14).
- `MessageViewer._messageReceived` writes topic colors into the current project. The recorded-data
  source must not do that.
- Available packages: `path_provider`, `file_picker`, `sembast_web` (with `idb_shim`, used for the
  web store), `fake_async` (dev, from the simulator).

## 4. Domain model

### 4.1 Overview

```
RecordingLibrary                              (desktop: folder, web: IndexedDB)
 └─ Recording  "Line 1 night shift"           one .mqttrec file = one device (R1)
     ├─ header   (immutable): id, startedAt, filters, broker, protocol, client id, app version
     ├─ topics   (discovered): "plant/line1/temp", "plant/line1/state", …
     ├─ messages: offset, topic, payload, qos, retain, retained-snapshot flag, MQTT 5 properties
     ├─ markers:  connection lost / reconnected, trigger fired, recovered
     └─ footer   (rewritable): name, notes, bookmarks, topic colors, summary stats, seek index

Project
 └─ simulation
     └─ devices: SimulatedDevice               kind generated (existing) or recorded (D22)
          └─ recorded: RecordedSource          recording id + topic selection + PlaybackOptions
```

The recorder tab and the simulator share one playback engine (`RecordingPlayer`, §6.1) and one
options model (`PlaybackOptions`, §6.2). The difference is ownership: playback in the recorder tab
is an ad-hoc run that is not saved; a recorded device is saved in the project and runs with the
rest of the simulation.

### 4.2 File format `.mqttrec` (R5)

All integers are little endian. A file is a header followed by framed records and, once the
recording is finalized, a footer and a trailer.

```
File     = Magic "MQREC" (5 bytes) | FormatVersion u8 (=1) | HeaderLen u32 | Header (UTF-8 JSON)
           | Record* | Trailer
Record   = Type u8 | BodyLen u32 | Body | Crc32 u32        (CRC-32 IEEE over Type, BodyLen and Body)
Trailer  = FooterPos u64 | Magic "MQEND" (5 bytes)         (last 13 bytes of a finalized file)
```

| Type | Record | Body |
|---|---|---|
| 1 | Topic | `topicIndex u32`, topic UTF-8. Written once, before the first message of the topic |
| 2 | Message | `offsetMicros u64`, `topicIndex u32`, `flags u8`, `payloadLen u32` (original), `storedLen u32`, payload bytes, then if `hasProperties`: `propsLen u32` + properties JSON |
| 3 | Marker | `offsetMicros u64`, JSON (`{"kind":"connectionLost"}`, `reconnected`, `triggerFired`, `recovered`) |
| 9 | Footer | JSON (§4.3). Written on finalize, rewritten when metadata changes |

Message `flags`: bits 0–1 QoS, bit 2 retain, bit 3 retained snapshot (R13), bit 4 has properties,
bit 5 truncated (payload longer than the max payload size, §5.2).

- **Time:** `offsetMicros` is measured with a `Stopwatch` from the recording start. The wall time
  of a message is `header.startedAt + offset`. Clock changes on the machine don't distort the
  recording.
- **Properties JSON:** `contentType`, `responseTopic`, `correlationData` (base64),
  `messageExpiryInterval`, `payloadFormatUtf8`, `userProperties` (list of `[key, value]`, order and
  duplicates kept). Subscription identifiers are not stored; they belong to the recorder's own
  subscription.
- **Writing:** records go through a write buffer that is flushed every second and on stop. A
  crash loses at most about one second.
- **Recovery:** a file without a valid trailer is recovered on open: records are read until the end
  of the file, a length that runs past the end, or a CRC mismatch. The file is truncated there, a
  `recovered` marker and a fresh footer are written, and the library shows "Recovered".
- **Footer rewrite (R9):** to change the name, notes, bookmarks or topic colors, the file is
  truncated at `FooterPos` and a new footer and trailer are written. Messages are never rewritten.
- **Why not SQLite or sembast:** sembast keeps the whole database in memory, which doesn't work for
  recordings of hundreds of MB. SQLite would add native libraries on Windows and a WASM build on
  the web. The framed format works the same on both platforms, needs no dependency, and appending
  is all recording does.

### 4.3 Header and footer

```dart
// Header: written once at start, never changed.
@JsonSerializable(explicitToJson: true)
class RecordingHeader {
  String id;                        // uuid, stable key (library, recorded devices, compare)
  DateTime startedAt;               // UTC
  List<RecorderFilter> filters;     // as subscribed, after normalization (R22)
  String broker;                    // host:port or URL
  MqttProtocolVersion protocol;
  String clientId;
  String? projectName;              // project it was recorded from; null for imports and the CLI with --host
  String appVersion;
  RecordingOrigin origin;           // live | flightRecorder | viewerBuffer | edit | import
  List<String> sourceRecordingIds;  // for edit and merge: the recordings it was made from
}

// Footer: rewritten on finalize and on metadata edits.
@JsonSerializable(explicitToJson: true)
class RecordingFooter {
  String name;
  String notes;
  Duration duration;                // offset of the last message or the stop time
  bool recovered;
  List<Bookmark> bookmarks;         // offset, label
  Map<String, TopicColor> topicColors;
  RecordingSummary summary;         // §7.1
  List<SeekEntry> seekIndex;        // every 1000th message: offsetMicros, file position
}

@JsonSerializable()
class RecorderFilter {
  String filter;                    // "plant/#"
  bool exclude;                     // exclusions are applied on the client, MQTT has none
  MqttQos qos;                      // default exactlyOnce, so the publisher's QoS is kept (§5.2)
}
```

### 4.4 Recording library (R2)

```dart
abstract class RecordingStorage {                       // one "file"
  Future<RecordingAppender> openAppend();
  Future<RecordingReader> openRead();
  Future<int> length();
  Future<void> truncate(int length);
}

class RecordingLibrary {                                // GetIt singleton
  Future<List<RecordingInfo>> list();                   // header + footer only, newest first
  Future<RecordingInfo?> findById(String id);
  Future<RecordingStorage> create(String suggestedName);
  Future<RecordingInfo> importFile(...);                // .mqttrec, .jsonl, .csv, mosquitto text (§8.3)
  Future<void> delete(String id);                       // after SrxDialog.yesNo
  Event<RecordingInfo> changedEvent;                    // new, finalized, renamed, deleted
}
```

- **Desktop:** the folder `Documents\MQTT Studio\Recordings` (from
  `getApplicationDocumentsDirectory()`; MSIX doesn't virtualize Documents, so the CLI and Explorer
  see the same files). The folder can be changed in the recorder tab; the choice is an app setting
  in `LocalStore`. File names are `<name> <yyyy-MM-dd HHmmss>.mqttrec`. Files the user copies into
  the folder show up after a refresh.
- **Web:** an IndexedDB object store (`idb_shim`) with the same bytes in 1 MB chunks, plus one
  record per recording for the header and footer so the list is cheap. Import and export go
  through `file_picker` and a browser download.
- Listing reads the header and, through the trailer, the footer of each file. It doesn't read the
  messages.

## 5. Recording

### 5.1 Recorder session and connection (R6, R7, R16)

```
RecorderService (GetIt singleton, lib/recorder/engine/recorder_service.dart)
 ├─ start(RecorderConfig) / stop() / bookmark(label) / saveFlightWindow()
 ├─ RecorderSession?                 the one active session (R8)
 │    ├─ connection: MqttAdapter     own instance, not the GetIt one; client id "<project id>-rec-<4 hex>"
 │    ├─ RecordingWriter             framing, write buffer, topic table, seek index, summary
 │    ├─ RingBuffer?                 pre-roll and flight recorder (§5.4, §5.5)
 │    └─ stats: received, stored, bytes, rate, state (waitingForTrigger, recording, reconnecting, saving)
 └─ events: stateChanged, statsChanged (throttled 500 ms)
```

- The session copies the project's `MqttSettings` (including the password) at start and stores
  the project name in the header. The connection is separate from the main one, so the CONNECT
  button doesn't affect the recording, but the recording belongs to the project (R16).
- On connection loss the session writes a `connectionLost` marker and reconnects with the CLI
  backoff (1 s, 2 s, 5 s, 10 s, then every 30 s). After `reconnected` it subscribes again. The REC
  indicator shows "Reconnecting". The analysis shows the gap between the markers.
- **Closing the project while recording (R16):** `ProjectManager` gets close guards
  (`addCloseGuard(Future<bool> Function())`), asked at the start of `closeProject`, before the
  unsaved-changes prompt. The recorder's guard shows `SrxDialog.yesNo` "A recording is running.
  Closing the project stops and saves it. Close anyway?". No cancels the close. The recording is
  only stopped and finalized on `projectClosedEvent`, so cancelling the unsaved-changes prompt
  afterwards also keeps it running. `openProject` must return early when `closeProject` returns
  false (today it ignores the result).
- **Closing the app while recording:** an `AppLifecycleListener.onExitRequested` handler shows
  "A recording is running. Closing MQTT Studio stops and saves it. Close anyway?". Yes finalizes
  the recording, then exits; no returns `AppExitResponse.cancel`. On the web, a `beforeunload`
  handler can only trigger the browser's own leave-page prompt; what was flushed so far is kept
  and recovered on the next start (§4.2).

### 5.2 What is captured

| Field | Source | Notes |
|---|---|---|
| Offset | `Stopwatch` at receive | Client-side receive time. There is no publish time in MQTT |
| Topic | `topicName` | Concrete topic, never a filter |
| Payload | raw bytes | Up to the max payload size (default unlimited). Longer payloads are stored cut with the `truncated` flag and the original length; playback skips them and counts them |
| QoS | delivered QoS | min(publish QoS, subscription QoS). Filters default to QoS 2 to keep the publisher's QoS |
| Retain | `retain` | See retained snapshot below |
| Properties | `MqttMessageProperties` | MQTT 5 only, without subscription identifiers |

**Retained snapshot (R13).** Retained messages that the broker sends because of the new
subscription are the state of the system at recording start. Detecting them:
- **MQTT 3.1.1:** the broker sets retain to 0 on live messages, so retain 1 always means snapshot.
  The publisher's retain flag of live messages is lost (§16).
- **MQTT 5:** the recorder subscribes with `retainAsPublished: true`, so live messages keep the
  publisher's retain flag. A message counts as snapshot when it has retain 1, is the first message
  of its topic, and arrives within 2 s of the subscribe acknowledgement.
- An option "Record retained snapshot" (on by default) can turn it off. It subscribes with
  `retainHandling: doNotSend` on MQTT 5, and drops retain-1 messages in the first 2 s on 3.1.1.

### 5.3 Filters

- One or more include filters, each with a QoS, and any number of exclude filters. A message is
  stored when it matches an include and no exclude (matching with `isTopicSubscriptionMatch`).
- Validation: the same topic filter rules as the add-topic dialog. `$share/…` is an error (R21).
  A filter covered by another include is dropped with a hint (R22, new function
  `TopicSubscription.filterCovers(a, b)`).
- `#` doesn't match topics starting with `$` (MQTT spec). The filter list shows a hint and
  `$SYS/#` can be added explicitly.
- When the main connection subscribes to the same topics, the user sees the messages in the topic
  viewer too. That is the normal way to watch a recording live.

### 5.4 Start triggers and stop conditions

```dart
@JsonSerializable(explicitToJson: true)
class RecorderConfig {
  String name;
  List<RecorderFilter> filters;
  RecorderMode mode;                 // normal | flightRecorder
  MessageCondition? startWhen;       // null = start right away
  Duration preRoll;                  // default 0, max 10 min: messages kept from before the trigger
  StopConditions stop;               // all optional, the first one reached stops the recording
  FlightRecorderOptions? flight;     // when mode == flightRecorder
  int? maxPayloadBytes;              // null = unlimited
  bool recordRetainedSnapshot;       // default true
}

class StopConditions {
  Duration? duration;                // counted from the trigger, not from pressing RECORD
  int? maxMessages;
  int? maxBytes;                     // default 1 GB (web 100 MB) (R17)
  MessageCondition? stopWhen;
  Duration postRoll;                 // for stopWhen: keep recording this long after it matches
}
```

- **Waiting for trigger:** after RECORD the session connects and subscribes, but stores messages
  only in the ring buffer (`preRoll` long). When `startWhen` matches (§10), the buffered messages
  are written first, then a `triggerFired` marker, then recording continues. Offsets count from
  the first written message, so pre-roll messages have positive offsets.
- The last used config is kept as an app setting, so the record dialog opens with it.

### 5.5 Flight recorder

```dart
class FlightRecorderOptions {
  Duration window;                   // default 10 min
  int maxMemoryBytes;                // default 200 MB (web 50 MB) (R17)
  MessageCondition? saveWhen;        // null = only the manual SAVE button
  Duration postRoll;                 // default 30 s
  int? maxSaves;                     // null = unlimited
}
```

- Messages stay in an in-memory ring buffer of `window`. When the memory limit is reached first,
  the oldest messages are dropped and the effective window shrinks. The REC indicator shows it,
  e.g. "FLIGHT 6m 12s of 10m".
- **SAVE** (or `saveWhen` matching) keeps capturing for `postRoll`, then writes the window and the
  post-roll to a new recording `<name> <timestamp>` with origin `flightRecorder`, and continues.
  Triggers that come during the post-roll belong to the same save.
- The ring buffer stores the same message objects the writer would write, so a save is one
  sequential write.

### 5.6 Save the topic viewer buffer

The topic viewer's command bar gets **Save as recording** (icon `save_alt`, tooltip "Save messages
as recording"). It writes what `MQTTMessageBuffer` holds right now, with origin `viewerBuffer`,
the current subscriptions as filters, their colors, and offsets from `receivedOn` (millisecond
precision). It works without the recorder running. The dialog notes that the buffer may not hold
everything that was received.

### 5.7 Lifecycle and errors

| Event | Behavior |
|---|---|
| RECORD with no project open | Disabled. Tooltip "Open a project to record from its broker" |
| Connect fails at start | Dialog `SrxDialog.error` with the socket error. Nothing is created |
| Subscribe of a filter fails | Snackbar with the reason. The other filters keep recording. All failed: stop with error |
| Connection lost | Marker, reconnect with backoff (R7), REC indicator "Reconnecting" |
| Stop condition reached | Finalize, snackbar "Recording saved: <name>" |
| Disk full or write error | Stop, finalize what was written (recovery if needed), error dialog |
| Project closed or switched | Warn first; on yes stop and finalize, on no keep the project open (R16, §5.1) |
| App closed | Warn first; on yes finalize and exit, on no keep the app open (§5.1) |
| App crash | Next start: the library recovers the file (§4.2) |

## 6. Playback

### 6.1 Player engine

```
RecordingPlayer (lib/recorder/engine/recording_player.dart, no Flutter dependency)
 ├─ RecordingPlayer(reader, PlaybackOptions, SimulatorPublisher, {instanceNumber, deviceName})
 ├─ start() / pause() / resume() / seek(offset) / step() / setSpeed(x) / stop()
 ├─ position, lag, sent, skipped (truncated), loopCount
 └─ events: positionChanged (throttled), finished, error
```

- It publishes through the simulator's `SimulatorPublisher`, so the main connection, the MQTT 5
  property path (`MqttAdapter.publish` with `MqttMessageProperties`) and the fake publisher in tests
  are shared with the simulator.
- **Scheduling (R11):** messages of the selected topics and range are read in order. Message *i*
  is due at `playStart + (offset_i' − rangeStart) / speed`, where `offset'` is the offset after gap
  compression. One one-shot `Timer` waits for the next due time; all messages that are due are
  sent in one go. Pause and speed changes re-base `playStart` at the current position. A
  `Stopwatch` provides the time, so the schedule doesn't depend on timer accuracy and doesn't drift.
- **Behind schedule:** messages are sent in order without waiting; `lag` (due time minus now) is
  shown. Nothing is dropped.
- **Max speed (R12):** a token bucket at the allowed rate (D11/C3 minus what else is running).
- **Reading:** the player reads ahead in blocks from the seek index position. For simulator
  devices with several instances, the selected range is loaded into memory once and shared when it
  is at most 64 MB. Otherwise each instance reads the file itself.

### 6.2 Playback options

```dart
@JsonSerializable(explicitToJson: true)
class PlaybackOptions {
  List<String> topics;               // selected recorded topics, empty = all
  double speed;                      // 0.1..100, default 1; 0 = Max (not for recorded devices, R12)
  bool loop;                         // default false
  Duration? rangeStart, rangeEnd;    // offsets in the recording, null = start/end
  Duration? compressGapsOver;        // gaps longer than this are shortened to it
  List<TopicRemap> remaps;           // applied in order, first match wins
  RetainedSnapshotMode snapshot;     // publish (default) | skip
  RetainOverride retain;             // asRecorded (default) | never | always
  MqttQos? qos;                      // null = as recorded
  bool republishProperties;          // default true; MQTT 5 properties as recorded
  InstanceStart instanceStart;       // staggered (default) | aligned | randomPosition (recorded devices only)
}

@JsonSerializable()
class TopicRemap {
  String from;                       // prefix of the recorded topic, "prod/"
  String to;                         // replacement, may contain {n}, {n:3}, {device}: "test/line{n}/"
}
```

- **Retained snapshot (R13):** with `publish`, the snapshot messages of the selected topics are
  sent first, retained, before message 1. With a range, the snapshot is the last retained message
  per topic before `rangeStart` (or the recorded snapshot), so the state at the range start is
  right. Looping doesn't send the snapshot again.
- **Remap:** the resolved topic must not contain `+` or `#` and must stay a valid topic (validation
  in the options editor, with a preview of the first three topics). Without a matching rule the
  topic stays as recorded.
- **MQTT 3.1.1 target:** properties can't be sent; the options editor shows a hint and the player
  drops them.
- **Instance start** (recorded devices with `instanceCount > 1`): `staggered` delays each
  instance by uniform(0, median interval of the selected topics), like the simulator's start
  stagger. `aligned` starts all at once. `randomPosition` starts each instance at a random offset
  in the range and needs `loop`.
- **Rate estimate:** selected messages in the range ÷ compressed range duration × speed ×
  instances. The peak (busiest second from the summary × speed × instances) is shown next to it.
  The estimate is checked against the same limits as the simulator (warning 100, refusal 1000
  msg/s; web 50), counting what the simulator is already running.

### 6.3 Playback in the recorder tab

- PLAY plays the selected recording with the options of its playback panel. The topic checkboxes
  in the overview table are `PlaybackOptions.topics`, so playing one topic means checking one.
  A range dragged in the timeline fills `rangeStart` and `rangeEnd`.
- Transport: play, pause, stop, step (when paused: send the next message only), seek by clicking
  the timeline, speed dropdown (0.1×, 0.25×, 0.5×, 1×, 2×, 5×, 10×, 100×, Max) and loop toggle.
  The playhead runs on the timeline.
- The playback options of each recording are remembered per recording (app setting by recording
  id), not in the recording file.
- **Feedback warning:** if a running recording's filters match the topics being played, starting
  playback warns "The running recording will record this playback" (yes/no). It can be intended,
  for example when recording a system's reaction.

### 6.4 Recorded devices in the simulator

See `simulator-design.md` D22–D25. In short: a device has `kind: recorded` and a
`RecordedSource` (recording id, file name as a fallback, `PlaybackOptions`). It uses the device's
instance count and first instance; with more than one instance a remap target must contain `{n}`
(same rule as simulator §6.2). One `RecordingPlayer` runs per instance. Start, stop, statistics
and errors work like generated devices. **ADD TO SIMULATION** in the recorder tab creates such a
device in the open project with the current playback options.

### 6.5 Lifecycle and errors

| Event | Behavior |
|---|---|
| PLAY while disconnected | Disabled. Tooltip "Connect to a broker first" |
| Disconnect of the main connection | Playback stops, position kept, snackbar (as simulator D8). The CLI follows C4 |
| End of range without loop | Stops, snackbar "Playback finished: <n> messages" |
| Recording file missing or unreadable | Error dialog. In the simulator: start error of that device, like a missing image folder |
| Publish throws | Treated like a disconnect |
| Recording deleted while playing | Deleting is disabled while it plays |

## 7. Analysis

### 7.1 Summary (R15)

Computed by the writer while recording and stored in the footer:

```
RecordingSummary
 ├─ messages, bytes, topics, duration, peakRatePerSecond, markers (counts by kind)
 └─ perTopic: Map<topic, TopicSummary>
      count, firstOffset, lastOffset, retainedCount, snapshotCount, truncatedCount,
      payloadBytes (min, max, total), payloadKinds (empty, number, text, json, image, binary),
      interval (min, max, sum) + IntervalHistogram (32 log-scale buckets, 1 ms … ~10 h),
      numeric (min, max, sum, count) when the payload is a number,
      jsonNumbers: up to 50 JSON paths with numeric values (min, max, sum, count),
      consecutiveDuplicates (same payload as the previous message of the topic),
      peakRatePerSecond
```

- Payload kinds use the detection of the detail view (number, `lat,lon`, JPG/PNG magic bytes,
  JSON, text), moved into `common/utils` so the recorder, the viewer and the simulator share it.
- The median interval comes from the histogram (approximate, within one bucket).
- A recording imported or edited gets its summary from one pass over the messages.

### 7.2 Recorded messages in the topic viewer widgets (R14)

```dart
abstract class MessageSource {
  MQTTMessageBuffer get messageBuffer;
  Event<ReceivedMqttMessage> get messageReceivedEvent;
  Event get messagesClearedEvent;
  Event get topicSubscriptionsChangedEvent;
  List<TopicSubscription> get topicSubscriptions;
  TopicColor getTopicColor(String topicName);
  bool get isLive;
}
```

- `MessageViewer` implements it (live). `RecordingMessageSource` loads the selected range of a
  recording into its own `MQTTMessageBuffer`, with `receivedOn = startedAt + offset` and the
  recording's topic colors. It never touches the project.
- `MessageViewerViewmodel` takes a `MessageSource` instead of reading the `MessageViewer`
  singleton. The MESSAGES tab of the recorder provides a viewmodel over the recording, so the
  grouped, tree and sequential viewers, the topic filter, the detail view, the payload viewer, the
  chart and the map all work on recorded data without changes.
- Offline (`isLive == false`): subscription chips show one chip per filter; tapping hides or shows
  its topics. Subscribe, play, pause and clear are disabled (not hidden). Re-publish in the detail
  view publishes on the main connection.
- At most 100,000 messages are loaded. For bigger ranges, the tab asks to pick a shorter range on
  the timeline.

### 7.3 Timeline

- One lane per topic (topic color, sorted like the overview table), with message density as bars.
  Markers (connection lost, trigger, recovered) and bookmarks are drawn across all lanes.
- Zoom with the mouse wheel, pan by dragging the axis, select a range by dragging in the lanes.
  The range is used by playback, the MESSAGES tab, CHARTS, export and trim.
- The density comes from one pass over the file in the background (`compute()`; on web this runs
  on the main thread in slices, §16), with a progress bar. Bookmarks can be added at the playhead
  or by right-click.

### 7.4 Charts

- Pick a topic and a value: the payload as a number, or a JSON path from the discovered ones
  (`jsonNumbers`) or typed in (R20). The existing `TopicChart` draws it with min, max and avg for
  the selected range.
- Inter-arrival histogram per topic from the summary histogram.
- Positions: payloads in `lat,lon` form or two JSON paths (lat, lon) show as a track on the
  existing `flutter_map` viewer.

### 7.5 Gaps and duplicates

- **Gaps:** an interval longer than `max(10 × median interval, 5 s)` (threshold editable) is a gap.
  Gaps are listed per topic with start and length and marked in the timeline. Gaps between
  `connectionLost` and `reconnected` are labeled as such.
- **Duplicates:** consecutive identical payloads per topic (from the summary), and repeats of the
  same topic and payload within 100 ms (QoS 1 redeliveries), listed per topic.

## 8. Editing, export and import

### 8.1 Edits (R9)

Every edit writes a new recording (origin `edit`, `sourceRecordingIds` set), named
`<name> (<edit>)`. The original stays until the user deletes it.

| Edit | Parameters |
|---|---|
| Trim | Range (from the timeline). Offsets are rebased to the range start. The retained snapshot becomes the last retained state per topic before the range start |
| Keep / delete topics | Topic selection (overview checkboxes) |
| Rename topics | `TopicRemap` rules (without placeholders) |
| Merge | Two or more recordings. Messages are interleaved by wall time (`startedAt + offset`), the start is the earliest |
| Split | At the playhead or at each bookmark (several files), or by topic (one file per topic) |
| Anonymize | Rules, see below |

**Anonymize** rules, applied in order to each message of matching topics:

```dart
class AnonymizeRule {
  String topicFilter;
  AnonymizeTarget target;   // jsonPath (with path) | wholePayload | topicLevel (with level index)
  AnonymizeAction action;   // hash | mask | fixed (with value) | remove | jitterNumber (± percent)
}
```

`hash` is a salted SHA-256 (`package:crypto`), cut to 12 hex chars. The salt is random per run, so
the same input gives the same output within one anonymized recording (relationships between
messages stay) but can't be matched against the original. Text payloads that aren't JSON support
`wholePayload` only. Rules can be saved to and loaded from a `.json` file, which the CLI uses too.
Properties (user property values, correlation data) are anonymized with `wholePayload` rules too,
selected by an option.

### 8.2 Metadata edits (in place)
Name, notes, bookmarks and topic colors are changed in the footer (§4.2). Deleting a recording asks
with `SrxDialog.yesNo` and removes the file.

### 8.3 Export and import

| Format | Export | Import |
|---|---|---|
| `.mqttrec` | Copy of the file | Copied into the library |
| JSON lines | Line 1: `{"format":"mqttstudio-recording","version":1, …header and footer metadata}`. Then one message per line: `{"t":<offset µs>,"time":"<ISO UTC>","topic":…,"qos":…,"retain":…,"snapshot":…,"payload":"<text>"}` or `"payloadBase64"` for non-UTF-8 payloads, `"properties":{…}` | Same format. Without the first line, the first message's `time` is the start |
| CSV | Columns `time,offset_ms,topic,qos,retain,payload,payload_encoding` (`text` or `base64`), optionally one column per chosen JSON path (flattened values). One file for all topics or one per topic | Same columns; the JSON path columns are ignored |
| `mosquitto_sub` output | | `-F "%U %t %p"` lines (Unix time with fractions, topic, payload) or `-v` lines (topic, payload; no time, the user picks a fixed interval). Single-line payloads only |

Export works on the selected topics and range. Import runs in the background with a progress bar
and computes the summary (§7.1).

## 9. Compare

```dart
class CompareOptions {
  List<TopicRemap> remaps;      // maps topics of B onto topics of A, e.g. "test/" → "prod/"
  bool counts;                  // same topic set, count per topic within countTolerance
  double countTolerance;        // percent, default 0
  bool payloads;                // per topic, the payload sequence in order is equal
  List<String> ignorePaths;     // JSON paths left out of the payload comparison, e.g. "$.ts"
  double numberTolerance;       // absolute, for JSON numbers and number payloads, default 0
  bool timing;                  // per topic, median interval within timingTolerance
  double timingTolerance;       // percent, default 10
  Duration? rangeA, rangeB;     // optional ranges
}
```

- Result per topic: `equal`, `different`, `onlyInA`, `onlyInB`, with counts, median intervals and
  the first difference (message index in both, both payloads, the JSON path that differs).
- JSON payloads are compared structurally (key order doesn't matter). Other payloads by bytes.
- The COMPARE tab shows the result table; a click on a difference opens both messages side by
  side. The CLI writes the same result as JSON (`--report`) and ends with exit code 8 when
  anything differs.
- Typical CI flow: `replay input.mqttrec` into the system under test while
  `record -t "out/#"` captures its output, then
  `recordings compare expected-output.mqttrec actual.mqttrec --payloads --ignore '$.ts'`.

## 10. JSON paths and conditions (R20)

**JSON path subset:** `$`, `.name`, `['name with spaces']`, `[index]`. No wildcards, filters or
recursive descent. One parser in `lib/common/utils/json_path.dart`, used by charts, conditions,
compare, anonymize and CSV export.

**Conditions** (`startWhen`, `stopWhen`, `saveWhen`):

```dart
class MessageCondition {
  String topicFilter;           // which messages are checked
  String? jsonPath;             // null = the whole payload
  ConditionOp? op;              // null = any message on the filter matches
  String? value;
}
enum ConditionOp { equals, notEquals, greater, greaterOrEqual, less, lessOrEqual, contains, regex }
```

The text form (CLI and an "advanced" field in the dialog) is
`<topic filter> [<json path>] [<op> <value>]`, with ops `== != > >= < <= contains ~`:

```
plant/line1/alarm                      any message on the topic
plant/+/temp > 80                      number payload above 80
plant/line1/state $.status == "error"  JSON field equals a string
plant/line1/log ~ /timeout|refused/    payload matches a regular expression
```

Numbers compare numerically when both sides parse as numbers, otherwise as text. An invalid
condition is a validation error in the dialog (exit code 2 in the CLI).

## 11. UI

### 11.1 Tab plumbing and REC indicator
- Show the RECORDER tab (`main_appbar.dart`) as `IndexedStack` index 2 (see simulator §8.1).
- **REC indicator (R18):** in the app bar left of the CONNECT button, only while a session runs:
  a red dot (`fiber_manual_record`, new color `recordingColor` in `CustomColors`) and
  "REC 00:12:31 · 12,340 · 4.2 MB", or "WAITING FOR TRIGGER", "RECONNECTING", "FLIGHT 6m of 10m".
  Clicking it opens the recorder tab. New design system token `recording` and component
  "RecIndicator" (add to the design system when built).

### 11.2 Recorder page

```
┌─────────────────────┬──────────────────────────────────────────────────────────────────────────┐
│ Recordings       ⟳  │ [● RECORD] [■ STOP] [🔖] [SAVE] │ [▶][⏸][⏹][⏭] [1× ▾] [⟲] │ [ADD TO SIMULATION] [⋮] │
│ ● Line 1 (live)     │──────────────────────────────────────────────────────────────────────────│
│   Line 1 night      │ Line 1 night shift   23.10.2026 22:00 · 8h 00m · 1,204,332 msgs · 412 MB  │
│   23.10. 8h 412 MB  │ broker.local:1883 · MQTT 5 · plant/line1/# (excl. plant/line1/debug/#)     │
│   Weather station   │ OVERVIEW   TIMELINE   MESSAGES   CHARTS   COMPARE                         │
│   22.10. 15m 2 MB   │ ┌───┬────────────────────────┬────────┬───────┬──────────────┬─────┬────┐ │
│   Line 1 (trimmed)  │ │ ☑ │ topic                  │ msgs   │ msg/s │ interval     │ size│gaps│ │
│                     │ │ ☑ │ ● plant/line1/temp     │ 28,800 │ 1.0   │ 1.0 s (±0.1) │ 4 B │ 0  │ │
│                     │ │ ☐ │ ● plant/line1/state    │    312 │ 0.01  │ 92 s         │ 85 B│ 2  │ │
│                     │ │ ☑ │ ● plant/line1/camera   │    960 │ 0.03  │ 30 s         │212KB│ 0  │ │
│ [IMPORT] [FOLDER]   │ └───┴────────────────────────┴────────┴───────┴──────────────┴─────┴────┘ │
└─────────────────────┴──────────────────────────────────────────────────────────────────────────┘
```

- **Library list** (left, 300 px, `divider` border): name, date, duration, size; the live session
  on top with the red dot; "Recovered" tag. Context menu: rename, notes, export, duplicate,
  delete. Below: IMPORT and FOLDER (open in Explorer; desktop only, disabled on web).
- **Command bar** (same style as `TopicsViewCommandBar`, groups with `VerticalDivider`s):
  - Record group: RECORD opens the record dialog, STOP, bookmark (`bookmark_add`), SAVE (flight
    recorder only). RECORD is disabled without a project and while a session runs (R8).
  - Playback group: play (green), pause (blue), stop, step (`skip_next`), speed dropdown, loop
    (`repeat`, toggle). The playback options editor opens from `tune`.
  - ADD TO SIMULATION (`TextButton`, disabled without a project) and ⋮ (edit, export, compare).
- **OVERVIEW:** metadata, notes, then the per-topic table (§7.1) with checkboxes for the playback
  selection, sortable columns and the topic chip in its color. Markers and bookmarks below.
- **TIMELINE**, **MESSAGES**, **CHARTS**, **COMPARE:** §7.2–§7.5 and §9.
- Empty state (no recordings): watermark "Recordings" in the list, like the subscription panel.

### 11.3 Record dialog

960 px wide with three tabs, like the simulator's topic dialog:
- **FILTERS:** name, list of filters (filter, QoS, include/exclude, ✕), "+ Filter", normalization
  and `$SYS` hints. The first filter is prefilled from the selected topic viewer subscription, if
  any.
- **START AND STOP:** mode (normal / flight recorder); start right away or when a condition
  matches, pre-roll; stop by duration, count, size, condition, post-roll. Flight recorder: window,
  memory limit, save condition, post-roll, max saves.
- **OPTIONS:** max payload size, record retained snapshot, the broker that will be used (from the
  project, read-only).
- Actions: Cancel, RECORD. Esc cancels, Enter starts.

### 11.4 Other dialogs
- **Playback options** (480 px): `PlaybackOptionsEditor` widget, shared with the simulator's
  recorded device dialog: speed, loop, range, gap compression, remaps with preview, snapshot,
  retain, QoS, properties, instance start (simulator only).
- **Edit** dialogs for trim (range fields), topics, rename, merge (recording picker), split, and
  anonymize (rule list, load/save rules).
- **Export** (format, topics, range, JSON path columns) and **Import** (file, format, interval for
  `-v` input).
- **Compare** options (§9) in the COMPARE tab itself, with a recording picker for B.

## 12. CLI

Details in `cli-design.md` §7.1. Summary:

```
mqttstudio record  -p <project> -t <filter>… [-x <exclude>…] [--name] [--out <file>]
                   [--duration] [--max-messages] [--max-size] [--start-when <cond>] [--pre-roll]
                   [--stop-when <cond>] [--post-roll] [--flight <window>] [--save-when <cond>]
                   [--max-payload-size] [--no-retained-snapshot] [--reconnect] [broker overrides]
mqttstudio replay  <recording> [-p <project> | --host …] [-t <topic>…] [--speed <x|max>] [--loop]
                   [--from] [--to] [--compress-gaps] [--remap <from>=<to>]… [--instances <n>]
                   [--snapshot publish|skip] [--retain as-recorded|never|always] [--qos] [--duration]
                   [--max-rate] [--reconnect] [broker overrides]
mqttstudio recordings list | show <recording> | export | import | edit | compare
```

A `<recording>` is a file path, or a name or id from the library. `simulate` runs recorded devices
like any other device. The CLI still never writes to `LocalStore` (CLI §3.1); recordings are files.

## 13. Files

New:
```
lib/recorder/model/recording_header.dart          RecordingHeader, RecordingFooter, RecorderFilter, Bookmark, SeekEntry (+ .g.dart)
lib/recorder/model/recording_summary.dart         RecordingSummary, TopicSummary, IntervalHistogram (+ .g.dart)
lib/recorder/model/recorder_config.dart           RecorderConfig, StopConditions, FlightRecorderOptions (+ .g.dart)
lib/recorder/model/playback_options.dart          PlaybackOptions, TopicRemap, enums (+ .g.dart)
lib/recorder/model/compare_options.dart           CompareOptions, CompareResult (+ .g.dart)
lib/recorder/model/anonymize_rule.dart            AnonymizeRule (+ .g.dart)
lib/recorder/format/record_codec.dart             framing, CRC-32, message encode/decode
lib/recorder/format/recording_writer.dart         topic table, write buffer, summary, seek index, finalize
lib/recorder/format/recording_reader.dart         sequential and seek reads, recovery
lib/recorder/storage/recording_storage.dart       interface + file implementation (desktop)
lib/recorder/storage/recording_storage_web.dart   IndexedDB implementation (conditional import)
lib/recorder/storage/recording_library.dart       RecordingLibrary
lib/recorder/engine/recorder_service.dart         RecorderService, RecorderSession
lib/recorder/engine/ring_buffer.dart              pre-roll and flight recorder buffer
lib/recorder/engine/recording_player.dart         RecordingPlayer, scheduling, token bucket
lib/recorder/engine/message_condition.dart        MessageCondition, text parser, evaluation
lib/recorder/tools/recording_editor.dart          trim, topics, rename, merge, split, anonymize
lib/recorder/tools/recording_exporter.dart        CSV, JSON lines
lib/recorder/tools/recording_importer.dart        JSON lines, CSV, mosquitto_sub
lib/recorder/tools/recording_comparer.dart        compare
lib/recorder/tools/timeline_scanner.dart          density per topic, gaps, duplicates
lib/recorder/recording_message_source.dart        MessageSource over a recording
lib/recorder/recorder_page.dart (+ recorder_viewmodel.dart)
lib/recorder/widgets/recording_list.dart
lib/recorder/widgets/recorder_command_bar.dart
lib/recorder/widgets/recording_overview.dart
lib/recorder/widgets/recording_timeline.dart
lib/recorder/widgets/recording_charts.dart
lib/recorder/widgets/recording_compare.dart
lib/recorder/widgets/playback_options_editor.dart
lib/recorder/widgets/rec_indicator.dart
lib/recorder/record_dialog.dart (+ viewmodel)
lib/recorder/playback_options_dialog.dart (+ viewmodel)
lib/recorder/edit_dialogs.dart (+ viewmodels), export_dialog.dart, import_dialog.dart (+ viewmodels)
lib/common/utils/json_path.dart
lib/common/utils/payload_kind.dart                payload detection moved from message_detail_view.dart
lib/common/message_source.dart                    MessageSource interface
lib/cli/commands/record_command.dart, replay_command.dart, recordings_command.dart (+ subcommands)
test/recorder/record_codec_test.dart
test/recorder/recording_writer_reader_test.dart
test/recorder/recording_recovery_test.dart
test/recorder/recorder_session_test.dart
test/recorder/recording_player_test.dart
test/recorder/message_condition_test.dart
test/recorder/recording_editor_test.dart
test/recorder/export_import_test.dart
test/recorder/recording_comparer_test.dart
test/common/json_path_test.dart
```

Changed:
```
lib/message_viewer/message_viewer.dart              implements MessageSource
lib/message_viewer/message_viewer_viewmodel.dart    reads from a MessageSource
lib/message_viewer/widgets/topics_viewer_command_bar.dart   "Save as recording"
lib/message_viewer/widgets/message_detail_view.dart uses payload_kind.dart
lib/model/topic_subscription.dart                   filterCovers(a, b)
lib/simulator/…                                     recorded devices (simulator-design.md D22–D25)
lib/common/widgets/main_appbar.dart                 RECORDER tab, REC indicator
lib/message_viewer/message_viewer_page.dart         IndexedStack index 2
lib/custom_theme.dart                               CustomColors.recordingColor
lib/main.dart                                       register RecordingLibrary, RecorderService; AppLifecycleListener exit warning
lib/project/project_manager.dart                    close guards; openProject respects a cancelled close
lib/cli/cli_app.dart                                register record, replay, recordings
assets/i18n/en.json                                 recorder.* strings
pubspec.yaml                                        crypto (anonymize) and idb_shim (web store) as direct dependencies; both are only transitive today
```

## 14. Testing

- **Format:** round trip of every record type and flag, binary and empty payloads, all MQTT 5
  properties (duplicate user property keys, correlation data), 64-bit offsets. CRC mismatch,
  truncated last record and missing trailer are recovered to the last good record. Footer rewrite
  keeps all messages.
- **Library:** listing reads only header and footer (counted reads on a fake storage), recovery on
  list, import of each format, delete.
- **Recorder session** (fake connection, `fake_async`): include/exclude matching, filter
  normalization, retained snapshot on 3.1.1 and MQTT 5, max payload truncation, every stop
  condition, start trigger with pre-roll, stop condition with post-roll, flight recorder window and
  memory limit, several saves, reconnect markers. Project close: the guard asks, no keeps the
  project open and the recording running, yes stops and finalizes it; cancelling the later
  unsaved-changes prompt also keeps it running. App exit with a running recording.
- **Player** (fake publisher, `fake_async`): due times at 0.1×, 1× and 100× over a long recording
  without drift; lag when the publisher is slow; Max limited by the token bucket; range with
  snapshot at range start; loop without a second snapshot; gap compression; remap with `{n}`;
  retain and QoS overrides; pause, resume, seek, step, speed change while playing; truncated
  messages skipped and counted.
- **Summary:** counts, intervals, histogram median, payload kinds, JSON number paths, duplicates,
  peak rate against a brute-force computation on generated data.
- **Conditions and JSON path:** parser accepts and rejects the documented forms, numeric vs text
  comparison, regex.
- **Editor:** trim rebases offsets and the snapshot; merge orders by wall time; split by bookmarks
  and topics; anonymize hashes consistently within a run and differently across runs.
- **Export/import:** JSON lines and CSV round trip (binary via base64), `mosquitto_sub` both forms.
- **Compare:** equal, count tolerance, ignored paths, number tolerance, timing tolerance, only-in-A
  and only-in-B, remap of B onto A.
- **MessageSource:** the viewer viewmodel works on `MessageViewer` and `RecordingMessageSource`;
  the recording source doesn't change the project (`hasProjectChanged()` stays false).
- **Simulator:** see simulator §10 (recorded devices).
- Manual: record from a local Mosquitto with the simulator feeding it, replay at several speeds
  into the topic viewer, compare a replayed recording with its source, desktop and web, app crash
  during recording and recovery.

## 15. Implementation phases

| Phase | Content | Done when |
|---|---|---|
| 1 | Format, writer, reader, recovery, desktop storage, library, summary | Format and library tests green, no UI |
| 2 | `RecorderService` with own connection, filters, stop conditions, record dialog (FILTERS, simple stop), recorder page with library list and OVERVIEW, REC indicator, close prompt | A recording can be made, stopped, listed and inspected in the app |
| 3 | `RecordingPlayer`, playback options editor, transport, speed, loop, range, gaps, remap, snapshot | A recording plays into the topic viewer at any speed |
| 4 | Recorded devices in the simulator (simulator D22–D25) | A recording runs as a device with 10 instances from the simulator page and `simulate` |
| 5 | `MessageSource` refactor, MESSAGES, TIMELINE, CHARTS, gaps and duplicates, bookmarks | Analysis tabs work on a large recording |
| 6 | Triggers, pre-roll, post-roll, flight recorder, save viewer buffer | All recording modes work |
| 7 | Edits, anonymize, export, import | Each edit and format round trip works from the UI |
| 8 | Compare (tab and comparer) | Compare finds the seeded differences in test recordings |
| 9 | CLI `record`, `replay`, `recordings …` (needs the CLI framework of `cli-design.md`) | CI flow of §9 runs from a script with the documented exit codes |
| 10 | Web storage (IndexedDB), limits, web hints, i18n, design system update | Manual test on desktop and web |

## 16. Known limitations

- **Receive time, not publish time:** MQTT carries no publish time. Offsets include broker and
  network delay, and messages that arrive in one TCP read get almost the same offset.
- **Timer precision on playback:** Windows timers have a resolution of a few milliseconds, so
  messages closer than that are sent in bursts. The schedule itself doesn't drift (R11).
- **MQTT 3.1.1 loses retain on live messages:** the broker clears it (§5.2), so a replay of a 3.1.1
  recording republishes only the snapshot as retained, unless the retain override is `always`.
- **QoS 0 loss:** messages the broker drops for a QoS 0 subscription are not in the recording.
- **No compression:** JSON-heavy recordings are large. Zipping the exported file helps for
  sharing; compression inside the format can come with a format version 2.
- **Web:** background tabs throttle timers (playback slows down, as simulator §12), analysis
  passes run on the main thread, and storage is limited to 100 MB per recording.
- **Offline viewer:** at most 100,000 messages at once (§7.2).
- **Single session:** one recording at a time in the app (R8). Run more with the CLI.

## 17. Open questions

None at the moment. The former open questions are resolved as R23 (all features free), R17
(limits), R16 (the recording stops with its project, after a warning) and R24 (library folder and
file extension).
