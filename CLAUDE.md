# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What MQTT Studio is

MQTT Studio (https://www.mqttstudio.com) is a free MQTT client from Redpin (Bolzano, Italy) for developers who build, test and support MQTT-based systems. It ships as a Windows desktop app (MSIX / Microsoft Store and an Advanced Installer setup) and as a web app running in the browser. Personal and commercial use are both allowed under the EULA. The free version stays free, and commercial add-on features are planned.

User-facing features (as advertised on the website):
- **Projects**: bundle broker settings and topic subscriptions so users can switch between scenarios.
- **Topic subscription panel**: subscribe, unsubscribe, or pause single topics.
- **Messages viewer** with three modes: **Grouped** (by time period), **Hierarchical** (topic tree with counts) and **Sequential**.
- **Color-coded topics**: each topic's messages are shown in its color.
- **Message detail view**: metadata and payload, plus republishing a message.
- **Payload viewer**: renders text, numbers, dates, JPG/PNG images and JSON according to the content.
- **Topic filter** and **Chart view** for numeric payloads (min/max/avg), plus a map viewer.
- **Publish dialog** for sending messages.

## Repository layout

```
src/mqttstudio_client/   Flutter app (the only code project)
src/DesktopSetup/        Advanced Installer project (MQTT Studio.aip) + EULA text
doc/                     Architecture diagram (drawio), Adobe XD design, EULA
product/                 Release notes, marketing screenshots
CI/                      Icons and logos
.github/copilot-instructions.md   Coding rules (mirrored below)
```

Run all Flutter commands from `src/mqttstudio_client`.

## Tech stack

- Flutter / Dart (SDK `>=3.8.0 <4.0.0`, needed for the null-aware elements json_serializable generates), targets **Windows** and **Web**.
- **srx_flutter**: Sarix's in-house framework, pulled from `github.com/sarixgmbh/SrxFlutter` (git ref `2.0`). It provides `SrxChangeNotifier`, `SrxDialog`, `SrxTheme`, `SrxNavigationService`, `SrxSessionController`, `SrxLocalDatabaseController`, `SrxCrudRepository`/`SrxLocalCrudRepository`, `SrxBaseModel`, `SrxServiceException`, `SrxAssetLoader`. Prefer these over writing new equivalents.
- **mqtt5_client** for MQTT 5 and **mqtt_client** for MQTT 3.1.1; the protocol is chosen per project (`MqttSettings.protocolVersion`, old projects default to 3.1.1). Both packages use the same class names, so `mqtt_client` is only imported with the `v3` prefix. The app-wide `MqttQos` is the `mqtt5_client` one. The current branch `mqtt5` adds MQTT 5 and upgrades dependencies (srx_flutter 1.5 → 2.0). PRs target `develop`.
- State/DI: `provider` + `get_it` (singletons are registered in `main.dart` `setupServiceLocator()`).
- Forms: `reactive_forms`. Localization: `easy_localization` (`assets/i18n/en.json`, English only). Persistence: `sembast` / `sembast_web` via srx local DB. JSON models: `json_serializable`. Events: `event` package.
- Charts: `community_charts_flutter`. Map: `flutter_map`. Analytics: Piwik (`service/piwik_tracking_service.dart`).

## Commands

```bash
flutter pub get
flutter run -d windows
flutter run -d chrome
flutter test
flutter analyze
dart run build_runner build --delete-conflicting-outputs   # regenerate *.g.dart after changing @JsonSerializable models
flutter build windows
flutter build web
powershell -ExecutionPolicy Bypass -File windows\packaging\create_msix.ps1   # Store MSIX package (settings in pubspec.yaml msix_config) plus the "mqttstudio" command line alias; use it instead of msix:create
build\windows\x64\runner\Release\mqttstudio-cli.exe --help  # headless CLI after flutter build windows
```

## Architecture

The data flows as **MqttAdapter → MessageViewer → viewmodels → widgets**.

- `lib/mqtt/mqtt_adapter.dart`: holds the broker connection, subscribes/publishes, and raises `onConnectedEvent`, `onDisconnectedEvent`, `messageReceivedEvent` and `subscribeFailedEvent`. It picks a `MqttProtocolClient` (`mqtt_protocol_client.dart`) per connection: `Mqtt5ProtocolClient` or `Mqtt311ProtocolClient`. They map the package types to app models (`ReceivedMqttMessage` with `MqttMessageProperties`, `BrokerInfo`), so nothing else depends on a client package except `MqttQos`. Platform-specific client creation goes through a conditional import per package: `mqttserver.dart` / `mqtt3server.dart` (native TCP/WebSocket, TLS with the bundled `assets/cert/mosquitto.org.crt`) or `mqttbrowser.dart` / `mqtt3browser.dart` (`dart.library.html`, WebSockets only). On the web only `ws://`/`wss://` work, so keep both paths in mind when touching connection code.
- MQTT 5 only UI (subscription options, publish properties) sits in a `Mqtt5Section` that stays visible but disabled for 3.1.1 projects. mqtt5_client returns defaults for properties a broker did not send (empty strings, an expiry of 65535, `retainAvailable` false), see the comments in `mqtt5_protocol_client.dart`.
- `lib/mqtt/mqtt_connection_viewmodel.dart`: connection state for the UI (connect button).
- `lib/message_viewer/message_viewer.dart`: domain service that manages topic subscriptions on the current project, pause/resume, and stores messages in `MQTTMessageBuffer` (`message_buffer.dart`). It re-broadcasts events to viewmodels.
- `lib/message_viewer/widgets/`: the grouped, sequential and tree viewers, the detail view, the subscription panel and the command bar.
- `lib/project/`: `ProjectManager` (open, close and save the current project, `projectClosedEvent`, unsaved-changes prompt), plus the project dialogs and viewmodels.
- `lib/model/`: serializable models (`Project`, `MqttSettings`, `TopicSubscription`, `TopicColor`, …) with generated `*.g.dart` parts. Don't hand-edit `*.g.dart`.
- `lib/repository/local/`: `LocalProjectRepository` stores projects in the local sembast DB.
- `lib/simulator/`: the SIMULATOR tab (`doc/simulator-design.md`). `model/` holds the `Simulation` saved in the `Project` (devices with N instances, topics, typed `PayloadGenerator`s), `engine/` the `SimulatorRunner` (timers, publishing, stats), generator instances, `{n}` placeholders and `SimulationRules` (validation and rate limits shared with the CLI). The `Simulator` service connects it to the project and the broker; the page, dialogs and viewmodels sit next to it. Tests in `test/simulator/`.
- `lib/cli/`: the headless CLI (`doc/cli-design.md`). `main()` runs it when the first argument is `--cli`, which the console launcher `windows/cli_launcher` (`mqttstudio-cli.exe`) passes; the Windows runner then keeps the window hidden. Commands extend `CliCommand` and are registered in `cli_app.dart`. Tests in `test/cli/`.
- `lib/service/`: Piwik tracking, newsletter signup, and the `ServiceError` codes used with `SrxServiceException`.
- `lib/common/`: shared widgets, payload utilities, the login page (currently bypassed), and the browser performance warning that suggests the desktop client.
- Theming: `lib/custom_theme.dart` (`CustomTheme.lightTheme`, `CustomTheme.srxTheme`). Dialogs are wrapped in `SrxTheme`.

## UI design

**Design system:** https://claude.ai/artifact/M1uENVXPQJf74mB86VB5yu. It holds the tokens resolved from `custom_theme.dart` and `topic_color.dart`, HTML renditions of every main widget, logos, screenshots and an "Adding a feature" guide. Read its `project/README.md` (Artifact `read` with `path`) before designing new UI, and update it when a feature adds a token or component.

MQTT Studio is a dense, single-window **desktop-first** tool. Design for a wide window (~1500 px). The web build uses the same layout, and there is no mobile or responsive layout. The reference screens are in `product/screenshots/`, and the original design file is `doc/MQTT Studio.xd`.

### Main window layout (`message_viewer_page.dart`)

From top to bottom:
1. **App bar** (`MainAppBar`): the hamburger opens the `NavigationDrawer`, then come the current project name (max 250 px), a `TabBar` ("TOPIC VIEWER" and "SIMULATOR"; Recorder and Documentation tabs exist but are hidden; the body is an `IndexedStack` by tab), and the full-height **ConnectButton** on the right. The button is green when connected and red when disconnected, with a power icon and an uppercase label.
2. **Topic subscription panel**: a `Wrap` of colored `TopicChip`s, one per subscription. Tapping a chip pauses or resumes it, and its ✕ unsubscribes. A faint watermark text ("Subscribed Topics", `headlineMedium` in `dividerColor`) sits behind the chips. On the right is a red accent `FloatingActionButton` (+) that opens `AddTopicDialog`. It is grey when no project is open.
3. **Command bar** (`TopicsViewCommandBar`): a row between two `Divider(height: 4)`, with groups separated by `VerticalDivider`s 40 px high. The groups are play (green), pause and clear icon buttons; borderless `ToggleButtons` for the view mode (Grouped `view_agenda`, Tree `account_tree`, Sequential `format_list_bulleted`); a grouping-period dropdown (1s/10s/1m/1h, shown only in Grouped mode); and a 300×40 outlined "topic filter" field with a filter icon, a clear button and a 300 ms debounce. A `TextButton` "PUBLISH" with the `send` icon is right-aligned.
4. **Body**: a `Row` with the active messages viewer filling the space and, when a message is selected, the **MessageDetailView** docked on the right (fixed 500 px, separated by a left border in `dividerColor`).

### Visual language

- **Theme**: `CustomTheme.lightTheme`, Material 2 (`useMaterial3: false`), light only. The primary color is a grey swatch (`0xFF616161`, which gives the dark grey app bar). The accent/secondary is a deep red `0xffB71C1C` (used for the FAB), and the error color is `0xfff62a00`. Always take colors from `Theme.of(context)`, and use the `Theme.of(context).custom` extension (`connectedColor`, `disconnectedColor`, `watermark`) for app-specific colors. Add new semantic colors to `CustomColors` rather than hard-coding them in widgets.
- **Topic colors carry the meaning.** Every topic has a `TopicColor` picked from `TopicColor.defaultColors` (indigo, blue, pink, amberAccent, deepPurple, orange, deepOrange, brown, green, teal, lime). A new subscription gets a random one. Each message is shown as a `TopicChip` or `FastTopicChip` in its topic's color. Compute the text color from luminance (`> 0.5` → black, else white; see `ThemeDataEx.getTextColor`). A paused topic uses the `watermark` grey, and a selected chip uses `color.lighten(0.3)` (`common/colorExt.dart`). The high-volume grouped and sequential viewers use the lightweight stateless `FastTopicChip`. Keep it that way for performance, and use the full `TopicChip` (animation, delete, count) elsewhere.
- **Chips**: `InputChip` with elevation 2 and `titleSmall` (w600) text. Extra fields are separated by ` | `, e.g. `topic | # count | HH:mm:ss`. A new message plays a short scale "glow" (1.0 → 1.1 → 1.0 over 400 ms).
- **Typography** uses the Material text theme only: large time headers in the grouped viewer are `headlineMedium`; viewer headers are `titleLarge`. In the detail view, field labels are `titleMedium` and values are `headlineSmall` (`SelectableText` so they can be copied). Large numeric payloads are `headlineMedium`, text and JSON payloads are `bodyLarge` with `height: 1.7`, and small tags are `labelLarge`.
- **Buttons**: the theme gives Elevated, Outlined, Filled and Text buttons a minimum size of 150×48 and a corner radius of 8. Command and toolbar actions are `IconButton`s or borderless `ToggleButtons` with tooltips. Every icon-only control needs a localized `tooltip`.
- **Icons**: Material `Icons.*`. Add a custom glyph to `assets/fonts/AppIcons.ttf` only when Material has nothing suitable.
- **Spacing**: multiples of 4 (4, 6, 8, 12, 16, 24). Panels use 12 px padding, dialogs 16 px, and the gaps between detail-view sections are 24 px.
- **Disabled state**: controls that need an open project or a connection are disabled (`onPressed: null` / `enabled: false`), never hidden. Follow the existing `projectViewmodel.isProjectOpen` / `isConnected()` checks.

### Dialogs and forms

- Use `SimpleDialog` with a localized title, `contentPadding: EdgeInsets.all(16)` and a fixed-width `ConstrainedBox` (480 px for small dialogs). Wrap the dialog in `SrxTheme(data: CustomTheme.srxTheme)` where it isn't inherited.
- Lay out fields with `SrxFormRow` and `Expanded(flex: …)`, with `SizedBox(width: 16)` between fields. Inputs are `Reactive*` fields with `OutlineInputBorder()`, `isDense: true`, a localized `labelText` and `validationMessages` that use localized keys (`srx.common.fieldrequired`, …). The first field gets `autofocus: true`, and `onSubmitted` submits the dialog.
- The action row at the bottom is an `SrxFormRow` with a leading `Spacer(flex: 1)`, then an `OutlinedButton` for Cancel (`srx.common.cancel`), then the primary action(s) as `ElevatedButton`s, each `Expanded(flex: 5)`. Close dialogs via `GetIt.I.get<SrxNavigationService>().pop(result)`.
- For confirmations and errors, use `SrxDialog.yesNo(...)` and `SrxDialog.error(...)` instead of building an `AlertDialog`.
- Show transient errors with `errorSnackBar(message, context)` (floating, error color, 10 s).

## Coding rules (from `.github/copilot-instructions.md`)

- Every async-calling function is `async`, and async calls are always `await`ed.
- Each page/dialog has its own viewmodel (`SrxChangeNotifier`). A viewmodel does not import other viewmodels or repositories; it uses GetIt services such as `MessageViewer` and `ProjectManager`. Simple stateless dialogs may skip the viewmodel.
- Always use reactive forms. Define the `FormGroup`, its field-name constants and its validators in the viewmodel (see `add_topic_viewmodel.dart`).
- All UI text is localized via `'key'.tr()`. Keys are flat (no nesting except for plurals) and prefixed with the page or dialog name, e.g. `projectedit.port.label`. Add new keys to `assets/i18n/en.json`.
- Keep `build` methods short and split them into smaller `_buildX` methods.
- Esc cancels a dialog and Enter submits it.
- No `dynamic` where a concrete type is possible.
- Use `color.withValues(alpha: …)`, never `withOpacity`.
- Always use braces with `if`, even one-liners.
- Comment only non-obvious logic. Don't add comments like "method added".

## Notes

- Line endings: the repo uses CRLF on checkout, and git warns about LF in edited files. Don't mass-convert files.
- `windows/flutter/generated_plugins.cmake` is generated by Flutter. Commit it when plugins change, but don't hand-edit it.
- Bump the version in `pubspec.yaml` (`version`) and in `msix_config.msix_version` together for releases.
