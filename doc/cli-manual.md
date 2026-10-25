# MQTT Studio command line (CLI)

MQTT Studio 2.0 can run without its window: simulate devices, record and replay MQTT traffic,
manage recordings and work with the topic documentation of your projects. This is useful in
scripts, scheduled tasks, CI pipelines and on test machines.

The CLI uses the projects you created and saved in the app. You set up brokers, simulations and
documentation in the app, and the CLI runs them.

- [Getting started](#getting-started)
- [Basics](#basics)
- [Commands](#commands)
  - [projects](#projects): list and show saved projects
  - [simulate](#simulate): run the simulation of a project
  - [record](#record): record topics into a recording
  - [replay](#replay): play a recording to a broker
  - [recordings](#recordings): list, show, export, import, edit and compare recordings
  - [doc](#doc): discover, check, export and import the topic documentation
- [Broker options](#broker-options)
- [Durations, sizes and conditions](#durations-sizes-and-conditions)
- [Output](#output)
- [Exit codes](#exit-codes)
- [Examples for scripts and CI](#examples-for-scripts-and-ci)
- [Troubleshooting](#troubleshooting)

## Getting started

The CLI comes with the Windows desktop app from the Microsoft Store: after installing it, the
command `mqttstudio` is available in any terminal (Windows Terminal, PowerShell, cmd). It is not
available in the browser version.

Check that it works:

```
mqttstudio --version
mqttstudio --help
mqttstudio projects list
```

`mqttstudio help <command>` or `mqttstudio <command> --help` shows every option of a command.

## Basics

```
mqttstudio <command> [<subcommand>] [options] [arguments]
```

**Projects.** Most commands take `-p` / `--project` with the name of a saved project. The name is
matched exactly first, then ignoring upper and lower case. Put names with spaces in quotes:
`-p "Demo factory"`.

**The CLI reads, it never changes your projects.** It sees what the app last *saved*: unsaved
changes in an open app window are not visible to it. Commands that produce documentation write
files instead of saving the project, and you import them in the app.

**App and CLI at the same time.** The app and any number of CLI runs can work at the same time.
Each CLI run connects with its own client id (the project's client id plus `-cli-` and four random
characters), so the broker doesn't disconnect the app.

**Stopping.** Long-running commands run until their duration or another stop condition is
reached, or until you press **Ctrl+C**. Ctrl+C ends the run cleanly (a recording is saved, a
discovery prints its result). A second Ctrl+C while it shuts down exits at once with code 130.

**Global options** work with every command and go before the command:

| Option | Meaning |
|---|---|
| `-h`, `--help` | Help for the CLI or a command |
| `--version` | Print the MQTT Studio version |
| `-o`, `--output text\|json` | `json` prints one JSON object per line, for scripts (see [Output](#output)). Default `text` |
| `-q`, `--quiet` | Only errors and the final summary |
| `-v`, `--verbose` | Per-topic details and the MQTT client log (on stderr) |

```
mqttstudio -o json simulate -p "Demo factory" --duration 1m
```

## Commands

### projects

List and inspect the saved projects.

```
mqttstudio projects list
mqttstudio projects show "Demo factory"
```

| Command | Shows |
|---|---|
| `projects list` | Every saved project with its broker and simulation |
| `projects show <project>` | The broker settings of a project and its simulation: devices, topics, instances and the estimated message rate |

### simulate

Run the simulation of a saved project, or some of its devices, the same way as the app's
SIMULATOR tab.

```
mqttstudio simulate -p "Demo factory"
mqttstudio simulate -p "Demo factory" -d "Weather station" -d "Packaging line" --duration 8h
mqttstudio simulate -p "Demo factory" --host test-broker.local --client-id ci-sim-42
mqttstudio simulate -p "Demo factory" --dry-run
```

| Option | Default | Meaning |
|---|---|---|
| `-p`, `--project <name>` | required | The project whose simulation runs |
| `-d`, `--device <name or id>` | all devices | Device to run. Repeat it for several devices. If two devices have the same name, use the id (`projects show` lists it) |
| `--duration <time>` | until Ctrl+C | Stop after this time, e.g. `90s`, `15m`, `1h30m` |
| `--max-rate <msg/s>` | `1000` | Refuse to start when the estimated rate is higher. At most `20000` |
| `--seed <number>` | random | Seed of the generators: two runs with the same seed publish the same payloads |
| `--dry-run` | | Check the simulation and print the plan (devices, topics, rate) without connecting |
| `--reconnect` | | Reconnect after a lost connection instead of stopping |
| `--clear-retained` | | Clear the retained messages of the simulated topics at the end |
| `--stats-every <time>` | `10s` | Interval of the progress lines, `0` turns them off |

Plus the [broker options](#broker-options).

The output starts with the plan, then prints progress lines and ends with a summary:

```
MQTT Studio 2.0.0 · simulate
Project   Demo factory (as last saved)
Broker    broker.local:1883 (MQTT 5) as demo-01-cli-7f3a
Devices   Weather station: 10 instances, 3 topics
Rate      ≈ 15 msg/s
  Weather station / weather/{n}/temp  Random walk, 1 s  → weather/1/temp … weather/10/temp
  ...
Started at 14:05:31. Press Ctrl+C to stop.
14:05:41  sent 152      15.2 msg/s  errors 0
...
Stopped after 10m 00s (duration reached): 9,184 messages, 0 errors.
```

Errors of single topics (for example a missing image folder) are printed and counted; the other
topics keep running. Devices that play a recording run like in the app, and so do devices of
simulated VDA 5050 robots: their robots say `OFFLINE` when the run stops, and `--clear-retained`
also removes their retained `connection` messages. Faults can only be injected in the app.

### record

Record topics of a project's broker into the recordings library (the folder chosen in the app's
RECORDER tab, by default `Documents\MQTT Studio\Recordings`) or into a `.mqttrec` file.

```
mqttstudio record -p "Demo factory" -t "plant/line1/#" -x "plant/line1/debug/#" --duration 8h
mqttstudio record -p "Demo factory" -t "plant/#" --start-when "plant/+/alarm" --pre-roll 2m --duration 10m
mqttstudio record -p "Demo factory" -t "plant/#" --flight 10m --save-when 'plant/+/state $.status == "error"'
mqttstudio record -p "Demo factory" -t "plant/#@1" --out C:\captures\night.mqttrec --max-messages 100000
```

**What to record**

| Option | Default | Meaning |
|---|---|---|
| `-p`, `--project <name>` | required | The broker of this project is recorded |
| `-t`, `--topic <filter>` | required | Topic filter to record. Repeatable. `<filter>@<qos>` subscribes with that QoS (default 2) |
| `-x`, `--exclude <filter>` | | Topic filter to leave out. Repeatable |
| `--name <name>` | the first filter | Name of the recording |
| `--out <file>` | the library | Write the recording to this `.mqttrec` file instead |
| `--no-retained-snapshot` | | Leave out the retained messages the broker sends right after subscribing |
| `--max-payload-size <size>` | unlimited | Store longer payloads cut, e.g. `64KB` |

**When to start and stop**

| Option | Default | Meaning |
|---|---|---|
| `--duration <time>` | | Stop after this time, counted from the start trigger |
| `--max-messages <n>` | | Stop after this many messages |
| `--max-size <size>` | `1GB` | Stop at this size |
| `--start-when <condition>` | start at once | Wait until a message matches the [condition](#conditions) |
| `--pre-roll <time>` | | Keep this much from before the start trigger, at most `10m` |
| `--stop-when <condition>` | | Stop when a message matches the condition |
| `--post-roll <time>` | | Keep recording this long after the stop condition matched |

**Flight recorder.** With `--flight`, the recorder keeps only the last part of the traffic in
memory and saves it when something happens, like the flight recorder of a plane.

| Option | Default | Meaning |
|---|---|---|
| `--flight <time>` | | Keep this window in memory |
| `--save-when <condition>` | Ctrl+C | Save the window when a message matches. Without it, Ctrl+C saves the window and stops |
| `--flight-post-roll <time>` | `30s` | Keep capturing this long after a save trigger before saving |
| `--max-saves <n>` | | Stop after this many saves |
| `--flight-memory <size>` | | Use at most this much memory, e.g. `200MB` |

**Other:** `--reconnect` reconnects after a lost connection (the gap is marked in the recording)
instead of stopping and saving; `--stats-every <time>` (default `10s`) sets the interval of the
progress lines. Plus the [broker options](#broker-options).

Ctrl+C stops and saves the recording. The last line names the file.

### replay

Play a recording to a broker: at its original timing, faster or slower, in a loop, for one or many
simulated instances.

```
mqttstudio replay "Line 1 night shift" -p "Test broker" --speed 10 --remap "plant/=test/plant/"
mqttstudio replay line1.mqttrec --host test-broker.local -t plant/line1/temp --loop --duration 1h
mqttstudio replay line1.mqttrec -p "Test broker" --instances 50 --remap "plant/line1/=plant/line{n}/"
```

`<recording>` is a `.mqttrec` file, or the name or id of a recording in the library (see
[recordings](#recordings)).

| Option | Default | Meaning |
|---|---|---|
| `-p`, `--project <name>` | | The broker of this project. Required unless `--host` is given |
| `-t`, `--topic <topic>` | all topics | Recorded topic to play. Repeatable |
| `--speed <x>` | `1` | `0.1` to `100`, or `max` (as fast as `--max-rate` allows) |
| `--loop` | | Start over at the end |
| `--from <time>`, `--to <time>` | the whole recording | Play only this range, as offsets from the start, e.g. `--from 5m --to 12m30s` |
| `--compress-gaps <time>` | | Shorten pauses longer than this to this |
| `--remap <from>=<to>` | | Rewrite the start of topics. Repeatable. `<to>` may contain `{n}`, the instance number |
| `--instances <n>` | `1` | Play the recording for this many instances at once. More than one needs a `--remap` with `{n}` |
| `--instance-start <mode>` | `staggered` | How the instances start: `staggered`, `aligned` or `random` |
| `--snapshot <mode>` | `publish` | `publish` sends the recorded retained messages first, `skip` leaves them out |
| `--retain <mode>` | `as-recorded` | `as-recorded`, `never` or `always` |
| `--qos <0\|1\|2>` | as recorded | QoS of all messages |
| `--duration <time>` | to the end | Stop after this time |
| `--max-rate <msg/s>` | `1000` | Refuse to start when the estimated rate is higher. At most `20000` |
| `--reconnect` | | Reconnect after a lost connection and go on |
| `--dry-run` | | Print the plan without connecting |
| `--stats-every <time>` | `10s` | Interval of the progress lines, `0` turns them off |

Plus the [broker options](#broker-options). `--speed max` works with one instance only.

### recordings

Work with the recordings library. A `<recording>` argument is a `.mqttrec` file path, or the id or
name of a recording in the library (exact, then ignoring upper and lower case). If a name is used
more than once, the CLI lists the ids to use instead.

**recordings list**: the recordings of the library.

```
mqttstudio recordings list
mqttstudio recordings list -p "Demo factory"
```

`-p` lists only the recordings made with that project.

**recordings show**: a recording with its summary per topic.

```
mqttstudio recordings show "Line 1 night shift" --gaps --duplicates
```

`--gaps` lists the pauses of each topic, `--duplicates` the repeated payloads per topic.

**recordings export**: write a recording as JSON lines, CSV or a copy of the file.

```
mqttstudio recordings export "Line 1 night shift" --format csv --column '$.temp' --column '$.state'
mqttstudio recordings export night.mqttrec --format jsonl -t plant/line1/temp --from 1h --to 2h --out temp.jsonl
```

| Option | Default | Meaning |
|---|---|---|
| `--format <jsonl\|csv\|mqttrec>` | `jsonl` | Format |
| `--out <file>` | the recording name | File to write |
| `-t`, `--topic <topic>` | all | Topic to export. Repeatable |
| `--from <time>`, `--to <time>` | everything | Range as offsets from the start |
| `--column <json path>` | | CSV: an extra column with the value at this [JSON path](#json-paths). Repeatable |

**recordings import**: import a file into the library.

```
mqttstudio recordings import capture.jsonl
mqttstudio recordings import sub.txt --format mosquitto --interval 500ms --name "From the field"
```

| Option | Default | Meaning |
|---|---|---|
| `--format <mqttrec\|jsonl\|csv\|mosquitto>` | from the file | `mosquitto` reads the output of `mosquitto_sub -v` or `mosquitto_sub -F "%U %t %p"` |
| `--interval <time>` | `1s` | For `mosquitto_sub -v` output, which has no times: the time between two lines |
| `--name <name>` | the file name | Name of the recording |

**recordings edit**: write a new recording from an existing one. The original stays as it is.

```
mqttstudio recordings edit "Line 1 night shift" --from 10m --to 40m --name "Line 1 incident"
mqttstudio recordings edit night.mqttrec --exclude-topic "plant/line1/debug/#" --rename "plant/=demo/"
mqttstudio recordings edit night.mqttrec --anonymize rules.json
```

| Option | Meaning |
|---|---|
| `--from <time>`, `--to <time>` | Keep only this range |
| `-t`, `--topic <topic>` | Keep only these topics. Repeatable |
| `--exclude-topic <topic>` | Leave out these topics. Repeatable |
| `--rename <from>=<to>` | Rename topics by their start. Repeatable |
| `--anonymize <file>` | Apply anonymize rules from a JSON file, as saved in the app's anonymize dialog |
| `--anonymize-properties` | Apply the whole-payload rules to MQTT 5 user properties too |
| `--name <name>` | Name of the new recording |

The steps run in this order: range, topics, rename, anonymize. The result goes into the library;
`recordings export --format mqttrec` copies it to a file.

**recordings compare**: compare two recordings topic by topic, for example a test run with a
reference run. Exits with code 8 when they differ.

```
mqttstudio recordings compare reference.mqttrec run-42.mqttrec --ignore '$.ts' --number-tolerance 0.5
mqttstudio recordings compare "Before update" "After update" --counts --count-tolerance 5 --report diff.json
```

| Option | Default | Meaning |
|---|---|---|
| `--counts` | | Compare the number of messages per topic |
| `--payloads` | | Compare the payloads per topic, in order |
| `--timing` | | Compare the median interval per topic |
| `--ignore <json path>` | | Leave this JSON field out of the payload comparison. Repeatable |
| `--count-tolerance <percent>` | `0` | Allowed difference of the counts |
| `--number-tolerance <x>` | `0` | Allowed absolute difference of numbers in payloads |
| `--timing-tolerance <percent>` | `10` | Allowed difference of the intervals |
| `--remap <from>=<to>` | | Map topics of the second recording onto the first by their start. Repeatable |
| `--report <file>` | | Write the result as JSON |

Without `--counts`, `--payloads` or `--timing`, all three comparisons run.

### doc

Work with the topic documentation of a project (the app's DOCUMENTATION tab).

The CLI doesn't save projects, so `doc discover` and `doc import` write the resulting
documentation to an **AsyncAPI file**. Open the DOCUMENTATION tab in the app and use **IMPORT** to
take it over; an MQTT Studio AsyncAPI file imports without losing anything.

**doc discover**: listen to the broker (or read a recording), find the topics with their payload
format, schema, interval, QoS and retain flag, and compare them with the documentation.

```
mqttstudio doc discover -p "Demo factory" -t "plant/#" --duration 10m
mqttstudio doc discover -p "Demo factory" -t "plant/#" -x "plant/+/debug/#" --count 50000 --out plant.asyncapi.yaml
mqttstudio doc discover -p "Demo factory" -t "#" --from-recording "Line 1 night shift" --out plant.asyncapi.yaml
```

| Option | Default | Meaning |
|---|---|---|
| `-p`, `--project <name>` | required | The project whose documentation is compared and whose broker is used |
| `-t`, `--filter <filter>` | required | Topic filter to discover. Repeatable. Avoid `#` on a busy broker |
| `-x`, `--exclude <filter>` | | Topic filter to leave out. Repeatable |
| `--duration <time>` | `5m` | Listen this long. Ctrl+C stops earlier and still prints the result |
| `--count <n>` | | Stop after this many messages instead of a duration |
| `--from-recording <recording>` | | Read a recording (name, id or `.mqttrec` file) instead of the broker |
| `--out <file>` | | Apply the result as the app's review would by default and write the documentation to this AsyncAPI file (`.json` for JSON, otherwise YAML) |
| `--no-templates` | | Don't combine topics like `m1`, `m2`, `m3` into templates like `m{id}` |
| `--no-schemas` | | Don't infer JSON schemas |
| `--reconnect` | | Reconnect after a lost connection instead of stopping |

Plus the [broker options](#broker-options). The result line counts the new topics (and how many of
them are templates), the changed ones and the documented topics that didn't send anything. With
`-v` each topic is listed.

**doc check**: check live messages against the documentation. It reports messages on
undocumented topics, wrong payload formats, JSON that breaks the schema, values out of range or
not allowed, parameters that break their pattern, a different QoS or retain flag, topics that
stay silent longer than documented, use of deprecated topics and differing MQTT 5 properties.

```
mqttstudio doc check -p "Demo factory" --duration 10m
mqttstudio doc check -p "Demo factory" -t "plant/line1/#" --duration 1h --fail-on warning
mqttstudio -o json doc check -p "Demo factory" --duration 5m > findings.jsonl
```

| Option | Default | Meaning |
|---|---|---|
| `-p`, `--project <name>` | required | The project whose documentation is checked |
| `-t`, `--filter <filter>` | see below | Topic filter to check. Repeatable |
| `--duration <time>` | until Ctrl+C | Check this long |
| `--fail-on <severity>` | `error` | Exit with code 8 when a finding of this severity or worse occurred: `error`, `warning` or `never` |
| `--reconnect` | | Reconnect after a lost connection instead of stopping |

Plus the [broker options](#broker-options). Without `-t`, the check subscribes to the filters of
the last applied discovery, else to the documented topics.

At the end it prints one line per finding (severity, topic, rule, count, detail) and a summary.

| Severity | Rules |
|---|---|
| error | wrong format, schema violation, value not allowed, parameter mismatch, stale (no message within the documented time) |
| warning | undocumented topic, out of range, different QoS, different retain flag, deprecated topic in use, different MQTT 5 properties |

**doc export**: write the documentation as a document or a machine-readable file.

```
mqttstudio doc export -p "Demo factory" --format html --out topics.html
mqttstudio doc export -p "Demo factory" --format asyncapi-yaml --scope plant/line1 --broker > line1.yaml
mqttstudio doc export -p "Demo factory" --format csv
```

| Option | Default | Meaning |
|---|---|---|
| `-p`, `--project <name>` | required | The project |
| `--format <format>` | required | `md` (Markdown), `html` (print it as PDF from the browser), `asyncapi-yaml`, `asyncapi-json`, `jsonschema` (a JSON Schema bundle of the payloads) or `csv` |
| `--out <file>` | stdout | Write to this file |
| `--scope <path>` | everything | Only this namespace or topic and everything below it |
| `--observed` | | Include what discovery observed (rates, intervals, instances) |
| `--broker` | | Include host, port and protocol of the broker |
| `--no-examples` | | Leave out the example payloads |

Exports never contain passwords, certificates or the client id.

**doc import**: compare an AsyncAPI file (2.x or 3.x, YAML or JSON) with the documentation and
write the merged result.

```
mqttstudio doc import -p "Demo factory" vendor-api.yaml
mqttstudio doc import -p "Demo factory" vendor-api.yaml --out merged.asyncapi.yaml
mqttstudio doc import -p "Demo factory" vendor-api.yaml --replace --out replaced.asyncapi.yaml
```

| Option | Meaning |
|---|---|
| `-p`, `--project <name>` | The project whose documentation the file is compared with. Required |
| `--out <file>` | Write the merged documentation to this AsyncAPI file. Without it, the command only prints what would change |
| `--replace` | Replace the documentation instead of merging |

It prints how many topics are new, changed, unchanged or in conflict (a topic covered by an
existing template); `-v` lists them. When merging, new and changed topics are taken over and what
discovery observed is kept.

## Broker options

`simulate`, `record`, `replay`, `doc discover` and `doc check` connect with the broker settings of
the project. These options override them for one run:

| Option | Meaning |
|---|---|
| `--host <host or URL>` | Broker hostname, or a `ws://` / `wss://` URL for WebSockets |
| `--port <port>` | Port |
| `--client-id <id>` | Client id. Default: the project's client id with `-cli-<random>` appended |
| `--username <name>` | User name |
| `--tls` / `--no-tls` | Turn TLS on or off |
| `--ca-cert <file>` | PEM file of a CA to trust in addition to the system ones |
| `--cert <file>` | PEM file of the client certificate (TLS over TCP) |
| `--key <file>` | PEM file of the private key, by default read from the certificate file |

**Passwords are never options**, because command lines end up in shell histories and process
lists. Set them as environment variables instead; without them the passwords of the project are
used:

| Variable | Used for |
|---|---|
| `MQTTSTUDIO_PASSWORD` | The broker password |
| `MQTTSTUDIO_KEY_PASSWORD` | The password of the private key |

```powershell
$env:MQTTSTUDIO_PASSWORD = "secret"
mqttstudio record -p "Demo factory" --username recorder -t "plant/#" --duration 1h
```

## Durations, sizes and conditions

**Durations:** `500ms`, `90s`, `15m`, `8h`, `2d` and combinations like `1h30m`. A plain number is
seconds.

**Sizes:** `64KB`, `500MB`, `1GB`, or a number of bytes.

### JSON paths

A small JSON path subset selects a field of a JSON payload: `$` is the whole payload, `.name` a
field, `['name with spaces']` a field with special characters, `[0]` an array element. For
example `$.machine.temp` or `$.alarms[0].code`.

### Conditions

`--start-when`, `--stop-when` and `--save-when` take a condition:

```
<topic filter> [<json path>] [<operator> <value>]
```

| Condition | Matches |
|---|---|
| `plant/line1/alarm` | any message on the topic |
| `plant/+/temp > 80` | a number payload above 80 |
| `plant/line1/state $.status == "error"` | a JSON field equal to a text |
| `plant/line1/log ~ /timeout\|refused/` | a payload matching a regular expression |

Operators: `==`, `!=`, `>`, `>=`, `<`, `<=`, `contains` and `~` (regular expression). Values
compare as numbers when both sides are numbers, otherwise as text.

Put the whole condition in quotes. In PowerShell, single quotes keep the inner double quotes and
`$` as they are: `--save-when 'plant/+/state $.status == "error"'`.

## Output

**Text** (default) is meant for people: a plan at the start, progress lines (`--stats-every`) and
a summary at the end. `-q` prints only errors and the summary, `-v` adds details per topic and the
MQTT client log on stderr.

**JSON lines** (`-o json`) is meant for scripts: one JSON object per line on stdout. Every object
has `event` (what happened) and `time` (ISO 8601, UTC). Errors go to stderr as
`{"event":"error","message":…}`.

```json
{"event":"plan","time":"2026-10-25T13:05:31.000Z","project":"Demo factory","broker":"broker.local:1883","protocol":"v5","clientId":"demo-01-cli-7f3a","devices":[{"id":"7a4b…","name":"Weather station","instances":10,"topics":3}],"estimatedRate":15.3}
{"event":"started","time":"2026-10-25T13:05:31.200Z"}
{"event":"stats","time":"2026-10-25T13:05:41.200Z","sent":152,"rate":15.2,"errors":0}
{"event":"stopped","time":"2026-10-25T13:15:31.200Z","reason":"duration","sent":9184,"errors":0,"exitCode":0}
```

Long-running commands end with an event that carries `exitCode`. `doc check` writes one `finding`
event per finding, with `severity`, `rule`, `topic`, `documented` (the matching documented
topic), `count`, `first`, `last`, `detail` and an example `payload`, and then a `summary`.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Finished: the duration was reached, Ctrl+C, or the command succeeded |
| 1 | Unexpected error |
| 2 | Wrong usage: unknown command or option, bad value, invalid condition |
| 3 | Not found: project, device or recording, or an ambiguous name |
| 4 | Invalid: the simulation or replay settings fail validation, or a file can't be read as AsyncAPI |
| 5 | Could not connect to or authenticate with the broker |
| 6 | Lost the connection and `--reconnect` was not given |
| 7 | The estimated rate is above `--max-rate` |
| 8 | Differences: `recordings compare` found differences, or `doc check` found findings at or above `--fail-on` |
| 130 | Second Ctrl+C during shutdown |

Errors of single topics during a simulation don't change the exit code; they are counted in the
summary.

## Examples for scripts and CI

**Load test for 30 minutes, with a fixed seed:**

```
mqttstudio simulate -p "Load test" --max-rate 5000 --seed 42 --duration 30m --reconnect
```

**Record a night shift into a file:**

```
mqttstudio record -p "Plant" -t "plant/#" --duration 8h --out "D:\captures\night-$(Get-Date -Format yyyyMMdd).mqttrec"
```

**Record what happens around an alarm:**

```
mqttstudio record -p "Plant" -t "plant/#" --flight 15m --save-when "plant/+/alarm" --flight-post-roll 2m --max-saves 5
```

**Regression test: replay a reference recording, record the system's answers, compare:**

```powershell
Start-Process mqttstudio -ArgumentList 'replay','reference-input.mqttrec','-p','Test broker' -NoNewWindow
mqttstudio record -p "Test broker" -t "results/#" --duration 10m --out run.mqttrec
mqttstudio recordings compare reference-output.mqttrec run.mqttrec --ignore '$.ts' --number-tolerance 0.01
if ($LASTEXITCODE -eq 8) { Write-Error "The results differ from the reference" }
```

**Fail a pipeline when the devices don't follow the documented topics:**

```powershell
mqttstudio -o json doc check -p "Plant" --duration 15m --fail-on error > findings.jsonl
if ($LASTEXITCODE -eq 8) { Write-Error "Topics break the documentation, see findings.jsonl" }
```

**Publish the topic documentation with every build:**

```
mqttstudio doc export -p "Plant" --format html --out public\topics.html
mqttstudio doc export -p "Plant" --format asyncapi-yaml --broker --out public\asyncapi.yaml
```

## Troubleshooting

**"Project … not found."** The CLI only sees saved projects: save the project in the app first.
`mqttstudio projects list` shows what the CLI sees.

**"Cannot connect to MQTT broker … The semaphore timeout period has expired, errno = 121".** The
broker's port didn't answer at all. Check host and port, the firewall, and whether the network
blocks the port (unencrypted MQTT on 1883 is often blocked; try the TLS port, usually 8883).

**"Connection refused" or "not authorized".** Check `--username` and `MQTTSTUDIO_PASSWORD`, and
whether the broker requires TLS or a client certificate.

**The app window gets disconnected when the CLI starts.** Both use the same client id because
`--client-id` was set to the project's own id. Leave `--client-id` out, the CLI then adds a random
suffix.

**Nothing is printed in a script.** Use `-o json` and read stdout line by line; errors are on
stderr. With `-q`, only errors and the final summary are printed.

**A long run stops when the network drops.** Add `--reconnect`: the run then retries (after 1, 2,
5 and 10 seconds, then every 30 seconds) and goes on.
