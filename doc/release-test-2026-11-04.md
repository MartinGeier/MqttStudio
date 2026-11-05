# Browser release test of MQTT Studio 2.0.0+5, 2026-11-04

Release web build (`flutter build web --release`, commit `73dd1a5` on `develop`), served under `/webapp/` as in production, Chrome at 1500×900. Brokers: broker.emqx.io (wss 8084) and broker.hivemq.com (wss 8884), MQTT 5. All test traffic used the `sarix-rt-2611/…` and `spBv1.0/SarixRT2611/…` namespaces. The retained message published during the test was cleared.

## Verdict

Two findings should be fixed before the release (H1, H2). Everything else works or is minor.

**Update:** H1 and H2 are fixed (uncommitted, see "Fixes" below). The other findings are still open.

## Findings

| | Sev | Area | Finding |
|---|---|---|---|
| H1 | High | Connection | **Connecting fails with "Session taken over (0x8e)" when the broker answers CONNECT after more than 5 s.** Reproduced 2 of 3 times with the HiveMQ preset. mqtt5_client retries after its 5 s connect timeout by opening a second socket without closing the first (`mqtt_synchronous_browser_connection_handler.dart` and the server handler alike, so desktop is affected too). The broker then answers the first CONNECT, both sessions use the same client id, and one kicks the other out. The app keeps the defaults (3 attempts, 5 s): `mqtt5_protocol_client.dart:49`, `mqtt311_protocol_client.dart:50`. Fix: `maxConnectionAttempts = 1` and a longer `connectTimeoutPeriod` (e.g. 15 s), and let the app's own reconnect handle retries. Also check `SideConnection` and the Sparkplug edge node connections. |
| H2 | High | Projects | **Unsaved project changes are lost without a prompt when the browser tab is closed or reloaded, and when the desktop window is closed.** Reproduced: a new subscription and a simulator device were gone after a reload. `installLeavePageGuard` and `_onExitRequested` (`message_viewer_page.dart:49,133`) only check `RecorderService.isRecording`. `ProjectManager.hasProjectChanged()` exists and should be part of both guards. Close Project prompts correctly. |
| M1 | Medium | Performance | **The MQTT client logs every packet in release builds.** `_client.logging(on: true)` in both protocol clients. Chrome dropped more than 16,000 console lines in about 15 minutes at ~15 msg/s. That costs CPU per message in the browser, and it logs the CONNECT packet (user name). Use `kDebugMode`. |
| M2 | Medium | Documentation | **CHECK keeps running after the broker refuses its subscription** (EMQX refuses `#` with 0x87) and then reports a misleading "No message in time" finding for a topic that is active. The error snackbar says "Discovery: …" because check errors reuse `DocumentationDialogs.discoveryError` (`documentation_page.dart:39-42`). |
| M3 | Medium | Accessibility | With Flutter accessibility enabled, the command bar filter field takes focus but no typed text. Dialog fields work in the same mode. Probably the `Tooltip` around the `TextField` (`topics_viewer_command_bar.dart:170`). Without accessibility the filter works. |
| L1 | Low | Connection | The connect error shows the raw library text: "mqtt-client::NoConnectionException: The maximum allowed connection attempts ({1}) were exceeded…" (after the H1 fix: after 15 s with 1 attempt). |
| L2 | Low | Detail view | For numeric payloads the large value between "Payload" and the chart is cut off (only the top of the digits is visible). |
| L3 | Low | Simulator | "Last payload" shows only `{` for multi-line JSON. VDA 5050 and Sparkplug rows sit under the generic column headers (Generator, Interval, QoS). The header counter says "1 of 1 topics running" while robots and edge nodes run. Stopped Sparkplug nodes keep "1 of 1 devices online" as last payload. |
| L4 | Low | Tree view | Child order is inconsistent: sensors 3, 2, 1; `temp`/`status` swap between siblings. |
| L5 | Low | Retained messages | The dialog scans `#` on open; the first SCAN click while that runs is ignored without feedback. |
| L6 | Low | Documentation | Discover from a recording opens with an empty, required topic filter; the recording's own filter would be a better default. |
| L7 | Low | Project dialog | A new project's dialog is titled "Edit project". On the web the port defaults to 1883 (only WebSocket ports work) until a preset is picked, and the "Certificates (TLS over TCP)" section is shown although TCP isn't possible. "Ok" vs "OK" between dialogs. |
| L8 | Low | Misc | Save Project gives no confirmation. Recorder library header says "0 of 0 recordings" while the first recording runs. Confirm dialogs show both Cancel and No. |

Not app defects: wss://test.mosquitto.org:8081 timed out from this network (HiveMQ and EMQX were reachable), so the Mosquitto preset could not be tested. Piwik requests are blocked by CORS from localhost; check them once on www.mqttstudio.com.

## Fixes

**H1.** Every MQTT connection now makes a single connect attempt and waits up to 15 s for CONNACK (`MqttProtocolClient.maxConnectionAttempts` / `connectTimeoutPeriod`). Every connection (main, `SideConnection`, Sparkplug edge nodes, CLI) goes through `MqttAdapter` and the two protocol clients, so all of them are covered. The client classes are subclassed in `mqttserver.dart`, `mqttbrowser.dart`, `mqtt3server.dart` and `mqtt3browser.dart` with the mixins `Mqtt5ConnectAttempt` and `Mqtt3ConnectAttempt`:
- mqtt5_client 4.17.1 has no setting for the 5 s CONNACK wait, so the mixin replaces the handler's `connectTimer` right after `connect()` starts. mqtt_client uses its `connectTimeoutPeriod`.
- The library's `disconnect()` leaves the socket of a failed attempt open, so the mixins close it.

Verified in the browser against a local test broker:
- **CONNACK after 8 s:** the client opened one socket and connected.
- **CONNACK after 30 s:** the client opened one socket, failed after 15.0 s with an error, and sent a WebSocket close frame at the same moment.

**H2.** The browser's leave-page guard and the desktop `_onExitRequested` now also check `ProjectManager.hasProjectChanged()`. On desktop, closing the window with unsaved changes shows the same save prompt as Close Project, and Cancel keeps the app open.

Verified in the browser by dispatching `beforeunload`:
- not prevented without a project, or with an unchanged open project after connecting;
- prevented after adding a subscription;
- not prevented after Save Project.

Not verified:
- The browser's own "Leave site?" dialog, because the automation accepts it.
- The desktop exit prompt.
- The 3.1.1 path against a slow broker.

`flutter analyze` is clean, and all 937 tests pass.

## Works

- Projects: new, preset brokers, edit settings, open from the recent cards and the Open dialog, Save, Close with the unsaved prompt, persistence across a page reload (subscriptions, simulator devices, documentation, recordings). "Do not show again" on the performance hint is kept.
- Connection: connect and disconnect, failure snackbar, subscribing while disconnected, broker info, $SYS dialog (explains that the broker sends none).
- Topic viewer: subscribe with MQTT 5 options, publish with retain, content type and user properties, Grouped, Tree (rates, sizes, jitter), Sequential, Fleet and Sparkplug views, pause and resume (global and per chip), clear, filters (topic text, wildcards, regex with error marker, condition `> 20` / `< 0`), detail view with MQTT 5 properties, JSON view, change highlighting and number chart, retained scan and clear with confirmation.
- Simulator: generated devices with `{n}` instances, random walk and JSON template generators with preview, start/stop all and per device, VDA 5050 robots (orders, zones, map), Sparkplug edge nodes with rebirth on request.
- Recorder: record with filter and stop-after, REC indicator, auto-stop, OVERVIEW, TIMELINE, MESSAGES and CHARTS tabs, playback start/stop.
- Documentation: discovery from a recording and from the live broker, review dialog that keeps edited fields, editing a topic, live CHECK with an out-of-range finding, VDA 5050 import with the bundled schemas.

## Not covered

Desktop/MSIX build and CLI; MQTT 3.1.1 projects; TLS client certificates; file import/export and downloads (AsyncAPI, `.mqttrec`, documentation export, publish file); compare messages; payload decoders (hex, Base64, CBOR, MessagePack, images, map); recorded simulator devices; VDA 5050 fault injection; long-running load.
