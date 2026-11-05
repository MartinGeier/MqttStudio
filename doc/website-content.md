# MQTT Studio website: content brief

Input for the AI agent that builds the new www.mqttstudio.com. It explains what the site is for
and how it should sound, gives the facts about the product, shows each feature with its advantage
for developers, and ends with a complete feature list, the current site's content and the open
points.

**Rules for the agent**
- Use only the facts in this document. Don't invent features, numbers, customers, testimonials,
  download counts or release dates.
- Items marked **TO CONFIRM** are open. Leave a visible placeholder for them instead of guessing.
- Follow the tone in §1. The texts under "Intro" are drafts; keep their facts when you rewrite
  them.
- Write UI names the way the app shows them: tab names in capitals (TOPIC VIEWER, SIMULATOR,
  RECORDER, DOCUMENTATION), feature names in normal case (Grouped view, flight recorder).
- The product name is **MQTT Studio** (two words, no hyphen). The current site also uses
  "MQTTStudio" and "MQTT-Studio"; don't keep those.

---

## 1. Purpose and tone

**Why the site exists.** MQTT Studio is a free tool that **Sarix** develops and gives away. Sarix
doesn't sell it and has no paid edition, so the site doesn't need to win buyers. Its job is to
**show developers what MQTT Studio does and how it helps them in their daily work**, so that they
try it, keep using it, and know who built it.

**Tone: show, don't sell.**
- Write like a developer explaining a tool to a colleague: factual, concrete, short sentences,
  second person ("Record the traffic of a plant and replay it at your desk").
- For each feature say **what it does**, **which problem it solves**, and **show it**: a screenshot,
  a real topic, a condition, a command line.
- Let examples carry the message: `plant/+/temp > 80`, `weather/{n}/temp`,
  `mqttstudio recordings compare reference.mqttrec run-42.mqttrec`.
- State "free" as a plain fact (hero badge, download page, FAQ), not as a sales argument.

**Avoid**
- Sales and marketing phrases: "unlock the full potential", "powerful", "seamless", "the best MQTT
  client", "revolutionary", "boost your productivity", "get it now", urgency of any kind.
- Price tables, plan comparisons, "upgrade" or "pro" wording, sign-up walls before the download.
  There is nothing to buy.
- Comparisons with other MQTT tools by name.
- Planned or future features. Show what the app does today.
- Testimonials, customer logos or usage numbers (none exist).

---

## 2. Product facts

| Item | Value |
|---|---|
| Product | MQTT Studio |
| What it is | An MQTT client for developers who build, test and support MQTT-based systems: watch, publish, simulate, record, replay and document MQTT traffic |
| Developed by | **Sarix** (the app's About dialog, the EULA and the package's publisher name say Sarix since version 2.0; the Microsoft Store identity still belongs to Redpin). The current site still says Redpin everywhere, see §9 |
| Version | 2.0.0. Release date: **TO CONFIRM** |
| First release | 1.0.0 on 09/11/2023 (release notes, date format as in the PDF) |
| Platforms | Windows desktop app (Microsoft Store) and web app in the browser. Same layout in both. No mobile app or mobile layout |
| Command line | `mqttstudio` command, installed with the Windows desktop app (new in 2.0) |
| Price | Free, for personal and commercial use, under the EULA. No paid edition, no licence key, no account |
| Built with | Flutter (Google's cross-platform UI toolkit), one code base for desktop and web |
| Protocols | MQTT 3.1.1 and MQTT 5, chosen per project. TCP, TLS, WebSockets (`ws://`, `wss://`). The browser version connects over WebSockets only |
| Data | Projects and recordings stay on the user's computer (or in the browser). Nothing is uploaded |
| Microsoft Store | https://www.microsoft.com/store/productId/9N3BV5PG4JTG |
| Web app | https://www.mqttstudio.com/webapp |

**One-line description** (a draft): *An MQTT client that lets you watch, simulate, record and
document your MQTT traffic, with built-in support for VDA 5050 and Sparkplug B.*

**Audience.** Developers and testers of IoT and industrial systems, integrators who commission
plants, support engineers who analyze customer installations, and teams who need a reference of the
topics a system uses. Also integrators of AGV/AMR fleets and fleet controls (VDA 5050), and
automation engineers who work with SCADA, MES, historians and edge gateways (Sparkplug B).

---

## 3. Advantages for developers

The site should make these advantages visible. Each one points to the features that deliver it.

| Task | How MQTT Studio helps | Features |
|---|---|---|
| **See what is on the broker** | Subscribe and see messages grouped by time, as a topic tree with rates or one by one. Payloads are rendered by content: JSON, numbers as charts, images, GPS positions on a map, binary as hex, decoded MessagePack or CBOR | §4.1, §4.2 |
| **Find the one message that matters** | Filter by topic, payload text or a value condition (`$.status == "error"`), see what changed since the previous message, compare two messages | §4.2 |
| **Understand timing** | Per-topic rate, time since the last message and interval jitter show slow, irregular or silent devices at a glance | §4.2 |
| **Clean up the broker** | Find and clear retained messages left over from tests; read the broker's `$SYS` statistics and the MQTT 5 capabilities it reports | §4.2 |
| **Develop without hardware** | Simulate devices with realistic values (random walk, waves, GPS tracks, JSON templates), up to 1,000 instances from one definition | §4.4 |
| **Reproduce a field issue at your desk** | Record a customer's traffic, replay it to a test broker at original timing or faster, step message by message | §4.5 |
| **Catch the moment something goes wrong** | Start a recording when a condition matches, with minutes of pre-roll, or keep a flight recorder running that saves the last minutes before an alarm | §4.5 |
| **Share traffic safely** | Anonymize recordings (hash, mask, replace, remove or jitter values) before sending them to a supplier | §4.5 |
| **Test automatically** | Compare two recordings in CI, run simulations and recordings headless, fail a pipeline when devices break the topic documentation | §4.5, §4.7 |
| **Document an existing system** | Discover topics from the broker or a recording and get a first draft with payload formats, JSON schemas, intervals, QoS and retain; export as Markdown, HTML/PDF or AsyncAPI 3.0 | §4.6 |
| **Keep devices honest** | Check live traffic against the documentation and get findings: wrong format, schema violations, values out of range, silent topics | §4.6 |
| **Work with VDA 5050 robots** | Read every message in plain words, see the fleet on a map, check the protocol, test a fleet control against up to 200 simulated robots with injected faults | §4.8 |
| **Work with Sparkplug B** | Decode Protobuf payloads with metric names from the birth, see edge nodes and devices with live values, check session rules, simulate edge nodes | §4.9 |
| **Start in seconds** | Open the web app in the browser, or install the desktop app from the Microsoft Store. No account, no licence key | §4.10 |

---

## 4. Features

One block per feature area. Each block gives a draft **intro**, **what it does**, the **advantage**
for developers, and what to **show**. The complete, itemized list is in §5. Features marked
*(new in 2.0)* aren't on the current site yet.

### 4.1 Projects, connection and subscriptions

**Intro (draft):** *Keep one project per broker or scenario: test system, production, customer A.
Switch between them in two clicks.*

What it does:
- A **project** holds the broker (host, port, client id, user name, password), the protocol (MQTT
  3.1.1 or MQTT 5), TLS and WebSockets, clean start and session expiry (MQTT 5), the topic
  subscriptions with their colors, the simulation and the topic documentation.
- The start screen lists the six recent projects.
- **Client certificates** (mutual TLS) *(new in 2.0)*: CA certificate, client certificate, private
  key and key password per project. Desktop app only (TLS over TCP).
- **MQTT 5** *(new in 2.0)*: chosen per project; existing projects keep MQTT 3.1.1. Subscription
  options (No Local, Retain As Published, Retain Handling), publish properties, received
  properties, broker info.
- **Topic subscription panel:** each subscription is a chip in its own color; tap to pause or
  resume, ✕ to unsubscribe. Wildcards `+` and `#`.

Advantage: no retyping of broker settings and subscriptions; the same project also carries the
simulation and documentation of that system.

Show: the start screen with recent projects; the project settings dialog; the subscription panel
with colored chips.

### 4.2 TOPIC VIEWER

**Intro (draft):** *See what flows through your broker. Group messages by time, browse the topic
tree with rates per topic, or read them one by one. Filter by topic, payload or value, decode
binary payloads and see what changed since the last message.*

What it does:
- **View modes:** **Grouped** (by 1 s, 10 s, 1 min or 1 h), **Tree** (topic hierarchy with message
  counts) and **Sequential** (arrival order); **Fleet** and **Sparkplug** for the two industrial
  protocols *(new in 2.0, §4.8, §4.9)*.
- **Color-coded topics:** every message shows in its topic's color.
- **Message detail view:** received time, QoS, retain, payload size, message count of the topic,
  MQTT 5 properties; copy topic and payload, republish, clear a retained message, auto-select the
  newest message, show the last 1,000 messages of the topic.
- **Payload viewer:** text, JSON, numbers, JPG/PNG images, GPS coordinates (`lat,lon`) on a
  **map**, binary as hex. Numbers get a **chart** over time with min, max and average.
- **Filter** *(extended in 2.0)*: by topic (part of it or an MQTT filter like `plant/+/temp`), by
  payload text, or by condition (`$.status == "error"`, `plant/+/temp > 80`, with
  `== != > >= < <=`, `contains` and `~`). Regular expressions optional.
- **Payload decoders** *(new in 2.0)*: Hex, Base64, gzip/zlib, MessagePack, CBOR, chosen per topic.
- **Changes since the previous message** *(new in 2.0)*: changed JSON fields with old and new
  value ("was 21.4, now 21.9"), or a text diff.
- **Compare two messages** *(new in 2.0)*: pin one, select another, see every difference.
- **Edit and publish** *(new in 2.0)*: the publish dialog opens prefilled with the selected message.
- **Topic statistics** in the tree *(new in 2.0)*: messages and bytes per second, time since the
  last message, average interval ± jitter.
- **Tree context menu** *(new in 2.0)*: copy a branch as a wildcard filter, subscribe or
  unsubscribe a branch, open its retained messages.
- **Retained message manager** *(new in 2.0)*: scan a topic filter for retained messages, list
  them, clear the selected ones.
- **Broker statistics ($SYS)** and **broker info** *(new in 2.0)*: the broker's live `$SYS`
  values, and the MQTT 5 capabilities it reported on connect.
- **Publish dialog:** topic, payload, QoS, retain, a file up to 500 KB (e.g. an image), MQTT 5
  properties.

Advantage: you see structure, timing and content at once and get from "something is wrong" to
the one message that shows why, without writing a script. The retained message manager and $SYS
statistics use their own connection, so they don't disturb what you're watching.

Show: grouped view with the detail view and a chart; tree view with statistics and the context
menu; a JSON diff in the detail view; the map view of a GPS payload; the retained message manager.

### 4.3 MQTT 5 in detail

**Intro (draft):** *MQTT 5 and MQTT 3.1.1, chosen per project. See and send message properties,
set subscription options and check what your broker supports.*

- Subscription options: No Local, Retain As Published, Retain Handling.
- Publish properties: content type, message expiry, payload format (UTF-8), response topic,
  correlation data, user properties.
- Received properties in the detail view, including subscription ids.
- Broker info: maximum QoS, retain available, maximum packet size, receive maximum, topic alias
  maximum, server keep alive, wildcard subscriptions, subscription identifiers, shared
  subscriptions, assigned client id.

Advantage: test request/response patterns and message expiry, and find out quickly why a broker
refuses something.

Show: the publish dialog with MQTT 5 properties; the broker info dialog.

### 4.4 SIMULATOR *(new in 2.0)*

**Intro (draft):** *Test dashboards, backends and integrations before the hardware exists. Define
a device once, run it as 1,000 instances, and let MQTT Studio publish sensor values, GPS tracks,
images and JSON documents on a schedule.*

What it does:
- **Devices with instances:** one definition runs as up to 1,000 instances. Topic placeholders
  `{n}`, `{n:3}` (zero-padded) and `{device}`: `weather/{n}/temp` → `weather/1/temp` …
  `weather/10/temp`.
- **11 payload generators:** random string, random number, counter (e.g. `ORD-0001`), boolean,
  value list, random walk (drifts like a real sensor), wave (sine, square, triangle, sawtooth, with
  noise), timestamp, GPS track (wander or follow a route), random image (desktop), and template
  (JSON or text with named fields, each with its own generator).
- **Timing:** fixed or random interval per topic, from 50 ms; instances start staggered.
- **MQTT options:** QoS, retain, MQTT 5 properties.
- **Control:** start and stop everything, one device or one topic; live counts and last payload
  per topic; live preview while editing.
- **Rate guard:** shows the estimated message rate, warns above 100 msg/s (50 in the browser),
  refuses above 1,000 msg/s.
- **One click to watch** a simulated topic in the TOPIC VIEWER; **clear retained** after a test.
- **Recorded devices:** replay a recording as a device, e.g. one real machine as 20 machines.
- **VDA 5050 robots** and **Sparkplug B edge nodes** as device kinds (§4.8, §4.9).
- Saved in the project, runnable from the command line.

Advantage: frontend work without a backend, load tests, demo systems, alarm tests with values
that leave their range, many devices from one laptop.

Show: a multi-instance device running; the topic dialog with a template generator and its preview.

### 4.5 RECORDER *(new in 2.0)*

**Intro (draft):** *Capture a customer's traffic and reproduce the bug at your desk. Replay a
production day into a test system at 10× speed. Keep the last 10 minutes before every alarm.
Compare two runs and let your CI fail when the output changes.*

What it does:
- **Record** topic filters with exclusions over a connection of its own, with payload, QoS,
  retain, MQTT 5 properties and receive time, plus the retained state at the start. Reconnects on
  its own and marks the gap.
- **Start and stop by condition** (`plant/+/temp > 80`), with up to 10 minutes of pre-roll; stop
  after a duration, count or size.
- **Flight recorder:** keeps the last minutes in memory and saves them on a button press or when a
  condition matches.
- **Save as recording** from the TOPIC VIEWER; **REC indicator** in the app bar on every tab.
- **Recordings** are crash-safe `.mqttrec` files in a library folder; in the browser they're kept
  in browser storage (up to 100 MB each).
- **Playback:** a whole recording, one topic or a range, at 0.1× to 100×; pause, seek, step,
  loop, shorten long pauses; rewrite topics (`prod/` → `test/`); timing doesn't drift over hours.
- **Analysis:** OVERVIEW (rates, intervals, sizes, gaps per topic), TIMELINE (lanes per topic,
  zoom, bookmarks, connection-loss markers), MESSAGES (the topic viewer on recorded data), CHARTS
  (values and JSON fields over time, interval histogram, GPS tracks), COMPARE (two recordings by
  counts, payloads and timing).
- **Editing** without touching the original: trim, keep or rename topics, merge, split, and
  **anonymize** (hash, mask, replace, remove or jitter values).
- **Import and export:** JSON lines and CSV; import also reads `mosquitto_sub` output.

Advantage: field issues become reproducible, regression tests get real input data, and traffic can
be shared with partners without exposing sensitive values.

Show: the TIMELINE with bookmarks; the REC indicator in the app bar; the CHARTS tab; a COMPARE
result.

### 4.6 DOCUMENTATION *(new in 2.0)*

**Intro (draft):** *MQTT Studio listens to your broker and writes the first draft of your topic
documentation: every topic with its payload format, JSON schema, interval, QoS and retain flag.
You add the descriptions, and a check tells you when devices stop following them.*

What it does:
- **Discover** from a live broker, a recording or the TOPIC VIEWER's messages. Topics that differ
  only by an id become one **template**: `plant/{line}/m{machine}/temp`.
- **Review, never overwrite:** new, changed and no longer seen topics are listed; nothing you wrote
  is overwritten without asking.
- **Edit:** title, Markdown description, status, owner, tags, links, parameters, payload (format,
  unit, range, allowed values, JSON schema as a field table, examples), delivery (QoS, retain,
  interval, "stale after"), MQTT 5 properties, producers, consumers, sensitivity. Observed values
  show next to the documented ones.
- **Check** live traffic against the documentation: undocumented topics, wrong format, schema
  violations, values out of range, wrong QoS or retain, silent topics, deprecated topics in use,
  plus the VDA 5050 and Sparkplug B protocol rules.
- **Export:** Markdown, HTML (print to PDF, a clean handbook), **AsyncAPI 3.0** (YAML or JSON),
  JSON Schema bundle, CSV. Exports never contain passwords, certificates or the client id.
- **Import:** AsyncAPI 2.x and 3.x; ready-made VDA 5050 documentation from the official schemas.
- **Create a simulation** from documented topics.

Advantage: documentation that starts from the real system instead of an empty page, stays in sync
through the check, and can be handed over as a PDF or exchanged as AsyncAPI.

Show: the documentation tree with the editor and the observed panel; the discovery review; check
findings; an exported HTML page (optional).

### 4.7 Command line *(new in 2.0)*

**Intro (draft):** *Everything you set up in the app also runs headless: simulate devices on a
test server, record a night shift, replay into staging, and fail your pipeline when the output or
the topic documentation doesn't match.*

- Installed with the Windows desktop app; the command is `mqttstudio`.
- Commands: `projects`, `simulate`, `record`, `replay`, `recordings` (list, show, export, import,
  edit, compare) and `doc` (discover, check, export, import).
- Uses the projects saved in the app; broker settings can be overridden per run; passwords only
  from environment variables.
- JSON lines output (`-o json`) and documented exit codes for CI.
- App and CLI can run at the same time.
- Full manual: `doc/cli-manual.md`. **TO CONFIRM:** whether it is published on the site (it fits
  as a docs page).

Show (from the manual):

```
mqttstudio simulate -p "Demo factory" --duration 8h
mqttstudio record -p "Plant" -t "plant/#" --flight 15m --save-when "plant/+/alarm"
mqttstudio recordings compare reference.mqttrec run-42.mqttrec --ignore '$.ts'
mqttstudio doc export -p "Plant" --format asyncapi-yaml --out asyncapi.yaml
```

Plus a terminal screenshot of `simulate` or `record` output.

### 4.8 VDA 5050 *(new in 2.0)*

**Intro (draft):** *VDA 5050 is the open interface between AGVs, AMRs and their fleet control.
MQTT Studio reads every message in plain words, shows all robots on one map, checks the protocol,
and simulates a fleet to test against before the first robot arrives.*

Background for the agent: VDA 5050 is published by the German automotive association VDA and VDMA.
It runs on MQTT with JSON messages and a fixed topic layout
(`{interface}/{version}/{manufacturer}/{serialNumber}/{topic}`, topics `order`,
`instantActions`, `state`, `visualization`, `connection`, `factsheet`, and in 3.0 `zoneSet` and
`responses`). Version 2.x runs in most installed fleets; 3.0 was released in March 2026 and adds
freely navigating robots, zones and requests. Plants will run both for years.

- **Versions 2.0, 2.1 and 3.0**, also mixed in one plant; 1.1 is read where it matches 2.0.
  Recognized by topic and content, no setting needed.
- **Messages in plain words:** a one-line summary per message (robot, mode, driving, battery,
  order progress, errors); warnings and errors are marked.
- **Interpreted detail view:** status, errors, action states, order progress, nodes and edges, and
  for 3.0 paths, zones, requests and responses. One click back to the raw JSON.
- **Fleet view:** all robots in a table and on a 2D map per map id, with the selected robot's
  trail, order and, for 3.0, planned path and zones. Also on recordings.
- **Ready-made documentation** for 2.1 and 3.0 from the official JSON schemas.
- **Protocol check:** header vs. topic, header id gaps, timestamp skew, order structure and
  updates, duplicate action ids, missing state heartbeat, and for 3.0 requests and responses.
- **Simulated robots:** up to 200 robots per device that drive orders on a grid, wait for each
  other, charge, and for 3.0 respect zones and request permission. The simulator plays the fleet
  control too, so a broker is all you need.
- **Fault injection** per robot: errors, emergency stop, low battery, cancelled order, connection
  loss, and protocol faults that trigger their check rule.

Advantage: commission a fleet control against robots from several manufacturers, test a robot's
VDA 5050 implementation before the acceptance test, migrate from 2.x to 3.0, and answer "why did
robot 0001 stop?" in a running plant.

Limits (don't claim otherwise): MQTT Studio is not a fleet control. It doesn't plan routes, grant
zones or send orders to real robots (users can still publish any message by hand). The simulated
robots follow the simulator's own fleet control. No layout backgrounds (CAD, LIF files) on the map.

Show: the Fleet view with simulated robots and one robot's order; an interpreted state message; the
SIMULATOR with the Faults menu open.

### 4.9 Sparkplug B *(new in 2.0)*

**Intro (draft):** *Sparkplug B traffic is binary Protobuf with metrics sent by alias. MQTT Studio
decodes it, names every metric from the birth certificates, shows each edge node and device with
its live values, checks the session rules, and simulates edge nodes that follow the
specification.*

Background for the agent: Sparkplug B (Eclipse Foundation, specification 3.0, also ISO/IEC 20237)
is the most widely used MQTT convention in industrial IoT. Edge nodes and their devices announce
their metrics in a *birth* message, then send only changed values, by alias, as Protobuf. Without
decoding, a generic MQTT client shows hex, and even decoded data has no names.

- **Decoded messages:** all message types (NBIRTH, NDEATH, NDATA, NCMD, DBIRTH, DDEATH, DDATA,
  DCMD, host STATE), all data types including arrays, DataSets and Templates, compressed payloads.
- **Names from the birth:** metric names, data types and units from the last birth.
- **Request rebirth** with one click (and a confirmation); never sent on its own.
- **Sparkplug view:** host applications, groups, edge nodes and devices with online state, bdSeq,
  seq and seq gaps; all metrics with value, unit, type, age and number of changes; sort by changes
  to find stuck metrics, click to chart. Also on recordings.
- **Protocol check:** seq gaps, missing timestamps, bdSeq mismatches, data after death, device data
  without birth, duplicate aliases, unknown metrics, changed data types.
- **Simulated edge nodes:** up to 20 edge nodes with up to 20 devices and 200 metrics each, with
  the NDEATH as real last will, data by exception, rebirth on request, writable metrics; optionally
  the primary host too, so a full system runs with only a broker.
- **Fault injection** per edge node: dropped connection, restart, devices offline, and protocol
  faults that trigger their check rule.

Advantage: commission edge gateways and PLC connections, test a SCADA, MES or historian without a
PLC, and track down missing or stale metrics.

Limits (don't claim otherwise): no writing of metrics from a command editor (users can publish by
hand), discovery documents Sparkplug topics without their metrics, Sparkplug 2.2 is read but not
simulated, no store-and-forward in the simulator.

Trademark note: "Sparkplug" is a trademark of the Eclipse Foundation. **TO CONFIRM:** whether the
site needs a trademark notice for Sparkplug and VDA 5050.

Show: the Sparkplug view with edge nodes, devices and the metric table; a decoded message in the
detail view.

### 4.10 Desktop app and browser

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

The web app is the quickest way to look around; the desktop app suits heavy traffic, recordings on
disk, client certificates and the command line. The browser version shows the same hint.

---

## 5. Complete feature list

The full list of what MQTT Studio 2.0 does, area by area, taken from the app itself. §4 explains
the features; this section is the reference for feature pages, comparison tables, the download page
and the release notes. Use it to check that a page claims nothing the app doesn't do and leaves out
nothing important.

Marks: **(desktop)** works in the Windows desktop app only, **(MQTT 5)** works only in projects
set to MQTT 5 (the controls stay visible but disabled for MQTT 3.1.1 projects). Everything without
a mark works in both the desktop app and the browser. Everything is free.

### 5.1 Main window and general

- One window with four tabs: **TOPIC VIEWER**, **SIMULATOR**, **RECORDER**, **DOCUMENTATION**.
- App bar: menu, name of the open project, the tabs, the red REC indicator while a recording runs,
  broker statistics ($SYS) button, broker info button, CONNECT button.
- CONNECT button names its action: red **CONNECT**, green **DISCONNECT**, **CONNECTING** with a
  spinner; the tooltip shows the broker address. Without an open project it offers to create one.
- Menu: New Project, Open Project, Save Project, Close Project, Project Settings, About MQTT
  Studio.
- Start screen (no project open): recent projects, NEW PROJECT and OPEN PROJECT.
- Error messages name the cause: the broker's reason when it closes the connection or refuses a
  subscription.
- Every dialog: Esc cancels, Enter submits.
- Browser only: a performance hint that suggests the desktop app for high message rates, with "Do
  not show again".
- Optional newsletter sign-up (email, first name, last name, company, privacy consent under the
  GDPR), with "Later" and "Do not show again".
- English user interface.

### 5.2 Projects and connection

- **Projects** bundle everything for one scenario: broker settings, subscriptions with their
  colors, the simulation and the topic documentation. Recordings are linked to the project they
  were made with.
- New, open, save, close, edit settings. Closing a project with unsaved changes asks to save.
  Closing a project or the app during a recording asks first (the recording is saved).
- **Recent projects:** the six last used projects as cards with their last-used time; one click
  opens a project.
- Stored locally on the computer (in the browser's storage for the web app). Nothing is uploaded.
- **Broker settings:** project name, broker host, port, client id, user name, password (with a
  show-password toggle).
- **Protocol** per project: MQTT 3.1.1 or MQTT 5. Old projects open as MQTT 3.1.1.
- **Transport:** TCP, TLS ("Use SSL"), WebSockets (`ws://`, `wss://`). The browser version uses
  WebSockets only.
- **Clean start** and **session expiry** (MQTT 5).
- **Client certificates (mutual TLS)** (desktop): CA certificate, client certificate, private key
  and key password, chosen as files.
- **Broker info** dialog: protocol, reason code and reason string, session present, session expiry,
  assigned client id, maximum QoS, retain available, maximum packet size, receive maximum, topic
  alias maximum, server keep alive, wildcard subscriptions, subscription identifiers, shared
  subscriptions, response information, server reference (the MQTT 5 values as the broker reported
  them on connect).
- **Broker statistics ($SYS)**, live, over a connection of its own: version, uptime, connected
  clients, clients in total, most clients at once, messages and bytes received and sent (1-minute
  average), subscriptions, retained messages, stored messages, heap in use. The summary follows
  Mosquitto's topics; the full list of all `$SYS` topics with a filter works for any broker. Says
  clearly when a broker publishes no `$SYS` topics.

### 5.3 Topic subscriptions

- **Add topic** dialog: topic or topic filter (wildcards `+` and `#`), QoS (at most once, at least
  once, exactly once), color; SUBSCRIBE or SUBSCRIBE & NEW to add several in a row. Invalid topics
  and duplicate subscriptions are refused.
- **MQTT 5 subscription options** (MQTT 5): No Local, Retain As Published, Retain Handling (send
  retained on subscribe / only for new subscriptions / don't send).
- **Topic chips** in the subscription panel, one per subscription in its color: tap to pause or
  resume, ✕ to unsubscribe. A paused topic turns grey.
- 11 topic colors; a new subscription gets a random one, changeable.
- Subscriptions are saved with the project and subscribed again on connect.

### 5.4 TOPIC VIEWER: message views

- **Start, pause and clear** the message stream.
- **Five view modes:**
  - **Grouped:** messages grouped by time period (1 s, 10 s, 1 min, 1 h) as colored chips.
  - **Tree:** the topic hierarchy with message counts; expand all, collapse all, topic
    statistics, context menu (§5.6). Documented topic titles show as tooltips.
  - **Sequential:** every message in arrival order.
  - **Fleet:** VDA 5050 robots in a table and on a map (§5.15). Available once a VDA 5050 robot
    was received.
  - **Sparkplug:** Sparkplug B hosts, edge nodes, devices and metrics (§5.16). Available once a
    Sparkplug B message was received.
- Each message shows in its topic's color; new messages briefly "glow".
- VDA 5050 and Sparkplug B messages show a **one-line summary** in the sequential and tree views,
  and a tooltip and warning/error marker on grouped chips. A topic can be switched to the raw
  payload for the session.
- Keeps up to 100,000 messages or 200 MB, then drops the oldest; the detail view says when
  messages of a topic were dropped.
- **Save as recording:** turns the messages the topic viewer holds into a recording.
- **Retained messages** button (§5.7) and **PUBLISH** button (§5.8) in the command bar.

### 5.5 TOPIC VIEWER: filter

- Filter field in the command bar with three modes:
  - **Topic:** part of the topic, or an MQTT topic filter with `+` and `#` (`plant/+/temp`).
  - **Payload:** text in the payload.
  - **Condition:** `[<topic filter>] [<JSON path>] [<operator> <value>]` with `== != > >= < <=`,
    `contains` and `~` (regular expression), e.g. `$.status == "error"` or `plant/+/temp > 80`.
    Same syntax as the recorder's triggers.
- Regular expression toggle (`.*`) for every mode; case is ignored.
- In the tree view, payload and condition filters test each topic's last message.
- Invalid filters are marked with an error icon; one click clears the filter.

### 5.6 TOPIC VIEWER: tree tools

- **Topic statistics** per topic: messages and bytes per second (over the last 10 s), time since
  the last message, average interval ± jitter. Retained messages sent on subscribe don't count as
  intervals.
- **Context menu** on every branch: copy the topic or the branch as a wildcard filter, subscribe
  to the branch, unsubscribe from one or all subscriptions in the branch, expand or collapse this
  branch, expand or collapse all, retained messages in this branch, request a Sparkplug rebirth of
  one or all edge nodes of a group.

### 5.7 Retained message manager

- Scans a topic filter for retained messages on the broker, over a connection of its own (the
  topic viewer's subscriptions stay as they are).
- Shows the count while scanning, then a list with topic, payload and size.
- Clears the selected retained messages, after a confirmation.
- Opens from the command bar or from a branch of the tree.

### 5.8 Publishing

- **Publish dialog:** topic (no wildcards), payload, QoS, retain.
- **Publish a file** up to 500 KB, e.g. an image.
- **MQTT 5 properties** (MQTT 5): content type, message expiry, UTF-8 payload format, response
  topic, correlation data, any number of user properties.
- **Re-publish** a received message unchanged, or **edit and publish**: the dialog opens prefilled
  with the selected message.
- **Clear a retained message** from the detail view.

### 5.9 Message detail view

- Opens next to the messages when a message is selected.
- **Metadata:** topic (copy button), received time, QoS, retain, payload size, message count of the
  topic.
- **MQTT 5 properties** of received messages (MQTT 5): content type, response topic, correlation
  data, message expiry, payload format, user properties, subscription ids.
- **Payload viewer** by content:
  - text and JSON (formatted, copyable)
  - numbers (large) with a **chart** over time with min, max and average
  - images (JPG, PNG)
  - GPS positions (`lat,lon`) on a **map**
  - binary payloads as a hex view
  - VDA 5050 and Sparkplug B messages **interpreted** (§5.15, §5.16), with a switch to the raw
    payload and a dropdown to chart a value of the message
  - Note: dates have no viewer of their own, they show as text. Don't list "dates" as a payload
    type (the current site does).
- **Payload decoders**, chosen per topic for the session: Auto, Text, Hex, Base64, gzip/zlib,
  MessagePack, CBOR. A decoded payload works like any other (JSON viewer, chart, filter).
- **Changes since the previous message** of the topic: changed JSON fields with old and new value
  ("was 21.4, now 21.9"), added and removed fields, or a text diff.
- **Compare two messages:** pin one message, select another one of any topic; the dialog says
  whether the payloads are equal and lists the differences.
- **Actions:** copy topic, copy payload, re-publish, edit and publish, clear retained, **AUTOSELECT**
  (follow the newest message), **show the last 1,000** messages of the topic, request a Sparkplug
  rebirth.

### 5.10 SIMULATOR: devices and topics

- **Four device kinds:** generated device, recorded device, VDA 5050 robots, Sparkplug edge nodes.
- **Generated device:** name, **instances** (1 to 1,000), number of the first instance, a preview
  of the topics it publishes to.
- **Topic placeholders:** `{n}` (instance number), `{n:3}` (zero-padded, up to 12 digits),
  `{device}` (device name). They also work in user property values and templates.
- **Topic settings:** topic, generator, **interval** (fixed, or random between two values; at least
  50 ms), QoS, retain, MQTT 5 properties (content type, set automatically when empty; message
  expiry; user properties).
- **Live preview:** GENERATE shows sample payloads for chosen instances, with a JSON check.
- **Validation** before start: empty or wildcard topics, missing `{n}` with several instances,
  intervals too short, unknown template fields, GPS routes with fewer than 2 points, and more.
- **Control:** start and stop everything, one device or one topic; edit, duplicate and delete
  devices and topics. Saving a running topic restarts it.
- **Live status** per topic: running, stopped or error; messages sent; last payload.
- **Rate guard:** shows the estimated rate in msg/s, warns above 100 msg/s (50 in the browser) that
  the topic viewer may lag, refuses to start above 1,000 msg/s.
- **Subscribe in one click:** subscribe to a simulated topic in the TOPIC VIEWER.
- **CLEAR RETAINED:** removes the retained messages the simulation left on the broker.
- Instances start staggered; the simulation stops with a message when the connection is lost.
- Saved in the project; runs from the command line too (§5.19).
- Browser: timers slow down in background tabs, the app says so.

### 5.11 SIMULATOR: payload generators

| Generator | Settings |
|---|---|
| Random string | min and max length, characters, prefix, postfix |
| Random number | min, max, decimals, prefix, postfix |
| Counter | start, step, decimals, reset after, prefix, postfix (e.g. `ORD-0001`) |
| Boolean | probability of true, texts for true and false (`true/false`, `1/0`, `ON/OFF`, …) |
| Value list | values, one per line, picked at random or in order |
| Random walk | start, min, max, volatility, decimals, prefix, postfix: drifts like a real sensor |
| Wave | sine, square, triangle or sawtooth; offset, amplitude, period, phase, noise, decimals, prefix, postfix |
| Timestamp | ISO 8601, epoch milliseconds, epoch seconds or a custom pattern; UTC or local time |
| GPS track | **wander** around a center (radius, turn rate, speed) or follow a **route** of waypoints; output `lat,lon` or JSON |
| Random image (desktop) | JPG/PNG files from a folder, by extension, at random or in order |
| Template | JSON or any text with named fields (`{{name}}`, `{{name.part}}`), each field with its own generator; optional JSON check |

### 5.12 SIMULATOR: recorded devices

- A device that **plays a recording** instead of generating values.
- Choose the recording and the topics to play; playback options as in the recorder (speed, loop,
  range, gaps, topic remapping, retain, QoS).
- **Instances:** one recording played as many devices, each with its own topics (remapping with
  `{n}`, e.g. `plant/` → `plant/{n}/`).
- Instances start staggered, all at once, or at a random position in the recording.
- **ADD TO SIMULATION** in the RECORDER creates such a device in one click.

### 5.13 RECORDER: recording

- **RECORD** dialog: name, **topic filters** with QoS, each to **include** or **exclude**;
  suggestions from the subscribed topics and the last filters. Hints when a filter is covered by
  another one, or when `$SYS` topics need their own filter.
- Records over a **connection of its own**, independent of the CONNECT button; **reconnects** on
  its own and marks the gap.
- Stores each message with payload, QoS, retain flag, MQTT 5 properties and receive time; the
  retained messages at the start as a **retained snapshot** (optional).
- **Stop** after a duration, a number of messages or a size; optional maximum payload size (longer
  payloads are cut).
- **Start and stop by condition** (`plant/+/temp > 80`, `plant/line1/state $.status == "error"`),
  with **pre-roll** (up to 10 minutes from before the start trigger) and **post-roll**.
- **Flight recorder** mode: keeps a window (e.g. the last 10 minutes) in memory with a memory
  limit, and saves it as a recording on **SAVE** or when the save condition matches, with
  post-roll and an optional maximum number of saves.
- **Bookmarks** while recording, e.g. when a device is switched or an error shows.
- **REC indicator** in the app bar on every tab: elapsed time, messages, size; also WAITING FOR
  TRIGGER, FLIGHT, CONNECTING and RECONNECTING states. A click opens the recorder.
- **Save as recording** from the TOPIC VIEWER.

### 5.14 RECORDER: library, playback, analysis and editing

**Library**
- Recordings are `.mqttrec` files: crash-safe (an interrupted recording is recovered and marked
  "Recovered"), with a summary and an index for fast seeking.
- Library folder, by default `Documents\MQTT Studio\Recordings`, changeable (desktop); FOLDER opens
  it in Explorer. The command line uses the same folder.
- Browser: recordings are kept in the browser's storage, up to 100 MB each; export them to keep
  them elsewhere.
- Show the recordings of the open project or of all projects; assign a recording to a project.
- Name and notes per recording; delete.

**Playback** (on the main connection)
- Play everything, chosen topics or a range; pause, resume, stop, **step** one message at a time.
- Speed 0.1× to 100×, loop, play from/to an offset, **shorten gaps** longer than a set time.
- **Topic remapping** (`prod/` → `test/`), retain as recorded / never / always, QoS as recorded or
  fixed, retained snapshot published first or skipped, MQTT 5 properties republished or not.
- Shows the estimated and peak rate before playing, progress, lag and loop count while playing.
- Timing doesn't drift, also over hours. Warns when a running recording would record the playback.

**Analysis tabs**
- **OVERVIEW:** per topic: messages, rate, interval, value range, payload type, average size,
  duplicates, gaps, retained; connection gaps, bookmarks, notes.
- **TIMELINE:** one lane per topic, zoom and pan, select a range (used by playback, MESSAGES and
  CHARTS), bookmarks (add, rename, delete, jump to), gaps with an adjustable threshold and
  connection-loss markers, duplicates (same payload as before, or again within 100 ms).
- **MESSAGES:** the topic viewer's grouped, tree and sequential views, filter and detail view on
  the recorded messages; also the Fleet and Sparkplug views for recordings that contain them.
- **CHARTS:** a number payload or any JSON path over time with min, max and average; histogram of
  the time between messages; GPS positions as a track on the map.
- **COMPARE:** two recordings topic by topic: message counts (with tolerance), payloads in order
  (JSON compared by content, ignored JSON paths, number tolerance), timing (median interval, with
  tolerance), topic mapping between the two, limited to a range. Shows the first difference per
  topic and the field where it differs.

**Editing** (each edit makes a new recording, the original stays)
- Trim to the selected range, keep the selected topics, rename topics by prefix, merge with other
  recordings, split (at bookmarks, at the playhead, one recording per topic).
- **Anonymize** with rules per topic filter: target a JSON field, the whole payload or a topic
  level; hash, mask with `*`, fixed value, remove, or jitter numbers by ± percent. Optionally also
  user properties and correlation data. Rules can be saved and loaded.
- **Discover documentation** from a recording (§5.17).

**Import and export**
- Export as `.mqttrec`, JSON lines or CSV (with chosen JSON paths as extra columns), all topics or
  the ones selected, all or the selected range.
- Import `.mqttrec`, JSON lines, CSV and `mosquitto_sub` output (with times via
  `-F "%U %t %p"`, or `-v` without times and a set interval).

### 5.15 VDA 5050 (AGVs, AMRs and fleet controls)

- **Versions** 2.0, 2.1 and 3.0, mixed in one plant; 1.1 read where it matches 2.0. Recognized
  automatically by topic and content.
- **Topics** `order`, `instantActions`, `state`, `visualization`, `connection`, `factsheet`, and for
  3.0 `zoneSet` and `responses`.
- **One-line summaries** in the topic viewer; messages with robot warnings or errors are marked.
- **Interpreted detail view:** status, errors, action states, order progress, nodes and edges;
  for 3.0 paths, zones, requests and responses. Switch to the raw JSON in one click.
- **Charts** of message values: battery charge, velocity, position.
- **Fleet view:**
  - table: robot, version, connection, mode, driving, battery, order and node, errors, open
    requests, age of the last state;
  - 2D map per map id with a grid and a legend: robots colored by state (driving, standing,
    warning, error, offline), the selected robot's trail, its order (released and not yet
    released, nodes reached and ahead), for 3.0 the planned path, the next meters and the zones;
    fit to view.
  - Works on live traffic and on recordings.
- **Ready-made documentation** for 2.1 and 3.0 from the official JSON schemas, with a chosen
  interface name; suggested by discovery when it finds VDA 5050 topics.
- **Protocol check:** header differs from the topic, header ids out of order or with gaps,
  timestamp skew, order structure, order updates and their content, duplicate action ids, missing
  state heartbeat; for 3.0 responses without request, unanswered requests, visualization ahead of
  state.
- **Simulated robots** (SIMULATOR):
  - up to 200 robots per device, VDA 5050 2.x or 3.0; interface name, manufacturer, serial number
    with `{n}`;
  - grid layout (columns, rows, spacing, charging stations, map id);
  - orders with a set number of nodes and horizon nodes, actions at nodes with durations, idle
    times;
  - speed, battery use and charging rate; robots charge when low;
  - state heartbeat, visualization rate, factsheet, zone set, release-zone requests (3.0);
  - random faults per hour, and a seed for repeatable runs;
  - the simulator plays the fleet control, so a broker is all that's needed;
  - live status per robot: driving, idle, waiting and why (not connected, paused, safety stop,
    error, running an action, battery empty), current order and node, open requests.
- **Fault injection** per robot: warning, urgent, critical and fatal errors, emergency stop, field
  violation, pause, low battery, cancel order, clear errors; connection broken, offline,
  hibernate, reconnect; protocol faults (skip header ids, clock 10 s ahead, wrong serial number,
  order with a sequence gap, order update with a lower id, response without request, unanswered
  request). Each protocol fault triggers its check rule.

### 5.16 Sparkplug B (industrial IoT)

- **Decodes** all message types (NBIRTH, NDEATH, NDATA, NCMD, DBIRTH, DDEATH, DDATA, DCMD, host
  STATE), all data types including arrays, DataSets and Templates, and compressed payloads (GZIP,
  DEFLATE).
- **Metric names, data types and units from the last birth**; without a birth, metrics show by
  alias with a warning.
- **One-line summaries** in the topic viewer and an interpreted detail view; charts of numeric and
  boolean metrics by name.
- **Request rebirth** (NCMD) for one edge node or all edge nodes of a group, from the detail view,
  the tree menu and the Sparkplug view, always after a confirmation ("don't ask again in this
  session" is possible). Never sent automatically.
- **Sparkplug view:** host applications, groups, edge nodes and devices with online/offline state
  and since when, bdSeq, seq and sequence gaps; for the selected node or device every metric with
  name, value, unit, type, last update, number of changes and properties; filter and sort the
  metrics, click a metric to chart it, jump to the last message. Works on live traffic and on
  recordings.
- **Protocol check:** payload isn't Sparkplug B, missing or skipped seq, missing timestamp,
  missing or mismatched bdSeq, data after death, device data without birth, birth metric without
  data type, duplicate aliases, unknown metrics, changed data types.
- **Simulated edge nodes** (SIMULATOR):
  - up to 20 edge nodes per device, up to 20 devices per node (a device can repeat with a number),
    up to 200 metrics each; group id and edge node id with `{n}`;
  - metrics with name (folders with `/`), data type, unit, deadband, writable flag, and a
    generator for the values;
  - Sparkplug 3.0 behavior: one connection per edge node with the NDEATH as last will, births,
    data by exception with a scan interval, seq and bdSeq, rebirth on request, writes by
    NCMD/DCMD, aliases, optional GZIP compression;
  - optional primary host: wait for a real host application, or let the simulator play the host
    (STATE);
  - live status per edge node: connecting, waiting for the host, online, reconnecting; devices
    online.
- **Fault injection** per edge node: drop connection (the broker sends the will), restart, devices
  offline; protocol faults: skip a seq, unknown metric, wrong data type, data after death, device
  data without birth, death with a wrong bdSeq, no timestamps, non-Sparkplug payload. The menu
  says which check rule each fault triggers.

### 5.17 DOCUMENTATION: documenting topics

- **Topic tree** of documented topics and namespaces, with counts of topics and undocumented ones,
  search, and a filter (all, undocumented, draft, stable, deprecated, new, changed, not seen, with
  findings).
- **Topic templates** with parameters, e.g. `plant/{line}/m{machine}/temp`; each parameter can have
  a pattern (regular expression).
- Add a topic or namespace, rename or move (with everything below), duplicate, switch between
  topic and namespace, delete, delete all topics; copy details from another topic when adding.
- **Editor** per topic: title, status (draft, stable, deprecated), owner, replaced by, tags,
  description in **Markdown**, links, parameters;
  - payload: format (JSON, number, boolean, text, binary, image, GNSS coordinates, empty),
    encoding, unit, minimum, maximum, allowed values, examples with notes;
  - **JSON schema as a field table** (field, type, unit, range or values, required, description),
    or edited as JSON;
  - delivery: QoS, retain (never, always, sometimes), interval (periodic, on event, on change,
    both), nominal interval, stale after, carries a last will;
  - MQTT 5: content type, message expiry, UTF-8 payload format, response topic, correlation data,
    user properties with examples;
  - access: producers, consumers, sensitivity (none, personal data, confidential, safety relevant),
    access notes.
- **Observed values** next to the documented ones: messages, instances, rate, interval and its
  spread, payload size, value range, retained, user properties, last payload.
- Overview page with the documentation's title, revision and contents.

### 5.18 DOCUMENTATION: discover, check, import and export

- **Discover** from a live broker (connection of its own, never publishes), a recording or the
  TOPIC VIEWER's messages; topic filters; stop after minutes, a number of messages or by hand.
  Options: detect templates, infer JSON schemas, keep example payloads, ignore `$SYS`.
- **Review** before anything changes: proposed templates, new topics, changed topics (documented
  vs. observed, adopt per value), topics not seen. Edited fields are never overwritten without
  asking. Topics can be ignored for future discoveries. REVIEW reopens the last discovery.
- **Check** live messages against the documentation (connection of its own), for everything or one
  branch. **Findings** panel: topic, rule, count, last time, detail; export and clear. Rules:
  undocumented topic, wrong format, schema violation, out of range, value not allowed, parameter
  mismatch, different QoS, different retain, no message in time (stale), deprecated topic in use,
  different MQTT 5 properties, plus the VDA 5050 and Sparkplug B protocol rules.
- **Export:** Markdown, HTML (print as PDF), AsyncAPI 3.0 (YAML, JSON), JSON Schema bundle, CSV;
  the whole documentation or one branch; with or without examples, observed statistics and the
  broker address. Credentials, certificates and the client id are never exported. The HTML
  export renders Markdown, links topic references and prints cleanly.
- **Import** AsyncAPI 2.x and 3.x (YAML or JSON): merge (new, changed, unchanged, conflicts shown)
  or replace everything. **VDA 5050 documentation** (2.1 or 3.0) in one click.
- **Create simulation** from documented topics: simulated devices with fitting generators.
- Saved in the project.

### 5.19 Command line (desktop)

- `mqttstudio` command, installed with the Windows desktop app; app and command line can run at
  the same time (each run gets its own client id).
- Commands:
  - `projects list`, `projects show`
  - `simulate`: run a project's simulation or some devices; duration, rate limit, seed for
    repeatable payloads, dry run, reconnect, clear retained at the end. Includes recorded devices,
    VDA 5050 robots and Sparkplug edge nodes (faults only in the app).
  - `record`: topic filters with QoS, exclusions, start/stop conditions with pre- and post-roll,
    flight recorder, limits, output file or the library.
  - `replay`: speed, loop, range, gap compression, topic remapping, many instances, retained
    snapshot, retain and QoS overrides.
  - `recordings list | show | export | import | edit | compare` (compare writes a JSON report).
  - `doc discover | check | export | import` (`--preset vda5050-v2|vda5050-v3`).
- Broker settings can be overridden per run (host or WebSocket URL, port, client id, user name,
  TLS, CA, client certificate and key). Passwords only from environment variables.
- Output as text or JSON lines (`-o json`), quiet and verbose modes, documented exit codes (e.g. 8
  when a comparison or a check fails), so CI pipelines can fail on differences.
- Ctrl+C stops cleanly and saves what was recorded.
- Full manual: `doc/cli-manual.md`.

### 5.20 Not included (don't claim)

- No mobile app or mobile layout; no dark theme; English only.
- No cloud account, sync or sharing of projects.
- Not a broker, not a fleet control, not a SCADA/host application.
- No metric writing from a command editor for Sparkplug (publish by hand instead); Sparkplug 2.2 is
  read but not simulated; no store-and-forward in the simulator.
- No layout backgrounds (CAD, LIF) on the VDA 5050 map.
- In the browser: no TCP/TLS connections without WebSockets, no client certificates, no random
  image generator, no command line.

---

## 6. Suggested site structure

A proposal; the designer may change it.

1. **Home**
   - Hero: name, one-line description (§2), a screenshot of the TOPIC VIEWER, buttons "Download for
     Windows" (Microsoft Store) and "Open in browser". Small badges: Free · MQTT 5 · Windows and
     web.
   - "What you can do with it": the advantages of §3 as short blocks, each linking to its feature.
   - Feature areas with one screenshot each: Watch (TOPIC VIEWER), Simulate, Record, Document,
     plus strips for "Automate" (CLI) and "Industrial protocols" (VDA 5050, Sparkplug B).
   - FAQ (§7).
   - Who builds MQTT Studio: one line about Sarix with a link to www.sarix.eu; contact.
2. **Feature pages** (or long sections): Topic viewer, Simulator, Recorder, Documentation, Command
   line, VDA 5050, Sparkplug B, each with the advantage, what it does, screenshots and examples
   (§4). VDA 5050 and Sparkplug B deserve pages of their own: they address specific audiences who
   search for these terms.
3. **Download:** Microsoft Store, web app, the desktop/browser table (§4.10), system requirements
   (**TO CONFIRM**: minimum Windows version), release notes as a web page instead of only a PDF.
4. **Docs** (optional): CLI manual, getting started.
5. **Release notes** (§10).
6. **Legal:** Terms of Use / privacy, EULA, imprint (§9).

No pricing page, no sign-up before download.

SEO: real page titles and meta descriptions, e.g. "MQTT Studio – MQTT 5 client, simulator and
recorder for Windows and the browser". Keywords that fit: MQTT client, MQTT 5, MQTT explorer, MQTT
simulator, MQTT recorder, MQTT replay, AsyncAPI, IoT testing, VDA 5050, VDA 5050 simulator, AGV,
AMR, fleet control, Sparkplug B, Sparkplug decoder, Sparkplug edge node simulator, IIoT, MQTT
retained messages, MQTT $SYS, MQTT payload decoder, MessagePack, CBOR.

---

## 7. FAQ

**What is MQTT Studio for?**
Watching, publishing, simulating, recording, replaying and documenting MQTT traffic while you
build, test or support an MQTT-based system. It also reads VDA 5050 and Sparkplug B.

**What does it cost?**
Nothing. MQTT Studio is free for personal and commercial use under the EULA. There is no paid
edition, no licence key and no account.

**Why is it free?**
Sarix develops MQTT Studio as a tool for developers and gives it away.

**Who is behind MQTT Studio?**
Sarix, which builds custom software for connected devices and machines (www.sarix.eu).
**TO CONFIRM:** whether Babylon and Redpin are still mentioned (the current site links Babylon, a
localization tool, to redpin.eu).

**Does it support MQTT 5?**
Yes, and MQTT 3.1.1, chosen per project.

**Desktop or browser, what's the difference?**
See §4.10.

**Does MQTT Studio support VDA 5050?**
Yes, versions 2.0, 2.1 and 3.0: interpreted messages, a fleet view, ready-made documentation, a
protocol check and simulated robots (§4.8).

**Does MQTT Studio decode Sparkplug B?**
Yes: decoded payloads with metric names from the birth, rebirth requests, a Sparkplug view, a
protocol check and simulated edge nodes (§4.9).

**Can I test my fleet control or SCADA without real hardware?**
Yes, with simulated VDA 5050 robots or Sparkplug edge nodes, including injected faults.

**Can I run it in CI or on a server?**
Yes, with the `mqttstudio` command line (Windows).

**Where are my projects and recordings stored?**
Locally on your computer, or in your browser. Nothing is uploaded.

**Can I export my topic documentation?**
Yes: Markdown, HTML/PDF, AsyncAPI 3.0, JSON Schema, CSV.

**How do I report a bug or suggest a feature?**
By email (support address, see §9). Bug reports, feature requests and suggestions are welcome.

**Which language is MQTT Studio developed in?**
Flutter, Google's open-source UI toolkit, with one code base for desktop and web.

---

## 8. Screenshots and visuals needed

Screenshots carry this site: each feature should be shown, not described at length.

The app is a dense, desktop-first tool; design for a wide window (~1500 px). Light theme only:
dark grey app bar, deep red accent (`#B71C1C`), topic chips in strong colors (indigo, blue, pink,
amber, deep purple, orange, brown, green, teal, lime). The connect button names its action: red
with CONNECT while disconnected, green with DISCONNECT while connected, CONNECTING with a spinner
in between.

Existing (version 1.x UI, still representative of the TOPIC VIEWER): `product/screenshots/`
(`grouped_chart.png`, `grouped_img.png`, `sequiential_chart.png`, `sequiential_img.png`,
`tree_chart.png`, `tree_img.png`). `CI/` holds app icons and logos. There are **no screenshots of
the 2.0 features yet**.

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
11. The start screen with recent projects.
12. Documentation check findings with VDA 5050 or Sparkplug protocol rules (optional).
13. An exported HTML documentation page or AsyncAPI file (optional).

App design system (tokens, colors, components of the app UI):
https://claude.ai/artifact/M1uENVXPQJf74mB86VB5yu (private Claude artifact; the agent may not have
access, ask the owner for an export if needed).

---

## 9. Company, contact and legal (needs updating)

The current site (and its legal pages) still name **Redpin**. Since version 2.0 the app, the EULA
and the package's publisher name say **Sarix**. Everything below is **TO CONFIRM** before
publishing.

| Item | Current site | New |
|---|---|---|
| Publisher / copyright | "Copyright © 2026 by Redpin", Redpin logo | Sarix. **TO CONFIRM:** legal company name, vector logo |
| Company website | www.redpin.eu (Babylon link) | www.sarix.eu (linked from the app since 2.0) |
| Address | via Buozzi 12, 39100 Bolzano (BZ), Italy | **TO CONFIRM** |
| General email | info@redpin.eu | info@sarix.eu (used in the app since 2.0) |
| Support email | support@redpin.eu | **TO CONFIRM** |
| Map link | https://goo.gl/maps/u8oeH8PgKp9U2gf37 | **TO CONFIRM** |
| Babylon link (FAQ) | https://www.redpin.eu/ | **TO CONFIRM** keep or remove |

**Contact.** Two different reasons to get in touch: questions and bug reports about the tool
(support address), and general inquiries to Sarix (info@sarix.eu). The contact section can show
both.

**Terms of Use page.** Current content: copyright (all site content is the property of Redpin),
privacy (refers to purchases on redpin.eu, with name, address and credit card data), cookies (no
profiling or social cookies; technical cookies for traffic analysis), no spyware or adware (the
app has no ads, no bundled programs, never sends personal data without the user's knowledge),
disclaimer of warranties. Needs an update for Sarix, and **TO CONFIRM:**
- the purchase/credit card paragraph: nothing is sold, so it should go;
- analytics: the app uses Piwik for usage statistics (which tool the site uses is unknown); the
  app's optional newsletter sign-up asks for email, name and company with consent under the GDPR.
  The privacy text should cover both. A privacy policy page is linked from the newsletter dialog;
  **TO CONFIRM** its URL.

**EULA page.** The text in the repository (`src/DesktopSetup/eula.txt`) names Sarix as the
licensor; the site still shows Redpin. Use the repository text. Note: clause 2 ("Translator
edition") and "number of user accounts" are leftovers from Babylon; **TO CONFIRM** whether the
EULA gets revised.

**Imprint:** the current site has none. **TO CONFIRM** whether one is needed (company details, VAT
number).

---

## 10. Release notes

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
- Developed by Sarix

---

## 11. Current site inventory

Site captured on 2026-10-25 and checked again on 2026-11-01: no changes, the pages were last
modified in November 2023. English only (`/de/` and `/it/` return 404). Pages live under `/en/`.

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

**Current home page copy** (as on 2026-10-25, for reference only; don't reuse its marketing tone):
- Hero: "MQTTStudio is a practical MQTT client designed for developers to efficiently create,
  test, and manage MQTT-based applications, enhancing their development and support workflows."
  Buttons: "Download Client", "Use in browser".
- Features (titles in site order): Grouped Messages View, Hierarchical Messages View, Projects,
  Topic subscription panel, Messages viewer, Color coded topics, Message detail view, Payload
  viewer, Topic filter, Chart view. All are covered in §4.1 and §4.2. The current site also claims
  a date viewer, which the app doesn't have (§5.9).
- FAQ: "What is MQTT Studio for?", "What is the licensing model?", "Who is behind MQTT Studio?",
  "How do I submit a feature request or report a bug?", "How does MQTT Studio make money?" (answer:
  it doesn't, the free version stays free without ads, commercial features are planned), "Which
  language is MQTT Studio developed in?". The new answers are in §7; the question about making
  money and the planned commercial features are dropped.
- The app's About dialog has a marketing text ("Unlock the full potential of MQTT development …");
  don't use it on the site.
