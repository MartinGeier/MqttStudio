import 'dart:async';
import 'dart:io';
import 'package:clock/clock.dart';
import 'package:event/event.dart';
import 'package:intl/intl.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/cli/cli_context.dart';
import 'package:mqttstudio/cli/commands/broker_options.dart';
import 'package:mqttstudio/cli/commands/cli_command.dart';
import 'package:mqttstudio/cli/commands/recording_arguments.dart';
import 'package:mqttstudio/cli/duration_parser.dart';
import 'package:mqttstudio/cli/exit_codes.dart';
import 'package:mqttstudio/cli/output.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/engine/recorder_service.dart';
import 'package:mqttstudio/recorder/model/message_condition.dart';
import 'package:mqttstudio/recorder/model/recorder_config.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';

// mqttstudio record: records topics of a project's broker into the recordings library or a file
// (doc/cli-design.md §7.1). It uses the app's RecorderService, without the app's projects.
class RecordCommand extends CliCommand with BrokerOptions, RecordingArguments {
  @override
  final String name = 'record';
  @override
  final String description = 'Record topics into the recordings library or a file.';

  RecordCommand(CliContext context) : super(context) {
    argParser
      ..addOption('project', abbr: 'p', help: 'Saved project whose broker is recorded. Required.')
      ..addMultiOption('topic', abbr: 't', help: 'Topic filter to record, <filter>@<qos> sets the QoS (default 2). Required.')
      ..addMultiOption('exclude', abbr: 'x', help: 'Topic filter to leave out.')
      ..addOption('name', help: 'Name of the recording, by default the first filter.')
      ..addOption('out', help: 'Write the recording to this .mqttrec file instead of the recordings library.')
      ..addOption('duration', help: 'Stop after this time, counted from the start trigger.')
      ..addOption('max-messages', help: 'Stop after this many messages.')
      ..addOption('max-size', defaultsTo: '1GB', help: 'Stop at this size, e.g. 500MB.')
      ..addOption('start-when', help: 'Start when a message matches this condition, e.g. "plant/+/alarm".')
      ..addOption('pre-roll', help: 'Keep this much from before the start trigger, at most 10m.')
      ..addOption('stop-when', help: 'Stop when a message matches this condition.')
      ..addOption('post-roll', help: 'Keep recording this long after the stop condition matched.')
      ..addOption('flight', help: 'Flight recorder: keep this window in memory and save it on --save-when or Ctrl+C.')
      ..addOption('save-when', help: 'Flight recorder: save when a message matches this condition.')
      ..addOption('max-saves', help: 'Flight recorder: stop after this many saves.')
      ..addOption('flight-memory', help: 'Flight recorder: at most this much memory, e.g. 200MB.')
      ..addOption('flight-post-roll', defaultsTo: '30s', help: 'Flight recorder: keep capturing this long after a save trigger.')
      ..addOption('max-payload-size', help: 'Store longer payloads cut, e.g. 64KB.')
      ..addFlag('no-retained-snapshot', negatable: false, help: 'Leave out the retained messages sent on subscribe.')
      ..addFlag('reconnect', negatable: false, help: 'Reconnect after a lost connection instead of stopping.')
      ..addOption('stats-every', defaultsTo: '10s', help: 'Interval of the progress lines, 0 turns them off.');
    addBrokerOptions();
  }

  @override
  Future<int> run() async {
    var results = argResults!;
    var projectName = results['project'] as String?;
    if (projectName == null) {
      usageException('--project is required.');
    }
    var config = _config();
    checkBrokerOptions();
    var statsEvery = parseDuration(results['stats-every'] as String, 'stats-every');
    var project = await findProject(projectName);
    var settings = connectionSettings(project.mqttSettings);
    var out = results['out'] as String?;
    var library = out == null ? await context.recordings() : RecordingLibrary(FolderRecordingStore(File(out).absolute.parent));
    _printPlan(project.name, settings, config, out ?? library.location);

    var recorder = RecorderService(library,
        connectionFactory: context.createAdapter,
        appVersion: () async => context.version,
        withProjects: false,
        reconnect: results['reconnect'] as bool);
    try {
      return await _Session(this, recorder, config, settings, project.name, statsEvery, out).execute();
    } finally {
      recorder.dispose();
    }
  }

  RecorderConfig _config() {
    var results = argResults!;
    var topics = results['topic'] as List<String>;
    if (topics.isEmpty) {
      usageException('At least one --topic is required.');
    }
    var filters = [
      for (var topic in topics) _filter(topic, exclude: false),
      for (var topic in results['exclude'] as List<String>) _filter(topic, exclude: true),
    ];
    var flight = optionalDuration('flight');
    var maxPayload = results['max-payload-size'] as String?;
    var maxMessages = results['max-messages'] as String?;
    if (maxMessages != null && (int.tryParse(maxMessages) ?? 0) < 1) {
      usageException('--max-messages must be a number from 1.');
    }
    var maxSaves = results['max-saves'] as String?;
    if (maxSaves != null && (int.tryParse(maxSaves) ?? 0) < 1) {
      usageException('--max-saves must be a number from 1.');
    }
    var preRoll = optionalDuration('pre-roll');
    if (preRoll != null && preRoll.inSeconds > RecorderConfig.maxPreRollSeconds) {
      usageException('--pre-roll can be at most 10m.');
    }
    var flightMemory = results['flight-memory'] as String?;
    return RecorderConfig(
      name: (results['name'] as String?) ?? filters.first.filter,
      filters: filters,
      mode: flight == null ? RecorderMode.normal : RecorderMode.flightRecorder,
      startWhen: _condition('start-when'),
      preRollSeconds: preRoll?.inSeconds ?? 0,
      durationSeconds: optionalDuration('duration')?.inSeconds,
      maxMessages: maxMessages == null ? null : int.parse(maxMessages),
      maxBytes: parseSize(results['max-size'] as String, 'max-size'),
      stopWhen: _condition('stop-when'),
      postRollSeconds: optionalDuration('post-roll')?.inSeconds ?? 0,
      flight: flight == null
          ? null
          : FlightRecorderOptions(
              windowSeconds: flight.inSeconds,
              maxMemoryBytes: flightMemory == null ? null : parseSize(flightMemory, 'flight-memory'),
              saveWhen: _condition('save-when'),
              postRollSeconds: parseDuration(results['flight-post-roll'] as String, 'flight-post-roll').inSeconds,
              maxSaves: maxSaves == null ? null : int.parse(maxSaves),
            ),
      maxPayloadBytes: maxPayload == null ? null : parseSize(maxPayload, 'max-payload-size'),
      recordRetainedSnapshot: !(results['no-retained-snapshot'] as bool),
    );
  }

  RecorderFilter _filter(String text, {required bool exclude}) {
    var at = text.lastIndexOf('@');
    var filter = at > 0 ? text.substring(0, at) : text;
    var qos = MqttQos.exactlyOnce;
    if (at > 0) {
      var level = int.tryParse(text.substring(at + 1));
      if (level == null || level < 0 || level > 2) {
        usageException('The QoS of $text must be 0, 1 or 2.');
      }
      qos = MqttQos.values[level];
    }
    var issue = RecorderRules.validateFilter(filter);
    if (issue != null) {
      usageException(issue == FilterIssue.shared
          ? '$filter: shared subscriptions can\'t be recorded, they only get this client\'s share.'
          : '$filter is no valid topic filter.');
    }
    return RecorderFilter(filter, exclude: exclude, qos: qos);
  }

  MessageCondition? _condition(String option) {
    var text = argResults![option] as String?;
    if (text == null) {
      return null;
    }
    try {
      return MessageCondition.parse(text);
    } on FormatException catch (exc) {
      usageException('--$option: ${exc.message}');
    }
  }

  void _printPlan(String project, MqttSettings settings, RecorderConfig config, String? target) {
    var includes = config.includes.map((filter) => filter.filter).join(', ');
    var excludes = config.excludes.map((filter) => filter.filter).join(', ');
    var lines = [
      'MQTT Studio ${context.version} · record',
      'Project   $project',
      'Broker    ${CliFormat.broker(settings)} as ${settings.clientId}',
      'Topics    $includes${excludes.isEmpty ? '' : ' (without $excludes)'}',
      if (config.startWhen != null) 'Start     when ${config.startWhen!.toText()}, pre-roll ${config.preRollSeconds} s',
      if (config.stopWhen != null) 'Stop      when ${config.stopWhen!.toText()}, post-roll ${config.postRollSeconds} s',
      if (config.isFlightRecorder)
        'Flight    window ${DurationParser.format(Duration(seconds: config.flightOptions.windowSeconds))}'
            '${config.flightOptions.saveWhen == null ? ', saves on Ctrl+C' : ', saves when ${config.flightOptions.saveWhen!.toText()}'}',
      if (target != null) 'Into      $target',
    ];
    out.event(
        'plan',
        {
          'project': project,
          'broker': '${settings.hostname}:${settings.port}',
          'clientId': settings.clientId,
          'name': config.name,
          'filters': [for (var filter in config.filters) filter.toJson()],
          'mode': config.mode.name,
          if (target != null) 'target': target,
        },
        text: lines.join('\n'));
  }
}

// One recording session, from the start until it stops
class _Session {
  static final DateFormat _time = DateFormat('HH:mm:ss');

  final RecordCommand command;
  final RecorderService recorder;
  final RecorderConfig config;
  final MqttSettings settings;
  final String projectName;
  final Duration statsEvery;
  final String? outPath;
  final Completer<RecordingFinishedEventArgs> _finished = Completer();
  RecorderState _lastState = RecorderState.idle;
  int _lastReceived = 0;
  bool _interrupted = false;

  _Session(this.command, this.recorder, this.config, this.settings, this.projectName, this.statsEvery, this.outPath);

  Output get out => command.out;

  Future<int> execute() async {
    recorder.finishedEvent.subscribe(_onFinished);
    recorder.savedEvent.subscribe(_onSaved);
    recorder.errorEvent.subscribe(_onError);
    try {
      await recorder.start(config, settings: settings, projectName: projectName);
    } catch (exc) {
      throw CliException(CliExitCode.connectFailed, 'Cannot start recording: $exc');
    }
    var startedAt = clock.now();
    out.event('started', {}, text: 'Started at ${_time.format(startedAt)}. Press Ctrl+C to stop.');
    // after the started event, so waiting for the trigger comes after it
    recorder.stateChangedEvent.subscribe(_onStateChanged);
    _onStateChanged(null);
    var interrupts = command.context.interrupts().listen((_) => _onInterrupt());
    Timer? statsTimer;
    if (statsEvery > Duration.zero) {
      statsTimer = Timer.periodic(statsEvery, (_) => _printStats());
    }

    var finished = await _finished.future;
    statsTimer?.cancel();
    unawaited(interrupts.cancel());
    var info = finished.info;
    String? file;
    if (info != null) {
      file = await _place(info);
    }
    var reason = _interrupted && finished.reason == RecordingStopReason.user ? 'interrupted' : finished.reason.name;
    var exitCode = switch (finished.reason) {
      RecordingStopReason.connectionLost => CliExitCode.connectionLost,
      RecordingStopReason.writeError => CliExitCode.failure,
      _ => CliExitCode.ok,
    };
    var messages = info?.footer.summary.messages ?? 0;
    out.event(
        'stopped',
        {
          'reason': reason,
          'messages': messages,
          if (info != null) 'id': info.id,
          if (file != null) 'file': file,
          'saves': recorder.flightSaves,
          'exitCode': exitCode.code,
        },
        text: info == null
            ? (config.isFlightRecorder
                ? 'Stopped (${_describe(reason)}) after ${recorder.flightSaves} saves.'
                : 'Stopped (${_describe(reason)}). Nothing was recorded.')
            : 'Stopped (${_describe(reason)}): ${CliFormat.count(messages)} messages in $file',
        level: OutputLevel.result);
    return exitCode.code;
  }

  static String _describe(String reason) => switch (reason) {
        'interrupted' => 'interrupted',
        'duration' => 'duration reached',
        'maxMessages' => 'message limit reached',
        'maxBytes' => 'size limit reached',
        'stopCondition' => 'stop condition matched',
        'maxSaves' => 'all saves done',
        'connectionLost' => 'connection lost',
        'writeError' => 'write error',
        _ => reason,
      };

  // --out: the file gets the requested path; else its path in the library
  Future<String> _place(RecordingInfo info) async {
    var location = recorder.library.location;
    var path = location == null ? info.fileName : '$location${Platform.pathSeparator}${info.fileName}';
    if (outPath == null || location == null) {
      return path;
    }
    var target = File(outPath!).absolute.path;
    if (target != File(path).absolute.path) {
      await File(path).rename(target);
    }
    return target;
  }

  void _onStateChanged(EventArgs? _) {
    var state = recorder.state;
    if (state == RecorderState.waiting && _lastState != RecorderState.waiting) {
      out.event('waitingForTrigger', {'condition': config.startWhen?.toText()},
          text: 'Waiting for ${config.startWhen?.toText()}');
    }
    if (_lastState == RecorderState.waiting && state == RecorderState.recording) {
      out.event('triggerFired', {}, text: 'Start condition matched, recording.');
    }
    if (state == RecorderState.reconnecting && _lastState != RecorderState.reconnecting) {
      out.event('reconnecting', {'attempt': recorder.reconnectAttempt}, text: 'Connection lost, reconnecting.');
    }
    _lastState = state;
  }

  void _onSaved(RecordingFinishedEventArgs args) {
    var info = args.info!;
    var location = recorder.library.location;
    var file = location == null ? info.fileName : '$location${Platform.pathSeparator}${info.fileName}';
    out.event('saved', {'file': file, 'id': info.id, 'messages': info.footer.summary.messages},
        text: 'Saved ${CliFormat.count(info.footer.summary.messages)} messages to $file', level: OutputLevel.result);
  }

  void _onError(RecorderErrorEventArgs args) => out.error(args.message);

  void _onFinished(RecordingFinishedEventArgs args) {
    if (!_finished.isCompleted) {
      _finished.complete(args);
    }
  }

  // Ctrl+C stops and saves; a flight recorder without --save-when saves its window first
  void _onInterrupt() {
    if (_interrupted) {
      command.context.forceExit(CliExitCode.interrupted.code);
      return;
    }
    _interrupted = true;
    if (config.isFlightRecorder && config.flightOptions.saveWhen == null) {
      recorder.saveFlightRecording();
    }
    recorder.stop();
  }

  void _printStats() {
    var received = recorder.received;
    var rate = (received - _lastReceived) / (statsEvery.inMicroseconds / Duration.microsecondsPerSecond);
    _lastReceived = received;
    out.event(
        'stats',
        {
          'received': received,
          'stored': recorder.storedMessages,
          'rate': double.parse(rate.toStringAsFixed(1)),
          'bytes': recorder.storedBytes,
        },
        text: '${_time.format(clock.now())}  received ${CliFormat.count(received).padRight(9)} '
            '${rate.toStringAsFixed(1).padLeft(7)} msg/s  stored ${CliFormat.count(recorder.storedMessages)}');
  }
}
