# MQTT Studio CLI – Design

Status: **Decided** (open decisions settled, see §8). Amended with the recorder commands (§7.1, C5–C7, draft), see `recorder-design.md` · Branch: `mqtt5` · Last updated: 2026-10-24

## 1. Purpose

MQTT Studio can run **headless from a command line**. The first command starts a saved simulation,
or selected devices of it, without opening the window. Typical uses: a soak test overnight, a CI
job that needs test traffic, a demo broker that is always fed.

The CLI is a framework with commands. `simulate` is the first one, and `publish`, `subscribe`,
`record` and so on can be added later without changing how the CLI is started, parsed, or how it
reports results.

### Goals (v1)
- `mqttstudio simulate --project <name> [--device <name> …]` runs until Ctrl+C or a set duration.
- Connection settings come from the saved project and can be overridden per run.
- Human-readable progress by default. JSON lines (`--output json`) for scripts and CI.
- Documented exit codes.
- Helper commands so a user can find what to pass: `projects list`, `projects show`.

### Non-goals (v1)
- Editing projects or simulations from the CLI (create them in the app).
- Running on Linux/macOS or without MQTT Studio installed (see §8, option B).
- Web build (a browser has no CLI).
- Remote control of a running GUI instance.

## 2. Command line

### 2.1 Shape

```
mqttstudio <command> [<subcommand>] [options]
mqttstudio --help | --version
mqttstudio help <command>
```

Built on `package:args` `CommandRunner`, which gives nested commands, generated `--help` per
command, typo suggestions and usage errors for free. Every new feature is one more `Command`
subclass registered in one place (§5).

### 2.2 Global options (every command)

| Option | Default | Meaning |
|---|---|---|
| `-h`, `--help` | | Help for the CLI or the command |
| `--version` | | Print the app version and exit |
| `-o`, `--output <text\|json>` | `text` | `json` prints one JSON object per line (§4.2) to stdout |
| `-q`, `--quiet` | off | Only errors and the final summary |
| `-v`, `--verbose` | off | Adds per-topic details and MQTT client logging |

### 2.3 v1 commands

| Command | Purpose |
|---|---|
| `simulate` | Run the simulation of a project, or some of its devices |
| `projects list` | List saved projects: name, broker, number of devices and topics |
| `projects show <project>` | Show a project's broker settings and its devices with their topics, instance counts and estimated rate |

### 2.4 `simulate`

```
mqttstudio simulate --project "Demo factory"
mqttstudio simulate -p "Demo factory" -d "Weather station" -d "Packaging line" --duration 8h
mqttstudio simulate -p "Demo factory" --host test-broker.local --client-id ci-sim-42 --output json
mqttstudio simulate -p "Demo factory" --dry-run
```

**What to run**

| Option | Default | Meaning |
|---|---|---|
| `-p`, `--project <name>` | **required** | Saved project, matched by name (exact, then case-insensitive). Projects are keyed by name in the store, so names are unique |
| `-d`, `--device <name\|id>` | all devices | Repeatable. Matched by device name, or by id when names are ambiguous (§3.2) |

**How long and how fast**

| Option | Default | Meaning |
|---|---|---|
| `--duration <time>` | until Ctrl+C | Stop after e.g. `90s`, `15m`, `8h`, `1h30m` |
| `--max-rate <msg/s>` | `1000` | Start is refused above this estimated rate (D11). Headless has no UI to protect, so it may be raised, up to `20000` |
| `--seed <int>` | random | Seeds every generator, so two runs publish the same payload sequence (timing still varies) |
| `--dry-run` | off | Load, validate and print the resolved plan (devices, topics with `{n}` expanded, rate), then exit without connecting |

**Broker overrides** (otherwise from the project's `MqttSettings`)

| Option | Meaning |
|---|---|
| `--host <host>` | Hostname or URL, same rules as the project dialog (including `ws://…/mqtt`) |
| `--port <port>` | Port |
| `--client-id <id>` | Default: `<project client id>-cli-<4 random hex>`. This avoids the broker disconnecting a GUI session that uses the project's own client id |
| `--username <name>` | Username |
| `--tls` / `--no-tls` | Override `useSsl` |
| `--ca-cert <file>` | PEM file of a CA to trust in addition to the system ones. Overrides the project's CA certificate |
| `--cert <file>` | PEM file of the client certificate for TLS over TCP. Overrides the project's certificate and key |
| `--key <file>` | PEM file of the private key. Without it the key is read from the certificate file |
| *(key password)* | Taken from `MQTTSTUDIO_KEY_PASSWORD` if set, else from the project, for the same reason as the password |
| *(password)* | Taken from the environment variable `MQTTSTUDIO_PASSWORD` if set, else from the project. There is deliberately **no `--password` option**: arguments end up in shell history and process lists |

**Behavior**

| Option | Default | Meaning |
|---|---|---|
| `--reconnect` | off | On connection loss, retry with backoff (1 s, 2 s, 5 s, 10 s, then every 30 s) and resume. Without it the run ends with exit code 6, matching the app's stop-on-disconnect (D8) |
| `--clear-retained` | off | On exit, clear retained messages of the topics that ran (same as the app's CLEAR RETAINED) |
| `--stats-every <time>` | `10s` | Progress interval. `0` turns it off |

### 2.5 Text output

```
> mqttstudio simulate -p "Demo factory" -d "Weather station" --duration 10m
MQTT Studio 1.1.0 · simulate
Project   Demo factory
Broker    broker.local:1883 (MQTT 5) as demo-01-cli-7f3a
Devices   Weather station: 10 instances, 3 topics
Rate      ≈ 15 msg/s
Started at 14:05:31. Press Ctrl+C to stop.
14:05:41  sent 152      15.2 msg/s  errors 0
14:05:51  sent 305      15.3 msg/s  errors 0
...
Stopped after 10m 00s (duration reached): 9,184 messages, 0 errors.
```

Topic errors (like a missing image folder) are printed when they happen and counted. The other
topics keep running, as in the app.

## 3. Behavior details

### 3.1 Reading the project
- The CLI reads projects through the same `LocalStore` (SharedPreferences key `localstore`) as
  the app, so it sees exactly what the app last **saved**. Unsaved edits in an open app window
  are not visible. The plan printout makes that clear by showing the project's last-saved time.
- The CLI **never writes** to the store. In particular it does not go through
  `ProjectManager.openProject`, which updates `lastUsed` and saves. The GUI may save while a CLI
  run is in progress without any conflict. Recordings are files in the recordings library, not in
  the store (recorder R2), so `record` and `recordings` don't break this rule.
- The app and any number of CLI runs can be active at the same time. Each is its own process with
  its own MQTT connection and, by default, its own client id.

### 3.2 Device selection
- `--device` matches the device name exactly, then case-insensitively. If two devices have the
  same name, it fails with exit code 3 and lists their ids. `--device <id>` always works.
- To make that rare, the device dialog validates that device names are unique within a
  simulation (new rule D20 in the simulator design).
- A device that matches nothing fails the whole run before connecting (exit code 3, with "did
  you mean" suggestions from the device list).

### 3.3 Lifecycle
1. Parse the arguments (exit 2 on error). Load the project and select devices (exit 3).
2. Validate the simulation with the same validators as the app's dialogs, and estimate the rate
   (exit 4 for invalid, exit 7 above `--max-rate`).
3. `--dry-run`: print the plan and exit 0.
4. Connect (exit 5 if that fails). Start all topics of the selected devices with
   `SimulatorRunner`, using the app's code unchanged.
5. Run until Ctrl+C (SIGINT), SIGTERM, `--duration`, or connection loss without `--reconnect`.
6. Stop the runner. If `--clear-retained` is set, clear retained messages. Disconnect, print the
   summary and exit with the code from §4.1.

A second Ctrl+C during shutdown exits immediately with code 130.

## 4. Results

### 4.1 Exit codes (shared by every command)

| Code | Name | When |
|---|---|---|
| 0 | `ok` | Finished: duration reached, Ctrl+C, or `--dry-run` / list commands succeeded |
| 1 | `failure` | Unexpected error |
| 2 | `usage` | Unknown command or option, bad value |
| 3 | `notFound` | Project or device not found, or a device name is ambiguous |
| 4 | `invalid` | The simulation fails validation (e.g. topic without `{n}` on a multi-instance device) |
| 5 | `connectFailed` | Could not connect or authenticate |
| 6 | `connectionLost` | Lost the connection and `--reconnect` is off |
| 7 | `rateLimit` | Estimated rate is above `--max-rate` |
| 8 | `mismatch` | `recordings compare` found differences (C6) |
| 130 | `interrupted` | Second Ctrl+C during shutdown |

Topic errors during a run don't change the exit code. They are counted in the summary
(`errors`). A `--fail-on-topic-error` flag can be added later if CI needs it.

### 4.2 JSON lines (`--output json`)

One object per line on stdout. Every object has `event` and `time` (ISO 8601, UTC). Diagnostics
and errors that happen before the run starts go to stderr as `{"event":"error",…}`.

```json
{"event":"plan","time":"…","project":"Demo factory","broker":"broker.local:1883","clientId":"demo-01-cli-7f3a","devices":[{"id":"…","name":"Weather station","instances":10,"topics":3}],"estimatedRate":15.3}
{"event":"started","time":"…"}
{"event":"stats","time":"…","sent":152,"rate":15.2,"errors":0}
{"event":"topicError","time":"…","device":"Packaging line","topic":"factory/line1/camera","message":"Image folder not found: D:\\sim\\camera"}
{"event":"reconnecting","time":"…","attempt":2,"delaySeconds":2}
{"event":"stopped","time":"…","reason":"duration","sent":9184,"errors":0,"exitCode":0}
```

`reason` is one of `duration`, `interrupted`, `terminated`, `connectionLost`. Every later
command uses the same envelope (`event`, `time`) and ends with one final event that carries
`exitCode`.

## 5. Architecture

### 5.1 Process model (option A, decided C1)

The CLI is the **same app binary**, started in headless mode:

```
mqttstudio.exe  (new, console subsystem, ~100 lines C++)       MQTT Studio.exe (existing)
 ├─ is what users type, via the MSIX execution alias            ├─ wWinMain sees "--cli" as first arg:
 ├─ starts "MQTT Studio.exe --cli <args…>"                      │    creates the Flutter window hidden,
 ├─ shares its console (stdout/stderr, Ctrl+C)                  │    never shows it (no taskbar entry)
 └─ waits and returns the child's exit code                     └─ main(args) → CliApp.run(args) instead of runApp()
```

Why a separate small launcher: `MQTT Studio.exe` is a Windows GUI-subsystem program. When you
start one from cmd or PowerShell, the shell does not wait for it. The prompt comes back at once,
output gets mixed with it, and `$LASTEXITCODE` is wrong. A console-subsystem launcher fixes all
three. Visual Studio uses the same pattern (`devenv.com` / `devenv.exe`). The existing runner
already calls `AttachConsole(ATTACH_PARENT_PROCESS)`, so the child writes to the launcher's
console.

Why the same binary: the whole stack is reused as is. That covers `LocalStore` on
SharedPreferences (whose file location under MSIX is virtualized and would be hard to find from
another program), `MqttAdapter`, `srx_flutter` and the simulator engine. There's one build and one
installer.

Changes outside Dart:
- `windows/runner/main.cpp`: if the first argument is `--cli`, create the window without showing
  it and don't set `SetQuitOnClose`. Dart ends the process with `exit(code)`.
- New CMake target `mqttstudio_cli` (the launcher) next to the runner, copied into the bundle.
- `pubspec.yaml` `msix_config`: add `execution_alias: mqttstudio`, pointing at the launcher, so
  `mqttstudio` works in any terminal after a Store or MSIX install.

### 5.2 Dart structure

```
lib/main.dart                        if args.first == '--cli' → exit(await runCli(args.skip(1)))
lib/cli/cli_app.dart                 CommandRunner, global options, error → exit code mapping
lib/cli/cli_context.dart             CliContext: Output, read-only ProjectSource, MqttConnector, clock
lib/cli/output.dart                  Output interface; TextOutput and JsonLinesOutput
lib/cli/exit_codes.dart              enum CliExitCode (§4.1)
lib/cli/cli_exception.dart           CliException(exitCode, message) — thrown by commands
lib/cli/duration_parser.dart         "1h30m" → Duration (shared by future commands)
lib/cli/commands/cli_command.dart    abstract CliCommand extends Command<int>: gets CliContext
lib/cli/commands/simulate_command.dart
lib/cli/commands/projects_command.dart   (parent) + projects_list_command.dart, projects_show_command.dart
```

```dart
abstract class CliCommand extends Command<int> {
  CliCommand(this.context);
  final CliContext context;
  // run() returns the exit code; failures throw CliException.
}

class CliContext {
  final Output out;                // text or JSON lines, honors --quiet/--verbose
  final ProjectSource projects;    // read-only view on LocalStore
  final MqttConnector mqtt;        // builds MqttAdapter-backed connections with overrides
  final Clock clock;               // injectable for tests
}
```

Adding a feature later means writing one `CliCommand`, registering it in `cli_app.dart`, and
documenting it in this file. Parsing, help, output format and exit codes are already there.

**Startup in CLI mode** runs only what headless needs: `WidgetsFlutterBinding.ensureInitialized()`
(plugins: shared_preferences, path_provider), `EasyLocalization` assets for messages, and the
GetIt registrations of `MqttAdapter`. There is no `SrxNavigationService`, no `runApp`, no
newsletter or performance dialogs, and no Piwik tracking (headless runs aren't app usage).

### 5.3 Effects on the simulator engine
- `SimulatorRunner` must be usable without `ProjectManager` and the viewmodel. It already only
  needs a `SimulatorPublisher`, which keeps it testable. The CLI creates its own runner instance.
- **Disconnect policy moves out of the runner.** The runner reports connection loss. The owner
  decides what to do: `SimulatorViewmodel` stops (D8), and the CLI stops or reconnects
  (`--reconnect`). This is new rule D21 in the simulator design.
- `estimateRate()` and simulation validation become shared functions (not dialog-only), used by
  the toolbar, the dialogs and the CLI.

### 5.4 Testing
- Argument parsing and help: `CommandRunner` with a fake `CliContext`, asserting exit codes for
  every row of §4.1.
- `simulate` end to end with a fake `ProjectSource`, a fake publisher and `fake_async`:
  duration, Ctrl+C (an injected stop signal), `--seed` reproducibility, `--dry-run` printing no
  connection.
- JSON output: every line parses and has `event` and `time`. The last line has `exitCode`.
- Manual: the launcher from cmd, PowerShell and Windows Terminal (waits, exit code, Ctrl+C), and
  the MSIX alias after install.

## 6. Help text (draft)

```
Run MQTT Studio from the command line.

Usage: mqttstudio <command> [arguments]

Global options:
-h, --help       Print this usage information.
    --version    Print the MQTT Studio version.
-o, --output     Output format. [text (default), json]
-q, --quiet      Only print errors and the final summary.
-v, --verbose    Print per-topic details and MQTT client logs.

Available commands:
  projects   List and inspect saved projects.
  simulate   Run the simulation of a saved project.

Run "mqttstudio help <command>" for more information about a command.
```

## 7. Later commands (fit the same frame)

| Command | Sketch |
|---|---|
| `publish -p <project> -t <topic> [--payload <text> \| --file <path>] [--qos] [--retain]` | One-off publish, e.g. from scripts |
| `subscribe -p <project> -t <filter>… [--count N] [--duration]` | Print received messages (text or JSON lines) |
| `record`, `replay`, `recordings …` | Designed, see §7.1 |
| `simulate --topic <id>`, `--instances <device>=<n>` | Finer selection and load scaling without editing the project |
| `projects export` / `import` | If file export (a v1 non-goal of the simulator) is ever wanted |

### 7.1 Recorder commands (draft, `recorder-design.md`)

A `<recording>` argument is a file path, or a recording name (exact, then case-insensitive) or id
from the library. An ambiguous name fails with exit code 3 and lists the ids, like `--device`.
All commands use the global options, the broker overrides of §2.4 and the JSON envelope of §4.2.

**`record`**

```
mqttstudio record -p "Demo factory" -t "plant/line1/#" -x "plant/line1/debug/#" --duration 8h
mqttstudio record -p "Demo factory" -t "plant/#" --start-when "plant/+/alarm" --pre-roll 2m --duration 10m
mqttstudio record -p "Demo factory" -t "plant/#" --flight 10m --save-when 'plant/+/state $.status == "error"'
```

| Option | Default | Meaning |
|---|---|---|
| `-p`, `--project <name>` | **required** | Broker settings come from this project |
| `-t`, `--topic <filter>` | **required** | Repeatable include filter. `<filter>@<qos>` sets the QoS (default 2) |
| `-x`, `--exclude <filter>` | | Repeatable exclude filter |
| `--name <name>` | `<first filter> <time>` | Recording name |
| `--out <file>` | library folder (the one set in the recorder tab) | Write to this file instead |
| `--duration`, `--max-messages`, `--max-size` | `--max-size 1GB` | Stop conditions (recorder §5.4) |
| `--start-when <cond>`, `--pre-roll <time>` | | Start trigger (recorder §10 condition syntax) |
| `--stop-when <cond>`, `--post-roll <time>` | | Stop condition |
| `--flight <window>`, `--save-when <cond>`, `--max-saves <n>`, `--flight-memory <size>` | | Flight recorder mode. Without `--save-when`, a save happens only on SIGINT/Ctrl+C, which saves the window and exits |
| `--max-payload-size <size>` | unlimited | Longer payloads are stored cut and flagged |
| `--no-retained-snapshot` | off | Don't record the retained messages sent on subscribe |
| `--reconnect` | off | As for `simulate` (C4). The gap is marked in the recording |

Events: `plan`, `started`, `waitingForTrigger`, `triggerFired`, `stats` (`received`, `rate`,
`bytes`), `reconnecting`, `saved` (`file`, `id`, `messages`, per flight recorder save), and
`stopped` with `exitCode`. Ctrl+C stops and finalizes the recording (exit 0).

**`replay`**

```
mqttstudio replay "Line 1 night shift" -p "Test broker" --speed 10 --remap "plant/=test/plant/"
mqttstudio replay line1.mqttrec --host test-broker.local -t plant/line1/temp --loop --duration 1h
mqttstudio replay line1.mqttrec -p "Test broker" --instances 50 --remap "plant/line1/=plant/line{n}/"
```

| Option | Default | Meaning |
|---|---|---|
| `-p`, `--project <name>` | | Broker settings. Required unless `--host` is given |
| `-t`, `--topic <topic>` | all topics | Repeatable. Recorded topics to play |
| `--speed <x\|max>` | `1` | 0.1–100, or `max` (limited by `--max-rate`) |
| `--loop` | off | Start over at the end of the range |
| `--from <time>`, `--to <time>` | whole recording | Range as offsets, e.g. `--from 5m --to 12m30s` |
| `--compress-gaps <time>` | off | Shorten gaps longer than this to this |
| `--remap <from>=<to>` | | Repeatable topic prefix rewrite. `<to>` may contain `{n}`, `{n:3}` |
| `--instances <n>`, `--instance-start <staggered\|aligned\|random>` | `1`, `staggered` | Several instances; with more than one, a remap with `{n}` is required (exit 4 otherwise) |
| `--snapshot <publish\|skip>` | `publish` | Retained snapshot first (recorder R13) |
| `--retain <as-recorded\|never\|always>`, `--qos <0\|1\|2>` | as recorded | Overrides |
| `--duration <time>` | until the end (or Ctrl+C with `--loop`) | Stop after this time |
| `--max-rate`, `--reconnect`, `--clear-retained`, `--dry-run` | as `simulate` | Same meaning as for `simulate` |

Events: `plan` (topics, messages, estimated and peak rate), `started`, `stats` (`sent`,
`position`, `lag`, `loop`), `stopped` (`reason`: also `finished`).

**`recordings`**

| Command | Purpose |
|---|---|
| `recordings list` | Name, id, start, duration, messages, size, filters |
| `recordings show <recording>` | Metadata and the per-topic summary table (recorder §7.1), plus `--gaps` and `--duplicates` lists |
| `recordings export <recording> --format <csv\|jsonl\|mqttrec> [--out] [-t …] [--from] [--to] [--column <json path>]…` | Export (recorder §8.3) |
| `recordings import <file> [--format <jsonl\|csv\|mosquitto>] [--interval <time>] [--name]` | Import into the library. `--interval` for `mosquitto_sub -v` input without times |
| `recordings edit <recording> [--from] [--to] [-t …] [--exclude-topic …] [--rename <from>=<to>]… [--anonymize <rules.json>] [--name] [--out]` | Writes a new recording (recorder R9). Merge and split are app-only in v1 |
| `recordings compare <a> <b> [--counts] [--payloads] [--timing] [--ignore <json path>]… [--count-tolerance <pct>] [--number-tolerance <x>] [--timing-tolerance <pct>] [--remap <from>=<to>]… [--report <file>]` | Compare (recorder §9). Without a mode flag, all three run. Exit 8 when anything differs |

**`simulate` with recorded devices:** recorded devices run like other devices. `--dry-run` shows
the recording, range and speed of each. A missing recording fails with exit code 3 before
connecting.

## 7.2 Implementation notes (2026-10-24)

What the code does where it differs from the text above:
- **Launcher name:** the app binary is already called `mqttstudio.exe` (CMake `BINARY_NAME`), so the
  console launcher is `mqttstudio-cli.exe` next to it (`windows/cli_launcher/main.cpp`, CMake
  target `mqttstudio_cli`). It starts `mqttstudio.exe --cli …` with its own standard handles, so
  output can also be redirected to a file, ignores Ctrl+C itself and returns the app's exit code.
- **MSIX execution alias:** the `msix` package's `execution_alias` always points at the main
  executable, the GUI, so it is not used. `windows/packaging/create_msix.ps1` runs `msix:build`,
  adds a second, hidden `<Application>` for `mqttstudio-cli.exe` (`AppListEntry="none"`) with a
  `uap5:ExecutionAlias` `mqttstudio.exe` to the generated manifest, and runs `msix:pack`. Without
  `desktop4:Subsystem`: the launcher is a console program already, and makeappx rejects the
  attribute here.
- **Output through pipes:** Dart can't write to a console from a GUI-subsystem process; the writes
  never complete, so the CLI hung without output in an interactive console (redirected output
  worked). The launcher therefore gives the app pipes for stdout and stderr and copies them to its
  own handles: as UTF-16 with `WriteConsoleW` to a console, so `≈` or `…` show whatever the code page
  is, and unchanged to files and pipes. The app still attaches to the launcher's console, which is
  how Ctrl+C reaches it.
- **Runner argument fix:** `Utf8FromUtf16` in `windows/runner/utils.cpp` (old Flutter template)
  kept the terminating null in the string, so `--cli` was never recognized and the window showed.
  Fixed like the current Flutter template.
- **Version:** the launcher is built with the `pubspec.yaml` version and passes it as
  `--app-version=…` right after `--cli`; `runCli()` takes it off, and `--version` prints it without
  the build number. The runner's CMake file also passes the version to `Runner.rc`, so
  `mqttstudio.exe` carries the right file version.
- **Output of the app:** `print` lines of the app (MQTT client logging) are only shown with
  `--verbose`, on stderr, so they never mix with text or JSON output.
- `--project` is checked by the command (exit code 2 when missing) rather than marked mandatory in
  `package:args`.

## 8. Decisions

| # | Decision | Source |
|---|---|---|
| C1 | **Process model A:** the same app binary, started headless with `--cli`, plus a console-subsystem launcher and an MSIX execution alias (§5.1). Windows only. Option B (a separate pure-Dart executable with a Flutter-free core, which would also run on Linux CI) stays possible later, because `lib/cli/` only depends on `CliContext` interfaces | User |
| C2 | The command is **`mqttstudio`**: the execution alias and the launcher's file name (`mqttstudio.exe`) | User |
| C3 | `--max-rate` defaults to 1000 msg/s and accepts at most **20000** msg/s | User |
| C4 | Reconnect is **off** by default. `--reconnect` opts in. This matches the app (D8), and CI runs fail fast with exit code 6 | User |
| C5 | The recorder commands are `record`, `replay` and `recordings` with subcommands (§7.1). `record` follows C4 for reconnect, unlike the app's recorder (recorder R7) | Design, for the recorder (draft) |
| C6 | New exit code 8 `mismatch` for `recordings compare`, so CI can tell differences from errors | Design, for the recorder (draft) |
| C7 | `replay` takes the broker from `-p` or from `--host` alone, because a recording is not tied to a project | Design, for the recorder (draft) |
