# MQTT Studio website: content brief

Input for the AI agent that builds the new www.mqttstudio.com. It contains everything the current
site says (captured on 2026-10-25), the facts about the product, and the features added in
version 2.0 that the current site does not mention yet.

**Rules for the agent**
- Use only the facts in this document. Don't invent features, numbers, prices, customers,
  testimonials, download counts or release dates.
- Items marked **TO CONFIRM** are open. Leave a visible placeholder for them instead of guessing.
- Copy marked "current site" may be reused or rewritten. The texts under "Suggested copy" are
  drafts; keep their facts when you rewrite them.
- Write UI names the way the app shows them: tab names in capitals (TOPIC VIEWER, SIMULATOR,
  RECORDER, DOCUMENTATION), feature names in normal case (Grouped view, flight recorder).
- The product name is **MQTT Studio** (two words, no hyphen). The current site also uses
  "MQTTStudio" and "MQTT-Studio"; don't keep those.

---

## 1. Product facts

| Item | Value |
|---|---|
| Product | MQTT Studio |
| What it is | An MQTT client for developers who build, test and support MQTT-based systems |
| Publisher | **Sarix** (the app's About dialog, the EULA and the package's publisher name say Sarix since version 2.0; the Microsoft Store identity still belongs to Redpin). The current site still says Redpin everywhere, see §8 |
| Version | 2.0.0 (the release with the new features of §4). Release date: **TO CONFIRM** |
| First release | 1.0.0 on 09/11/2023 (release notes, date format as in the PDF) |
| Platforms | Windows desktop app (Microsoft Store) and web app in the browser. Same layout in both. No mobile app or mobile layout |
| Command line | `mqttstudio` command, installed with the Windows desktop app (new in 2.0) |
| Price | Free. The free version stays free, with no ads. Commercial add-on features are planned; none exists yet |
| Licence | Free for personal and commercial use under the EULA |
| Built with | Flutter (Google's cross-platform UI toolkit), one code base for desktop and web |
| Protocols | MQTT 3.1.1 and MQTT 5, chosen per project. TCP, TLS, WebSockets (`ws://`, `wss://`). The browser version connects over WebSockets only |
| Microsoft Store | https://www.microsoft.com/store/productId/9N3BV5PG4JTG |
| Web app | https://www.mqttstudio.com/webapp |

**Positioning.** The current site positions MQTT Studio as a practical, free developer tool for
looking at MQTT traffic. Version 2.0 widens this: besides watching messages, MQTT Studio now
**generates** traffic (simulator), **captures and replays** it (recorder), **documents** a
broker's topics (documentation), runs all of this **headless** in scripts and CI (CLI), and
**understands two industrial protocols** that run on MQTT: **VDA 5050** (mobile robots / AGVs)
and **Sparkplug B** (industrial IoT). A possible one-line summary: *Watch, simulate, record and
document your MQTT traffic, in one free tool. With built-in VDA 5050 and Sparkplug B support.*

**Audience.** Developers and testers of IoT and industrial systems, integrators who commission
plants, support engineers who analyze customer installations, and teams who need a reference of
the topics a system uses. With 2.0 also: integrators of AGV/AMR fleets and fleet controls
(VDA 5050), and automation engineers who work with SCADA, MES, historians and edge gateways
(Sparkplug B).

---

## 2. Current site inventory

Site captured on 2026-10-25. English only (`/de/` and `/it/` return 404). Pages live under `/en/`.

| Page | URL | Content |
|---|---|---|
| Home | `/en/index.html` | Hero, features, FAQ, contact (footer) |
| Download | `/en/download.html` | Microsoft Store link, web app link, release notes PDF |
| Terms of Use | `/en/terms-of-use.html` | Legal disclaimer, copyright, privacy, cookies, no spyware |
| EULA | `/en/eula.html` | End user licence agreement |
| Web app | `/webapp` | The MQTT Studio web app itself (not part of the redesign) |
| Release notes | `/downloads/ReleaseNotes.pdf` | One page, version 1.0.0 only |

**Navigation:** logo (home), Features (`#features`), Contact (`#contact`), Download.
**Footer:** address, info and support email, Download, Terms of Use, EULA, copyright line.
**Meta:** the page `description` meta tag is empty on every page. Add real descriptions.
**Credits:** web design and programming by VisualRun (Terms of Use page).

**Assets on the current site** (reuse or replace):
- Logo `/assets/Logo/MQTT-Logo.svg`, publisher logo `/assets/Logo/redpin-logo_white.svg`
- Screenshots `/assets/img/grouped_chart.png`, `grouped_img.png`, `tree_chart.png`
- Feature icons (Material Symbols): `integration_instructions`, `list_alt`, `view_module`,
  `colorize`, `description`, `visibility`, `filter_list`, plus `icon-1.svg`
- Download page icons: Microsoft Store icon, `open_in_new`, `download`

**Assets in the repository:**
- `product/screenshots/`: `grouped_chart.png`, `grouped_img.png`, `sequiential_chart.png`,
  `sequiential_img.png`, `tree_chart.png`, `tree_img.png` (all version 1.x UI)
- `CI/`: app icons and logos
- There are **no screenshots of the 2.0 features yet** (SIMULATOR, RECORDER, DOCUMENTATION, CLI).
  **TO CONFIRM:** who makes them. §7 lists the shots needed.

---

## 3. Core features (on the current site, still valid)

Each entry: the current site's text (shortened), then facts from the app the site doesn't
mention.

### Projects
Current site: projects bundle the MQTT settings and topic subscriptions in one place, so
developers switch between scenarios (test broker, production, customer A) quickly.
App facts: a project holds the broker (host, port, client id, user name and password), the
protocol (MQTT 3.1.1 or MQTT 5), TLS and WebSockets, clean start and session expiry (MQTT 5),
the topic subscriptions with their colors, and since 2.0 also the simulation and the topic
documentation. Projects are stored locally (in the browser for the web app).

### Topic subscription panel
Current site: shows all active subscriptions; subscribe, unsubscribe, or pause a single topic to
stop receiving it for a while.
App facts: each subscription is a colored chip; tap to pause or resume, ✕ to unsubscribe.
Wildcards `+` and `#` are supported. On MQTT 5 a subscription has the options No Local, Retain As
Published and Retain Handling.

### Messages viewer with three views
Current site: three view modes, Grouped, Hierarchical and Sequential, switchable at any time.
- **Grouped view:** messages grouped by time period (1 s, 10 s, 1 min, 1 h), to see sequences and
  patterns.
- **Hierarchical view:** the topic tree with message counts per topic; an overview of what flows
  into a system.
- **Sequential view:** every message in arrival order.

### Color-coded topics
Current site: each topic gets a color and all its messages show in that color, so messages are
easy to tell apart.

### Message detail view
Current site: all metadata of a message and its payload; republish the message from here.
App facts: shows received time, QoS, retain, payload size, message count of the topic, and on
MQTT 5 the properties (content type, response topic, correlation data, message expiry, payload
format, user properties, subscription ids). Copy topic and payload, clear a retained message,
auto-select the newest message, show the last 1,000 messages of the topic.

### Payload viewer
Current site: renders the payload by its content: text, numbers, dates, images (JPG, PNG) and
JSON.
App facts: GPS coordinates (`lat,lon` payloads) show on a **map** (added in 2024, not on the
current site). Since 2.0, binary and encoded payloads can be decoded (§4.3), and VDA 5050 and
Sparkplug B messages are shown interpreted (§4.8, §4.9).

### Chart view
Current site: numeric payloads show as a chart over time.
App facts: with **min, max and average** lines.

### Topic filter
Current site: narrows the messages shown by topic name.
App facts: since 2.0 the filter also checks payload text and conditions on values (§4.3).

### Publish dialog
Not on the current site. Publish a message with topic, payload, QoS and retain, or publish a file
(up to 500 KB, e.g. an image). On MQTT 5 with content type, message expiry, UTF-8 flag, response
topic, correlation data and user properties.

### Web app performance note
In the browser, the app shows a hint that performance is limited and suggests the desktop app for
high message rates. The site may say the same: the web app is ideal to start right away, the
desktop app for heavy traffic, recordings on disk and the command line.

---

## 4. New in MQTT Studio 2.0

The main window now has four tabs: **TOPIC VIEWER** (everything in §3), **SIMULATOR**,
**RECORDER** and **DOCUMENTATION**. The topic viewer gets two more view modes, **Fleet** (VDA 5050
robots) and **Sparkplug** (edge nodes, devices and metrics), next to Grouped, Tree and Sequential.
All new features, including VDA 5050 and Sparkplug B support, are **free**, with no licence check;
none of them is a commercial add-on.

### 4.1 MQTT 5 support

**Suggested copy:** *MQTT 5 and MQTT 3.1.1. Choose the protocol per project. With MQTT 5, MQTT
Studio shows and sends message properties, sets subscription options and shows what your broker
supports.*

- Protocol chosen per project; existing projects keep MQTT 3.1.1.
- Subscription options: No Local, Retain As Published, Retain Handling.
- Publish properties: content type, message expiry, payload format (UTF-8), response topic,
  correlation data, user properties.
- Received properties in the message detail view.
- Clean start and session expiry per project.

### 4.2 Client certificates (mutual TLS)

**Suggested copy:** *Connect to brokers that require client certificates. Add your CA certificate,
client certificate and private key to the project.*

- CA certificate, client certificate, private key and key password per project.
- Desktop app only (TLS over TCP). The browser connects over WebSockets.

### 4.3 Topic viewer tools

**Suggested headline:** Find the message that matters.
**Suggested copy:** *Filter by topic, payload or value. Decode binary payloads. See what changed
since the last message, compare any two, and find the retained messages nobody remembers
publishing. All in the topic viewer you already know.*

- **Three filter modes** in the command bar:
  - **Topic:** part of the topic, or an MQTT topic filter with `+` and `#` (`plant/+/temp`).
  - **Payload:** text in the payload.
  - **Condition:** a value test on the payload, e.g. `$.status == "error"` or
    `plant/+/temp > 80`, with `== != > >= < <=`, `contains` and `~` (regular expression). Same
    syntax as the recorder's triggers.
  - Each mode can use a regular expression; all ignore case. In the tree view, payload filters test
    each topic's last message.
- **Payload decoders**, chosen per topic: Auto, Text, Hex, Base64, gzip/zlib, MessagePack and
  CBOR. Binary payloads get a hex view. A decoded payload works like any other: JSON viewer, chart,
  filter.
- **Changes since the previous message:** one click highlights what changed in a topic's payload
  since its last message, field by field for JSON ("was 21.4, now 21.9") or as a text diff.
- **Compare two messages:** pin one message, select another (any topic), and see whether the
  payloads are equal and every difference.
- **Edit and publish:** opens the publish dialog prefilled with the selected message, to change a
  value and send it again.
- **Topic statistics** in the tree view: messages and bytes per second, the time since the last
  message, and the average interval with its jitter, per topic. Shows at a glance which topics are
  slow, irregular or silent.
- **Tree context menu:** copy a branch as a topic or wildcard filter, subscribe to or unsubscribe
  from a branch, expand and collapse branches, open the retained messages of a branch.
- **Retained message manager:** scans a topic filter for retained messages on the broker, lists
  them with topic, payload and size, and clears the selected ones (with confirmation). Useful to
  clean up after tests or find stale state.
- **Broker statistics ($SYS):** an app bar button shows the broker's `$SYS` topics live: version,
  uptime, connected clients, message and byte rates, subscriptions, retained and stored messages,
  with a summary for Mosquitto and the full list for other brokers.
- **Broker info:** what the broker reported on connect (MQTT 5): maximum QoS, retain available,
  maximum packet size, receive maximum, topic alias maximum, server keep alive, support for
  wildcard subscriptions, subscription identifiers and shared subscriptions, assigned client id.

The retained message manager and the broker statistics use their own connection, so they don't
disturb the topic viewer's subscriptions.

### 4.4 SIMULATOR: simulated devices without hardware

**Suggested headline:** Simulate devices, not just messages.
**Suggested copy:** *Test dashboards, backends and integrations before the hardware exists.
Define a device once, run it as 1,000 instances, and let MQTT Studio publish realistic sensor
values, GPS tracks, images and JSON documents on a schedule.*

What it does:
- **Devices with instances.** A device has several topics; one definition expands to up to 1,000
  instances. Topic placeholders: `{n}` (instance number), `{n:3}` (zero-padded, `007`) and
  `{device}`, e.g. `weather/{n}/temp` → `weather/1/temp` … `weather/10/temp`.
- **11 payload generators:**
  - Random string
  - Random number
  - Counter (also for codes like `ORD-0001`)
  - Boolean (`true/false`, `1/0`, `ON/OFF`)
  - Value list (random or in order)
  - Random walk (drifts like a real sensor, within limits)
  - Wave (sine, square, triangle, sawtooth, with noise)
  - Timestamp (ISO 8601, epoch, custom pattern)
  - GPS track (wander around a point or follow a route)
  - Random image (JPG/PNG from a folder, desktop only)
  - Template: JSON or any text built from named fields, each with its own generator
- **Timing:** fixed or random interval per topic (from 50 ms). Instances start staggered so they
  don't all fire at once.
- **MQTT options:** QoS, retain, and MQTT 5 properties (content type, message expiry, user
  properties).
- **Control:** start and stop everything, one device or one topic. Live statistics per topic:
  messages sent, last payload (with the instance that sent it), errors.
- **Live preview** of generated values while editing.
- **Rate guard:** shows the estimated message rate, warns above 100 msg/s (50 in the browser),
  refuses above 1,000 msg/s in the app.
- **One click to watch:** subscribe to a simulated topic in the TOPIC VIEWER (`weather/+/temp`).
  Generated numbers chart, GPS positions show on the map, images show as images.
- **Clear retained:** removes the retained messages a simulation left on the broker.
- **Recorded devices:** a device can also replay a recording (see §4.5) instead of generating
  values, e.g. one real machine replayed as 20 machines.
- **VDA 5050 robots** and **Sparkplug B edge nodes** as ready-made device kinds that follow their
  protocol, with fault injection (see §4.8 and §4.9).
- **Saved in the project**, and runnable from the command line (`mqttstudio simulate`).

Use cases: load tests, demo systems, frontend development without a backend, testing alarms with
values that leave their range, reproducing many devices with one laptop.

### 4.5 RECORDER: record, replay and analyze MQTT traffic

**Suggested headline:** Record it once. Replay it anywhere.
**Suggested copy:** *Capture a customer's traffic and reproduce the bug at your desk. Replay a
production day into a test system at 10× speed. Keep the last 10 minutes before every alarm.
Compare two runs and let your CI fail when the output changes.*

Recording:
- Record one topic, a wildcard filter, or several filters with exclusions.
- Every message is stored with payload, QoS, retain flag, MQTT 5 properties and receive time.
  The retained state at the start is kept as a snapshot.
- Runs on its own connection, so recording doesn't depend on the CONNECT button; reconnects
  automatically and marks the gap.
- **Start and stop by condition:** start when a message matches (with up to 10 minutes of
  pre-roll from before the trigger), stop after a duration, a message count, a size or a
  condition (with post-roll).
- **Flight recorder:** keeps the last minutes in memory and saves them on a button press or when
  a condition matches, like a plane's flight recorder.
- Conditions are simple text, e.g. `plant/+/temp > 80` or `plant/line1/state $.status == "error"`.
- **Save as recording** from the TOPIC VIEWER: turn the messages on screen into a recording.
- A red **REC indicator** in the app bar shows a running recording on every tab.
- Recordings are files (`.mqttrec`), crash-safe, kept in a library folder
  (`Documents\MQTT Studio\Recordings` by default) and linked to their project. In the browser they
  are kept in the browser's storage (up to 100 MB each).

Playback:
- Play a whole recording, one topic or a selection, at 0.1× to 100× or as fast as allowed.
- Pause, resume, seek, step message by message, loop, play a time range, shorten long pauses.
- Rewrite topics on the fly (`prod/` → `test/`), override retain and QoS, publish or skip the
  retained snapshot.
- Timing doesn't drift, also over hours.
- **Add to simulation:** run a recording as a recorded device with many instances.

Analysis (tabs OVERVIEW, TIMELINE, MESSAGES, CHARTS, COMPARE):
- **Overview:** per topic: messages, rate, interval, payload size, gaps.
- **Timeline:** one lane per topic, zoom and pan, select a range, bookmarks, connection-loss
  markers.
- **Messages:** the TOPIC VIEWER's grouped, tree and sequential views, filter and detail view on
  recorded data.
- **Charts:** a number payload or a JSON field over time with min, max and average; interval
  histogram; GPS positions as a track on the map.
- **Gaps and duplicates** per topic.
- **Compare** two recordings: counts, payloads (JSON compared by content, fields can be ignored,
  number tolerance) and timing. In CI the command fails when they differ.

Editing (the original is never changed, every edit makes a new recording): trim, keep or delete
topics, rename topics, merge, split (at bookmarks, at the playhead, per topic) and **anonymize**
(hash, mask, replace, remove or jitter values, e.g. before sending a recording to a supplier).

Import and export: JSON lines and CSV (with chosen JSON fields as columns); import also reads
`mosquitto_sub` output.

Use cases: reproduce field issues offline, regression tests in CI, demo data, load tests from real
traffic, sharing anonymized traffic with partners.

### 4.6 DOCUMENTATION: document your topics automatically

**Suggested headline:** Your MQTT topics, documented in minutes.
**Suggested copy:** *Writing topic documentation by hand is slow and out of date the day after.
MQTT Studio listens to your broker and writes the first draft for you: every topic with its
payload format, JSON schema, interval, QoS and retain flag. You add the descriptions, and a check
tells you when devices stop following the documentation.*

- **Discover:** subscribe to one or more wildcard filters and listen for a few minutes, or read a
  recording or the TOPIC VIEWER's messages. Every topic becomes a documented entry with payload
  format, inferred JSON schema, interval (periodic, on change, event), QoS, retain flag and
  examples.
- **Templates:** topics that differ only by an id are proposed as one template with parameters,
  e.g. `plant/{line}/m{machine}/temp` instead of hundreds of single topics.
- **Review, never overwrite:** running discovery again lists new, changed and no longer seen
  topics. Nothing you wrote is overwritten without asking.
- **Edit:** title, description, status (draft, stable, deprecated), owner, tags, links,
  parameters, payload (format, unit, range, allowed values, JSON schema as a field table,
  examples), delivery (QoS, retain, interval, "stale after"), MQTT 5 properties, producers,
  consumers, sensitivity and access notes. Observed values are shown next to the documented ones.
- **Check:** compares live traffic with the documentation and lists findings as errors or
  warnings: undocumented topics, wrong format, JSON that breaks the schema, values out of range or
  not allowed, wrong QoS or retain, topics that go silent, deprecated topics still in use. On
  VDA 5050 and Sparkplug B topics it also checks the protocol rules (see §4.8 and §4.9).
- **Ready-made VDA 5050 documentation:** one click imports all VDA 5050 topics with the official
  JSON schemas (versions 2.1 and 3.0).
- **Export:** Markdown, HTML (print to PDF), **AsyncAPI 3.0** (YAML or JSON), a JSON Schema bundle
  and CSV. Exports never contain passwords, certificates or the client id.
- **Import:** AsyncAPI 2.x and 3.x, merged with what is already documented.
- **Connected to the rest of the app:** create a simulation from documented topics, discover from
  a recording, documented titles appear as tooltips in the TOPIC VIEWER tree.
- Saved in the project; discovery and check never publish anything.

Use cases: document an existing plant or product before a project starts, hand a system over to a
customer or support team, review naming and payload consistency, check in CI that devices still
send what the documentation promises, exchange the API as AsyncAPI.

### 4.7 Command line (CLI)

**Suggested headline:** Automate it.
**Suggested copy:** *Everything you set up in the app also runs headless: simulate devices on a
test server, record a night shift, replay into staging, and fail your pipeline when the output or
the topic documentation doesn't match.*

- Installed with the Windows desktop app; the command is `mqttstudio`. Not available in the
  browser version.
- Commands: `projects`, `simulate`, `record`, `replay`, `recordings` (list, show, export, import,
  edit, compare) and `doc` (discover, check, export, import).
- Uses the projects saved in the app; broker settings can be overridden per run. Passwords come
  from environment variables, never from the command line.
- Machine-readable output (`-o json`, one JSON object per line) and documented exit codes for CI.
- `simulate` runs VDA 5050 robots and Sparkplug edge nodes too, `doc check` applies the VDA 5050
  and Sparkplug B protocol rules, and `doc import --preset vda5050-v2|vda5050-v3` writes the
  ready-made VDA 5050 documentation.
- App and CLI can run at the same time.
- Full user manual: `doc/cli-manual.md` in the repository. **TO CONFIRM:** whether the manual is
  published on the site (it would fit as a docs page).

Example for a feature section (from the manual):

```
mqttstudio simulate -p "Demo factory" --duration 8h
mqttstudio record -p "Plant" -t "plant/#" --flight 15m --save-when "plant/+/alarm"
mqttstudio recordings compare reference.mqttrec run-42.mqttrec --ignore '$.ts'
mqttstudio doc export -p "Plant" --format asyncapi-yaml --out asyncapi.yaml
```

### 4.8 VDA 5050: mobile robots and fleet controls

**Suggested headline:** See what your robots are doing.
**Suggested copy:** *VDA 5050 is the open interface between AGVs, AMRs and their fleet control.
MQTT Studio reads it for you: every message in plain words, all robots on one map, the protocol
checked, and a simulated fleet to test against before the first robot arrives.*

Background for the agent: VDA 5050 is published by the German automotive association VDA and
VDMA. It runs on MQTT with JSON messages and a fixed topic layout
(`{interface}/{version}/{manufacturer}/{serialNumber}/{topic}`, topics `order`,
`instantActions`, `state`, `visualization`, `connection`, `factsheet`, and in 3.0 `zoneSet` and
`responses`). Version 2.x runs in most installed fleets; 3.0 was released in March 2026 and adds
freely navigating robots, zones and requests. Plants will run both for years.

- **Versions 2.0, 2.1 and 3.0**, also mixed in one plant; 1.1 is read where it matches 2.0. No
  setting needed: messages are recognized by topic and content.
- **Messages in plain words:** each message gets a one-line summary in the topic viewer, e.g.
  robot, mode, driving, battery, order progress and error count. Messages in which a robot
  reports a warning or an error are marked.
- **Interpreted detail view:** status, errors, action states, order progress, nodes and edges,
  and for 3.0 paths, zones, requests and responses, instead of a large raw JSON document. One click
  switches back to the raw payload.
- **Charts** of a message type's values: state of charge, velocity, position.
- **Fleet view** (new view mode of the topic viewer): all robots in one table (connection, mode,
  driving, battery, errors, order, open requests, version) and on a 2D map per map id, with the
  selected robot's trail, order (released and planned part), and for 3.0 its planned path and the
  zones. Also works on recordings.
- **Ready-made documentation** for 2.1 and 3.0, built from the official JSON schemas: topics,
  payload schemas, QoS, retain and the state heartbeat. Discovery suggests it when it finds
  VDA 5050 topics.
- **Protocol check** (documentation tab and CLI): header doesn't match the topic, header id gaps
  or restarts, timestamp skew, broken order structure, invalid order updates, duplicate action
  ids, missing state heartbeat, and for 3.0 unanswered requests, responses without a request and
  visualization ahead of state. Plus schema, QoS and retain checks from the documentation.
- **Simulated robots** (SIMULATOR): a fleet of up to 200 VDA 5050 2.x or 3.0 robots that drive
  orders on a grid layout, wait for each other, charge when the battery is low, and for 3.0 respect
  zones and request permission. The simulator plays the fleet control too, so all of this works
  with nothing but a broker.
- **Fault injection** while the simulation runs, per robot: warnings, fatal errors, emergency
  stop, low battery, cancelled order, connection broken, offline, hibernate, and protocol faults
  (skipped header ids, clock skew, wrong serial number, broken orders, …). Each protocol fault
  triggers its check rule, so the check can be demonstrated.

Use cases: commissioning a fleet control against robots from several manufacturers, testing a
robot's VDA 5050 implementation before the acceptance test, migrating a fleet from 2.x to 3.0,
troubleshooting in a running plant ("why did robot 0001 stop?").

What it doesn't do (don't claim it): MQTT Studio is not a fleet control. It doesn't plan routes,
grant zones or send orders to real robots (users can still publish any message by hand). The
simulated robots follow the simulator's own fleet control, not an external one. No layout
backgrounds (CAD, LIF files) on the map.

### 4.9 Sparkplug B: industrial IoT

**Suggested headline:** Sparkplug B, decoded.
**Suggested copy:** *Sparkplug B traffic is binary Protobuf with metrics sent by alias. MQTT
Studio decodes it, names every metric from the birth certificates, shows each edge node and
device with its live values, checks the session rules, and simulates edge nodes that follow the
specification.*

Background for the agent: Sparkplug B (Eclipse Foundation, specification 3.0, also ISO/IEC
20237) is the most widely used MQTT convention in industrial IoT. Edge nodes and their devices
announce their metrics in a *birth* message, then send only changed values, by alias, as
Protobuf. Without decoding, a generic MQTT client shows hex, and even decoded data has no names.

- **Decoded messages:** all message types (NBIRTH, NDEATH, NDATA, NCMD, DBIRTH, DDEATH, DDATA,
  DCMD and host STATE), all data types including arrays, DataSets and Templates, compressed
  payloads (GZIP, DEFLATE). A one-line summary per message, e.g. metric names and values with
  units.
- **Names from the birth:** data messages show metric names, data types and units taken from the
  last birth. When the birth was missed, metrics show by alias with a warning.
- **Request rebirth:** one click (with confirmation) asks an edge node, or all edge nodes of a
  group, to send their births again, from the detail view, the tree's menu or the Sparkplug view.
  MQTT Studio never sends it on its own.
- **Sparkplug view** (new view mode of the topic viewer): host applications, groups, edge nodes
  and devices as a tree with online/offline state, bdSeq, seq and seq gaps; for the selected node
  or device all metrics with current value, unit, data type, age, number of changes and
  properties. Sort by changes to find metrics that are stuck; click a metric to chart it. Also
  works on recordings. *A host application in miniature, for commissioning and support.*
- **Charts** of numeric and boolean metrics by name.
- **Protocol check** (documentation tab and CLI): payload isn't Sparkplug B, missing or skipped
  seq, missing timestamp, missing or mismatched bdSeq, data after the edge node's death, device
  data without birth, birth metrics without data type, duplicate aliases, unknown metrics and
  changed data types.
- **Simulated edge nodes** (SIMULATOR): up to 20 edge nodes with up to 20 devices and 200 metrics
  each, following the Sparkplug 3.0 specification: one MQTT connection per edge node with the
  NDEATH as real last will, births, data by exception (with deadband), seq and bdSeq, rebirth on
  request, writable metrics (answers NCMD/DCMD writes), optional compression. Metric values come
  from the simulator's generators (wave, random walk, counter, …). The simulator can also play the
  primary host application (STATE), so a full system runs with only a broker. Use it to test a
  SCADA, MES or historian without a PLC.
- **Fault injection** per edge node: drop the connection (the broker sends the will), restart,
  devices offline, and protocol faults (skipped seq, unknown metric, wrong data type, data after
  death, device data without birth, wrong bdSeq, missing timestamp, non-Sparkplug payload). Each
  protocol fault triggers its check rule.

Use cases: commissioning edge gateways and PLC connections, testing host applications against a
reference edge node and against known faults, troubleshooting missing or stale metrics.

What it doesn't do (don't claim it): no writing of metrics from a command editor yet (users can
publish by hand), discovery documents Sparkplug topics without their metrics, Sparkplug 2.2 is
read but not simulated, no store-and-forward in the simulator.

Trademark note: "Sparkplug" is a trademark of the Eclipse Foundation. **TO CONFIRM:** whether the
site needs a trademark notice for Sparkplug and VDA 5050.

### 4.10 Availability: desktop vs. browser

| Feature | Windows desktop | Browser |
|---|---|---|
| TOPIC VIEWER, publish, projects | yes | yes |
| Topic viewer tools (filters, decoders, diff, compare, retained messages, $SYS) | yes | yes |
| MQTT 5 | yes | yes |
| Connection types | TCP, TLS, WebSockets | WebSockets (`ws://`, `wss://`) only |
| Client certificates | yes | no |
| SIMULATOR | yes | yes, except the random image generator; slows down in background tabs |
| RECORDER | yes, recordings as files | yes, recordings in browser storage, max 100 MB each |
| DOCUMENTATION | yes | yes, exports are downloaded |
| VDA 5050 and Sparkplug B in the topic viewer and check | yes | yes (Sparkplug 64-bit values above 2^53 lose precision) |
| Simulated VDA 5050 robots and Sparkplug edge nodes | yes | **TO CONFIRM** (tested on desktop) |
| Command line | yes | no |
| High message rates | recommended | limited |

---

## 5. Suggested site structure

A proposal; the designer may change it.

1. **Home**
   - Hero: name, one-line summary, buttons "Download for Windows" (Microsoft Store) and "Open in
     browser". Free, MQTT 5, Windows and web as small badges.
   - Four pillars with one screenshot each: Watch (TOPIC VIEWER), Simulate, Record, Document.
     Plus a strip for "Automate" (CLI) and one for "Industrial protocols" (VDA 5050, Sparkplug B).
   - Core features grid (§3).
   - "What's new in 2.0" teaser.
   - FAQ (§6), contact.
2. **Feature pages** (or long sections): Topic viewer (with the tools of §4.3), Simulator, Recorder,
   Documentation, Command line, VDA 5050, Sparkplug B, each with use cases, capabilities and
   screenshots. VDA 5050 and Sparkplug B deserve pages of their own: they address specific
   audiences who search for these terms.
3. **Download:** Microsoft Store, web app, the desktop/browser table (§4.10), system requirements
   (**TO CONFIRM**: minimum Windows version), release notes as a web page instead of only a PDF.
4. **Docs** (optional): CLI manual, getting started.
5. **Release notes** (§9).
6. **Legal:** Terms of Use / privacy, EULA, imprint. See §8 for what needs updating.

SEO: real page titles and meta descriptions, e.g. "MQTT Studio – free MQTT 5 client, simulator
and recorder for Windows and the browser". Keywords that fit: MQTT client, MQTT 5, MQTT explorer,
MQTT simulator, MQTT recorder, MQTT replay, AsyncAPI, IoT testing, VDA 5050, VDA 5050 simulator,
AGV, AMR, fleet control, Sparkplug B, Sparkplug decoder, Sparkplug edge node simulator, IIoT, MQTT retained messages, MQTT $SYS, MQTT payload decoder,
MessagePack, CBOR.

---

## 6. FAQ

Current site questions with updated answers. Changed facts are noted.

**What is MQTT Studio for?**
Current: a tool for developers to manage MQTT-based applications, with a user-friendly interface
and advanced message analysis. *Update:* add simulation, recording and replay, documentation and
automation.

**What is the licensing model?**
Free for personal and commercial use. Details in the EULA.

**Who is behind MQTT Studio?**
Current: a team of developers who build tools for developer productivity in their spare time,
including the localization tool Babylon, linked to redpin.eu. *Update:* the publisher is now
Sarix. **TO CONFIRM:** new text for this answer, and whether Babylon is still mentioned.

**How do I submit a feature request or report a bug?**
By email (support address, see §8). Bug reports, feature requests and suggestions are welcome.

**How does MQTT Studio make money?**
It doesn't at the moment. The free version will always stay free, without ads and without plans to
sell it. Commercial features for developers are planned. *Note:* all 2.0 features (simulator,
recorder, documentation, CLI) are part of the free version.

**Which language is MQTT Studio developed in?**
Flutter, Google's open-source UI toolkit, with one code base for desktop and web.

New questions worth adding:
- **Does it support MQTT 5?** Yes, and MQTT 3.1.1, chosen per project.
- **Desktop or browser, what's the difference?** See §4.10.
- **Does MQTT Studio support VDA 5050?** Yes, versions 2.0, 2.1 and 3.0: interpreted messages, a
  fleet view, ready-made documentation, a protocol check and simulated robots (§4.8).
- **Does MQTT Studio decode Sparkplug B?** Yes: decoded payloads with metric names from the birth,
  rebirth requests, a Sparkplug view, a protocol check and simulated edge nodes (§4.9).
- **Can I test my fleet control / SCADA without real hardware?** Yes, with simulated VDA 5050
  robots or Sparkplug edge nodes, including injected faults.
- **Can I run it in CI or on a server?** Yes, with the `mqttstudio` command line (Windows).
- **Where are my projects and recordings stored?** Locally on your computer (or in your
  browser). Projects aren't uploaded anywhere.
- **Can I export my topic documentation?** Yes: Markdown, HTML/PDF, AsyncAPI 3.0, JSON Schema,
  CSV.

---

## 7. Screenshots and visuals needed

The app is a dense, desktop-first tool; design it for a wide window (~1500 px). Light theme only:
dark grey app bar, deep red accent (`#B71C1C`), topic chips in strong colors (indigo, blue, pink,
amber, deep purple, orange, brown, green, teal, lime). The connect button is red with CONNECT while disconnected
and green with DISCONNECT while connected.

Existing (version 1.x UI, still representative of the TOPIC VIEWER): see §2.

Needed for 2.0 (**TO CONFIRM** who provides them):
1. TOPIC VIEWER with the four tabs visible, grouped view, detail view with a chart.
2. Tree view with topic statistics and the context menu; the detail view with "changes since the
   previous message" highlighted; the retained message manager; the broker statistics dialog.
3. Map view of a GPS payload.
4. SIMULATOR with a multi-instance device running, and the topic dialog with a template generator.
5. RECORDER with the timeline, the REC indicator in the app bar, the CHARTS tab.
6. DOCUMENTATION with tree, editor and observed panel; the discovery review; the check findings.
7. A terminal with `mqttstudio simulate` or `record` output.
8. Fleet view with simulated VDA 5050 robots on the map, one robot selected with its order, and
   an interpreted VDA 5050 state in the detail view.
9. Sparkplug view with edge nodes, devices and the metric table, and a decoded Sparkplug message
   in the detail view.
10. SIMULATOR with a VDA 5050 or Sparkplug device and its Faults menu open.
11. Documentation check findings with VDA 5050 or Sparkplug protocol rules (optional).
12. An exported HTML documentation page or AsyncAPI file (optional).

App design system (tokens, colors, components of the app UI):
https://claude.ai/artifact/M1uENVXPQJf74mB86VB5yu (private Claude artifact; the agent may not have
access, ask the owner for an export if needed).

---

## 8. Company, contact and legal (needs updating)

The current site (and its legal pages) still name **Redpin**. Since version 2.0 the app, the EULA
and the package's publisher name say **Sarix**. Everything below is **TO CONFIRM** before publishing.

| Item | Current site | New |
|---|---|---|
| Publisher / copyright | "Copyright © 2026 by Redpin", Redpin logo | Sarix. **TO CONFIRM:** Sarix logo file, legal company name (the git email domain is sarix.eu) |
| Address | via Buozzi 12, 39100 Bolzano (BZ), Italy | **TO CONFIRM** |
| General email | info@redpin.eu | info@sarix.eu (used in the app since 2.0) |
| Support email | support@redpin.eu | **TO CONFIRM** |
| Map link | https://goo.gl/maps/u8oeH8PgKp9U2gf37 | **TO CONFIRM** |
| Babylon link (FAQ) | https://www.redpin.eu/ | **TO CONFIRM** keep or remove |

**Terms of Use page.** Current content: copyright (all site content is the property of Redpin),
privacy (refers to purchases on redpin.eu, with name, address and credit card data), cookies (no
profiling or social cookies; technical cookies for traffic analysis), no spyware or adware (the
app has no ads, no bundled programs, never sends personal data without the user's knowledge),
disclaimer of warranties. Needs an update for Sarix, and **TO CONFIRM:**
- the purchase/credit card paragraph, which doesn't apply to a free app;
- analytics: the app uses Piwik for usage statistics (which tool the site uses is unknown); the app's optional newsletter
  sign-up asks for email, name and company with consent under the GDPR. The privacy text should
  cover both. A privacy policy page is linked from the newsletter dialog; **TO CONFIRM** its URL.

**EULA page.** The text in the repository (`src/DesktopSetup/eula.txt`) now names Sarix as the
licensor; the site still shows Redpin. Use the repository text. Note: clause 2 ("Translator
edition") and "number of user accounts" are leftovers from Babylon; **TO CONFIRM** whether the
EULA gets revised.

**Imprint:** the current site has none. **TO CONFIRM** whether one is needed (company details, VAT
number).

---

## 9. Release notes

Current PDF (`/downloads/ReleaseNotes.pdf`, Redpin layout):

**1.0.0 – 09/11/2023 (initial release)**
- Projects
- Grouped topic viewer
- Hierarchical topic viewer
- Sequential topic viewer
- Topic detail view with chart and image viewer
- Topic filter

Not in the PDF (from the project history):
- 1.x updates, 2024: map viewer for GPS payloads; min, max and average in the chart. 2025:
  WebSocket URLs no longer need the `/mqtt` path. Exact versions **TO CONFIRM**.

**2.0.0 – release date TO CONFIRM**
- New: MQTT 5 (per project, with properties, subscription options and broker info)
- New: topic viewer tools: payload and condition filters, payload decoders (Hex, Base64,
  gzip/zlib, MessagePack, CBOR), changes since the previous message, comparing messages, edit and
  publish, topic statistics, tree context menu, retained message manager, broker statistics ($SYS)
- New: client certificates for TLS connections
- New: SIMULATOR tab with simulated devices, 11 payload generators and recorded devices
- New: RECORDER tab: record, replay, analyze, edit, compare, import and export MQTT traffic
- New: DOCUMENTATION tab: discover, document, check and export topics (AsyncAPI 3.0)
- New: VDA 5050 support (2.x and 3.0): interpreted messages, Fleet view, documentation presets,
  protocol check, simulated robots with fault injection
- New: Sparkplug B support: decoding, Sparkplug view, rebirth requests, protocol check, simulated
  edge nodes and host with fault injection
- New: `mqttstudio` command line for Windows
- Publisher changed to Sarix

---

## Appendix: current home page copy

For reference, as on the site on 2026-10-25.

**Hero:** "MQTTStudio is a practical MQTT client designed for developers to efficiently create,
test, and manage MQTT-based applications, enhancing their development and support workflows."
Buttons: "Download Client", "Use in browser".

**Features** (titles in site order): Grouped Messages View, Hierarchical Messages View, Projects,
Topic subscription panel, Messages viewer, Color coded topics, Message detail view, Payload viewer,
Topic filter, Chart view. Their content is summarized in §3.

**About dialog text in the app** (can serve as marketing copy): "Unlock the full potential of MQTT
development with MQTT Studio! Seamlessly manage, visualize, and optimize your IoT data flow.
Empower developers with a user-friendly interface to build robust and efficient MQTT
applications."
