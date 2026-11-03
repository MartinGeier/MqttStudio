# Code review of MQTT Studio, 2026-11-03

Six read-only reviewers each took one area of `src/mqttstudio_client/lib` (about 54,000 lines, not counting `*.g.dart`). Nothing was edited or run.
Paths below are relative to `src/mqttstudio_client/lib/`.

## Status: fixed

Every finding below is fixed on `mqtt5`, each with tests. The full suite passes (937 tests).

| Area | Commit |
|---|---|
| Topic viewer buffer | `a9a1eb2` |
| Core: `SideConnection` | `286b373` |
| Core: projects | `b2bc7ea` |
| Documentation | `1684310` |
| Simulator | `cf2568a` |
| Topic viewer, payload decoders | `cac2b93` |
| Protocols | `97c2e82` |
| Recorder, and recorded devices in CLI `--reconnect` | `3774027` |
| Fitting the areas together | `69c0d38` |

Three findings were partly wrong:
- **CLEAR keeping the selected message:** the CLEAR button already cleared it. The viewmodel now clears it too, which covers clearing a recording.
- **`RecordedDeviceViewmodel` notifying after it was closed:** `SrxChangeNotifier` already ignores that. Only the uncancelled form subscriptions and the late library list were real.
- **Grouped view changing the shown list:** the incremental grouping was removed in `a9a1eb2`.

Behaviour that changed on purpose:
- **Recorded playback during an outage:** a recording's playback keeps its schedule and skips messages while disconnected, instead of stopping.
- **New projects:** a new project is saved as soon as it is opened.
- **Project names:** the name of another saved project is rejected.
- **Wide placeholders:** `{n:width}` allows at most 12 digits.

**✔ = I checked it against the code myself.** The other findings come from the reviewers' reading, and each one cites a line. Severity: H high, M medium, L low.

## Patterns that recur across areas

1. **Closing or stopping while a connection is still being made.** The object is stored only after `await connect(...)`, so a stop or close in the meantime finds nothing to close, or crashes. Afterwards, the connect completes and the object comes back to life.
   - Affected: `RecorderService`, `SysMonitor`, `RetainedScanner`, `DiscoveryService`, `CheckService`, `SideConnection._reconnect` and `SimulatorRunner.startRecorded`.
   - Fix: one fix in `SideConnection` would cover most of them: a connect that can be cancelled, plus a `_closed` check that disconnects the client it just built.
2. **Only `FormatException` is caught around decoders**, but the decoders can also throw `RangeError`, `ArgumentError`, `UnsupportedError` or `TypeError`.
   - Affected: `payload_decoder.dart`, the Sparkplug reader and profile, the AsyncAPI importer and the recording library listing.
   - Effect: in the topic viewer, the error is thrown inside `build` on every rebuild.
3. **Unbounded growth over long sessions.**
   - The topic viewer buffer.
   - The VDA 5050 checker state.
   - On the web, IndexedDB recordings stay cached in memory.

## Topic viewer (`message_viewer/`, payload decoders)

| | Sev | Where | Defect |
|---|---|---|---|
| ✔ | H | `message_buffer.dart:17` | The buffer never removes old messages, and `insert(0, …)` costs O(n) per message. Statistics and the chart rescan the whole buffer on each rebuild. Memory and CPU grow without limit. |
| ✔ | M | `message_viewer_viewmodel.dart:847` | The refresh throttle drops the last update of a burst. If 3 messages arrive within 500 ms and then nothing more, the Grouped and Sequential views show only the first one. |
| | M | `retained_scanner.dart:54,71` | If the connection drops during a scan, `unSubscribeFromTopic` throws before the completer completes, so the scan stays busy forever. |
| | M | `common/utils/payload_decoder.dart:44,309,453,495` | CBOR/MessagePack input can throw errors that are not a `FormatException`: NaN or huge timestamps, and a uint64 length that wraps to a negative number. The detail view then breaks for the session. |
| | M | `message_viewer.dart:151` | After a reconnect, the topics are subscribed again even while everything is paused. |
| | M | `tree_messages_viewer.dart:64`, `message_buffer.dart:203` | A topic with a leading `/` gets the wrong tree path, e.g. `a/b` instead of `/a/b`. Copying the topic, subscribing to its branch and filtering then act on the wrong topic. |
| | L | `retained_scanner.dart:30` | Closing the dialog while it is still connecting leaks the connection. |
| | L | `message_buffer.dart:161,174` | Hourly groups use UTC boundaries, which is wrong in time zones with a half-hour offset. |
| | L | `message_buffer.dart:140-149` | Unfiltered messages are added to the list currently shown even while a filter is active. If one group holds more than 2000 messages, that only group is removed. |
| | L | `message_viewer_viewmodel.dart:874` | CLEAR keeps the selected message. |
| | L | `message_filter.dart:44` | A `+` in a plain topic search (e.g. `c++`) forces wildcard mode, and the search fails. |
| | L | `topics_viewer_command_bar.dart:27` | The filter's `TextEditingController` is never disposed. |

## Core: MQTT, projects, common, CLI

| | Sev | Where | Defect |
|---|---|---|---|
| ✔ | H | `common/localstore.dart:17`, `project_edit_viewmodel.dart:144` | Projects are stored under their name, and the dialog renames the project in place. Renaming A to B keeps A with its old settings. Renaming to the name of an existing project C silently overwrites C. |
| | M | `project/project_manager.dart:48-53` | A new project counts as unchanged right after it is created. Closing it neither prompts nor saves, so the project is lost. |
| ✔ | M | `mqtt/sys_monitor.dart:62-66` | If the $SYS statistics dialog is closed while it is still connecting, its connection stays open and subscribed to `$SYS/#`. |
| | M | `mqtt/side_connection.dart:142` | Closing during a reconnect leaves the newly built connection open. |
| | M | `mqtt_connection_viewmodel.dart:22` + `project_manager.dart:79` | Closing the project while a connect is still running leaves the app connected with no project open, or shows a spurious error. |
| | L | `project/project_manager.dart:80,83` | `projectClosedEvent` is broadcast twice, the first time while `currentProject` is still set. |
| | L | `mqtt/mqtt_adapter.dart:44` | `TlsContext.loadBundledCa()` is not awaited, so the first TLS connect (especially in the CLI) can run without the bundled CA. |
| | L | `mqtt/mqtt_adapter.dart:140` | One subscriber that throws stops the rest of that batch of messages from being delivered to anyone. |

## Recorder

| | Sev | Where | Defect |
|---|---|---|---|
| ✔ | H | `recorder/engine/recorder_service.dart:370` | STOP while CONNECTING hits `_connection!` while it is still null and throws. `start()` then resumes and keeps recording after the user stopped, or after the project closed. |
| ✔ | H | `recorder/engine/recording_player.dart:333-339` | A loop restarts right after the last message, not at the end of the range. A one-message recording republishes with no delay. A recording that holds only the retained snapshot loops forever in microtasks, which hangs the tab on the web. |
| ✔ | H (web) | `recorder/storage/indexed_db_recording_store.dart:101,118` | After one failed IndexedDB write (e.g. the quota is exceeded), the `_writes` chain stays failed, so every later write and delete fails until the page is reloaded. |
| | M | `recording_player.dart:260`, `:177-185` | Pausing or changing the speed during a read drops a message. `setSpeed` can run two reads on one cursor at once, which skips a record. |
| | M | `recorder_service.dart:458` | Retained messages the broker resends after a reconnect are recorded as new live messages. |
| | M | `recording_library.dart:217` | A quiet CLI recording is treated as crashed after 15 s and "recovered" (truncated) while the CLI is still writing to it. |
| | M (web) | `indexed_db_recording_store.dart:330` | Listing the library loads every recording into memory and keeps it there. |
| | L | `recording_library.dart:188` | Importing an unfinished `.mqttrec` always fails instead of recovering it. |
| | L | `recording_library.dart:208` | A file with bad header JSON throws a `TypeError`, which breaks the whole library list. |
| | L | `recording_writer.dart:285` | After a failed append, `_length` is wrong, so the trailer points past the footer. |

## Simulator

| | Sev | Where | Defect |
|---|---|---|---|
| ✔ | H | `simulator/engine/simulator_runner.dart:376-431` | A recorded device whose recording is still loading starts anyway after Stop all, a disconnect or a project close, and publishes the old project's recording. |
| | M | `simulator/sparkplug/simulated_host.dart:143` | The simulated primary host never reconnects. After it drops, every edge node waits for it forever while still shown as running. |
| | M | `simulator_runner.dart:422` + `recording_player.dart:303` | In CLI `--reconnect` mode, recorded devices stop for good at the first outage, and the run never finishes. |
| | M | `simulator/simulator.dart:182-199,263` | Editing a running device or topic restarts it without the rate check, e.g. at 20,000 msg/s. |
| | L-M | `simulation_rules.dart:359` | Sparkplug metric generators are not validated. A bad generator in an imported project aborts Start all. |
| | L-M | `simulator/simulator.dart:92` | `refreshRecordings` loops over the live device list across awaits, so it can throw `ConcurrentModificationError`. |
| | L | `vda5050/simulated_fleet.dart:168` | Robots count messages that were never sent while disconnected. |
| | L | `simulator_runner.dart:443` | A file handle leaks when a recording fails to open. |
| | L | `recorded_device_viewmodel.dart:43,55` | The form subscription is never cancelled, and the dialog is notified after it was closed. |
| | L | `simulator/engine/placeholders.dart:10` | `{n:width}` has no upper bound: a huge width throws or builds strings of 100 MB. |
| | L | `simulator_runner.dart:592` | A device with `instanceCount: 0` runs and never publishes; the CLI rejects the same device. |

## Protocols (VDA 5050, Sparkplug)

| | Sev | Where | Defect |
|---|---|---|---|
| ✔ | H | `protocol/sparkplug/sparkplug_payload.dart:428`, `sparkplug_profile.dart:106` | A timestamp in ns (or any value out of range) throws a `RangeError` that is not a `FormatException`. The interpretation is never cached, so the error is thrown again on every rebuild of every view. |
| | H (web) | `sparkplug_payload.dart:236,193` | 64-bit varints lose precision as JS doubles: Int64 −5 decodes as 0. |
| | M | `sparkplug_payload.dart:271` | A huge length overflows `position + length` on native, which gives a `RangeError` instead of a `FormatException`. |
| ✔ | M | `sparkplug_rules.dart:111-120`, `sparkplug_state.dart:222` | An NDEATH from an older session (stale bdSeq) still marks the live node offline. Every later DATA message then gets an `afterDeath` error. |
| | M | `sparkplug_payload.dart:406` | `retype` misses BigInt values and the web: negative Int32 values show as 18446744073709551611. |
| | M | `protocol/widgets/fleet_canvas.dart:102,307`, `fleet_viewer.dart:208` | A NaN or huge coordinate makes the grid loop never end (the UI hangs), or makes `floor()`/`round()` throw. |
| | M-L | `vda5050_rules.dart:189` | The header id rule ignores `snapshot`, which gives false `headerIdOutOfOrder` findings after a reconnect. |
| | L | `vda5050_rules.dart:50` | The checker's maps are never pruned. |
| | L | `sparkplug_payload.dart:382,567` | Templates and property sets are read recursively with no depth limit, so a crafted payload overflows the stack. |
| | L | `sparkplug_state.dart:207` | Commands update the state; a DCMD to an unknown device creates a phantom device. |
| | L | `sparkplug_profile.dart:434` | An empty DataSet fails the `DataTable` assertion in debug builds. |
| | L | `vda5050_rules.dart:114` | False `responseWithoutRequest` warnings for requests made before the check started. |

## Documentation

| | Sev | Where | Defect |
|---|---|---|---|
| ✔ | H | `documentation/documentation_service.dart:37` | The path `''` of a topic that starts with `/` selects every node. Delete removes the whole documentation, and Move garbles every path. |
| ✔ | H | `engine/documentation_analyzer.dart:40,202` | `double.tryParse("NaN")` puts NaN into the observed values. Encoding the project (`model/project.dart:36`) and the AsyncAPI export then throw. |
| | M | `discovery_service.dart:216`, `check_service.dart:105` | Stopping while still connecting breaks the service: discovery throws at `_analyzer!` on every message, and the check ignores the stop. |
| | M | `export/asyncapi_importer.dart:165,177,221` | Extension values of the wrong type throw a `TypeError`/`ArgumentError`. Only `FormatException` is caught. |
| | M | `asyncapi_importer.dart:66`, `import_merge.dart:312` | Two AsyncAPI 3 channels with the same address produce duplicate nodes. |
| | M-L | `conformance_checker.dart:379` | The check ignores discovery's exclude filters, so excluded topics show up as "undocumented". |
| | L-M | `engine/schema_inferrer.dart:38` | Fields inside arrays get a presence above 100 %. |
| | L | `export/schema_json.dart:17,156` | Boolean enums are exported as strings. |
| | L | `engine/discovery_merger.dart:69` | Renaming template parameters one after another can merge two parameters into one and silently drop the template. |
| | L | `export/yaml_writer.dart:89,163` | Trailing blank lines are lost, and keys such as `on`, `yes` and `null` are left unquoted. |
| | L | `export/csv_exporter.dart:77` | CSV exports allow formula injection (`=`, `+`, `-`, `@`). |
| | L | `export/doc_blocks.dart:340,359` | A ``` inside an example payload breaks the Markdown export. |
