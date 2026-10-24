import 'dart:async';
import 'dart:math';
import 'package:clock/clock.dart';
import 'package:event/event.dart';
import 'package:intl/intl.dart';
import 'package:mqttstudio/cli/cli_context.dart';
import 'package:mqttstudio/cli/commands/broker_options.dart';
import 'package:mqttstudio/cli/commands/cli_command.dart';
import 'package:mqttstudio/cli/duration_parser.dart';
import 'package:mqttstudio/cli/exit_codes.dart';
import 'package:mqttstudio/cli/output.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/recorder/engine/recording_player.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:mqttstudio/simulator/engine/simulator_runner.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';

// mqttstudio simulate: runs the simulation of a saved project, or some of its devices (doc/cli-design.md §2.4)
class SimulateCommand extends CliCommand with BrokerOptions {

  @override
  final String name = 'simulate';
  @override
  final String description = 'Run the simulation of a saved project.';

  SimulateCommand(CliContext context) : super(context) {
    argParser
      ..addOption('project', abbr: 'p', help: 'Saved project, matched by name. Required.')
      ..addMultiOption('device', abbr: 'd', help: 'Device to run, by name or id. Repeatable, all devices by default.')
      ..addOption('duration', help: 'Stop after this time, e.g. 90s, 15m or 1h30m. Runs until Ctrl+C by default.')
      ..addOption('max-rate',
          help: 'Refuse to start above this estimated rate in msg/s, at most ${SimulationRules.maxCliRate.round()}.',
          defaultsTo: '${SimulationRules.maxRate.round()}')
      ..addOption('seed', help: 'Seed of the generators, two runs with the same seed publish the same payloads.')
      ..addFlag('dry-run', negatable: false, help: 'Print the plan without connecting.');
    addBrokerOptions();
    argParser
      ..addFlag('reconnect', negatable: false, help: 'Reconnect after a lost connection instead of stopping.')
      ..addFlag('clear-retained', negatable: false, help: 'Clear the retained messages of the topics on exit.')
      ..addOption('stats-every', defaultsTo: '10s', help: 'Interval of the progress lines, 0 turns them off.');
  }

  @override
  Future<int> run() async {
    var options = _parseOptions();
    var projectName = argResults!['project'] as String?;
    if (projectName == null) {
      usageException('--project is required.');
    }
    var project = await findProject(projectName);
    var devices = _selectDevices(project.simulation);
    var topics = [for (var device in devices) for (var topic in device.topics) (device, topic)];
    _validate(project.simulation, devices, topics);
    var recordings = await _findRecordings(devices);

    var rate = SimulationRules.estimateRate(topics) +
        recordings.entries.fold(
            0.0,
            (sum, entry) =>
                sum + RecordingPlayer.estimate(entry.value, entry.key.recorded!.playback).rate * entry.key.instanceCount);
    var settings = connectionSettings(project.mqttSettings);
    _printPlan(project, settings, devices, rate, recordings);
    if (rate > options.maxRate) {
      throw CliException(CliExitCode.rateLimit,
          'The estimated rate of ${CliFormat.rate(rate)} is above --max-rate ${options.maxRate.round()}. '
          'Increase the intervals, reduce the instances or raise --max-rate.');
    }
    if (argResults!['dry-run'] as bool) {
      _printTopics(devices, recordings);
      out.event('done', {'exitCode': 0});
      return CliExitCode.ok.code;
    }

    var adapter = context.createAdapter();
    await connect(adapter, settings);
    return _Run(this, adapter, settings, devices, topics, options, recordings).execute();
  }

  // the recordings of the recorded devices, by device; a missing one ends the run before connecting (D23)
  Future<Map<SimulatedDevice, RecordingInfo>> _findRecordings(List<SimulatedDevice> devices) async {
    var recorded = devices.where((device) => device.isRecorded).toList();
    if (recorded.isEmpty) {
      return {};
    }
    library = await context.recordings();
    var found = <SimulatedDevice, RecordingInfo>{};
    for (var device in recorded) {
      var source = device.recorded!;
      var info = await library!.findSource(source.recordingId, source.fileName);
      if (info == null) {
        throw CliException(CliExitCode.notFound,
            'The recording "${source.recordingName}" of device "${device.name}" is not in ${library!.location ?? 'the recordings'}.');
      }
      found[device] = info;
    }
    return found;
  }

  RecordingLibrary? library;

  _Options _parseOptions() {
    var results = argResults!;
    Duration? duration;
    if (results['duration'] != null) {
      duration = parseDuration(results['duration'] as String, 'duration');
    }
    var maxRate = double.tryParse(results['max-rate'] as String);
    if (maxRate == null || maxRate <= 0 || maxRate > SimulationRules.maxCliRate) {
      usageException('--max-rate must be a number between 1 and ${SimulationRules.maxCliRate.round()}.');
    }
    int? seed;
    if (results['seed'] != null) {
      seed = int.tryParse(results['seed'] as String);
      if (seed == null) {
        usageException('--seed must be a whole number.');
      }
    }
    var statsEvery = parseDuration(results['stats-every'] as String, 'stats-every');
    checkBrokerOptions();
    return _Options(duration, maxRate, seed, statsEvery, results['reconnect'] as bool, results['clear-retained'] as bool);
  }

  List<SimulatedDevice> _selectDevices(Simulation simulation) {
    var wanted = argResults!['device'] as List<String>;
    if (wanted.isEmpty) {
      return simulation.devices;
    }
    var selected = <SimulatedDevice>[];
    for (var name in wanted) {
      var device = simulation.deviceById(name) ?? _deviceByName(simulation, name);
      if (!selected.contains(device)) {
        selected.add(device);
      }
    }
    return selected;
  }

  SimulatedDevice _deviceByName(Simulation simulation, String name) {
    var exact = simulation.devices.where((device) => device.name == name).toList();
    var matches = exact.isNotEmpty
        ? exact
        : simulation.devices.where((device) => device.name.toLowerCase() == name.toLowerCase()).toList();
    if (matches.length == 1) {
      return matches.single;
    }
    if (matches.length > 1) {
      throw CliException(CliExitCode.notFound,
          'The device name "$name" is used more than once, use one of the ids: ${matches.map((d) => d.id).join(', ')}');
    }
    var available = simulation.devices.map((device) => device.name).join(', ');
    throw CliException(CliExitCode.notFound, 'Device "$name" not found. Devices of the project: $available');
  }

  void _validate(Simulation simulation, List<SimulatedDevice> devices, List<(SimulatedDevice, SimulatedTopic)> topics) {
    if (topics.isEmpty && !devices.any((device) => device.isRecorded)) {
      throw CliException(CliExitCode.invalid, 'The selected devices have no topics.');
    }
    var issues = SimulationRules.validateSimulation(simulation, devices);
    if (issues.isNotEmpty) {
      throw CliException(CliExitCode.invalid, 'The simulation is not valid:\n${issues.map((i) => '  ${i.describe()}').join('\n')}');
    }
  }

  void _printPlan(Project project, MqttSettings settings, List<SimulatedDevice> devices, double rate,
      Map<SimulatedDevice, RecordingInfo> recordings) {
    var deviceLines = devices.map((device) {
      var recording = recordings[device];
      if (recording != null) {
        return '${device.name}: ${CliFormat.instances(device)}, recording "${recording.name}" at '
            '${_speed(device.recorded!.playback.speed)}${device.recorded!.playback.loop ? ', loop' : ''}';
      }
      return '${device.name}: ${CliFormat.instances(device)}, ${device.topics.length} '
          '${device.topics.length == 1 ? 'topic' : 'topics'}';
    }).toList();
    var text = [
      'MQTT Studio ${context.version} · simulate',
      'Project   ${project.name}${project.lastUsed == null ? '' : ' (as last saved)'}',
      'Broker    ${CliFormat.broker(settings)} as ${settings.clientId}',
      'Devices   ${deviceLines.join('\n          ')}',
      'Rate      ≈ ${CliFormat.rate(rate)}',
    ].join('\n');
    out.event(
        'plan',
        {
          'project': project.name,
          'broker': '${settings.hostname}:${settings.port}',
          'protocol': settings.protocolVersion.name,
          'clientId': settings.clientId,
          'devices': [
            for (var device in devices)
              {
                'id': device.id,
                'name': device.name,
                'instances': device.instanceCount,
                'topics': recordings[device]?.footer.topics.where(device.recorded!.playback.plays).length ??
                    device.topics.length,
                if (recordings[device] != null) 'recording': recordings[device]!.name,
              }
          ],
          'estimatedRate': rate,
        },
        text: text);
  }

  static String _speed(double speed) => speed == speed.roundToDouble() ? '${speed.round()}x' : '${speed}x';

  void _printTopics(List<SimulatedDevice> devices, Map<SimulatedDevice, RecordingInfo> recordings) {
    for (var device in devices) {
      var recording = recordings[device];
      if (recording != null) {
        for (var topic in recording.footer.topics.where(device.recorded!.playback.plays)) {
          var target = SimulationRules.recordedTarget(device, topic);
          out.event('topic', {'device': device.name, 'topic': topic, 'recorded': true, 'target': target},
              text: '  ${device.name} / $topic  recorded  → $target');
        }
      }
      for (var topic in device.topics) {
        var resolved = SimulationRules.resolvedTopics(device, topic);
        out.event(
            'topic',
            {'device': device.name, 'topic': topic.topic, 'generator': topic.generator.type.key, 'resolved': resolved},
            text: '  ${device.name} / ${topic.topic}  ${CliFormat.generator(topic.generator.type)}, '
                '${CliFormat.interval(topic.interval)}  → '
                '${resolved.length == 1 ? resolved.first : '${resolved.first} … ${resolved.last}'}');
      }
    }
  }

}

class _Options {
  final Duration? duration;
  final double maxRate;
  final int? seed;
  final Duration statsEvery;
  final bool reconnect;
  final bool clearRetained;

  _Options(this.duration, this.maxRate, this.seed, this.statsEvery, this.reconnect, this.clearRetained);
}

// One run of the simulation, from the start until it stops
class _Run {
  static final DateFormat _time = DateFormat('HH:mm:ss');
  // the process ends right after the command, the socket needs a moment to send the last packets
  static const Duration _socketFlushTime = Duration(milliseconds: 500);

  final SimulateCommand command;
  final MqttAdapter adapter;
  final MqttSettings settings;
  final List<SimulatedDevice> devices;
  final List<(SimulatedDevice, SimulatedTopic)> topics;
  final _Options options;
  late final SimulatorRunner runner;
  final Completer<String> _stopped = Completer();
  bool _reconnecting = false;
  int _lastSent = 0;

  final Map<SimulatedDevice, RecordingInfo> recordings;

  _Run(this.command, this.adapter, this.settings, this.devices, this.topics, this.options, this.recordings);

  Output get out => command.out;

  Future<int> execute() async {
    runner = SimulatorRunner(MqttAdapterPublisher(adapter), seed: options.seed, openRecording: (source) async {
      var info = recordings.entries.firstWhere((entry) => entry.key.recorded == source).value;
      return command.library!.store.open(info.fileName);
    });
    runner.topicErrorEvent.subscribe(_onTopicError);
    adapter.onDisconnectedEvent.subscribe(_onDisconnected);
    var interrupts = command.context.interrupts().listen((_) => _onInterrupt());
    var startedAt = clock.now();

    for (var device in devices) {
      runner.startDevice(device);
    }
    runner.runStateChangedEvent.subscribe(_onRunStateChanged);
    _wasRunning = runner.isAnyRunning;
    out.event('started', {}, text: 'Started at ${_time.format(startedAt)}. Press Ctrl+C to stop.');

    Timer? durationTimer;
    if (options.duration != null) {
      durationTimer = Timer(options.duration!, () => _stop('duration'));
    }
    Timer? statsTimer;
    if (options.statsEvery > Duration.zero) {
      statsTimer = Timer.periodic(options.statsEvery, (_) => _printStats());
    }

    var reason = await _stopped.future;
    var runTime = clock.now().difference(startedAt);

    durationTimer?.cancel();
    statsTimer?.cancel();
    runner.stopAll();
    adapter.onDisconnectedEvent.unsubscribe(_onDisconnected);
    if (options.clearRetained && adapter.isConnected()) {
      var cleared = runner.clearRetained(topics);
      await Future.delayed(_socketFlushTime);
      out.event('retainedCleared', {'topics': cleared}, text: 'Cleared $cleared retained topics.');
    }
    if (adapter.isConnected()) {
      adapter.disconnect();
      await Future.delayed(_socketFlushTime);
    }
    // nothing depends on the end of the cancel, and its future belongs to the root zone
    unawaited(interrupts.cancel());
    runner.dispose();

    var exitCode = reason == 'connectionLost' ? CliExitCode.connectionLost : CliExitCode.ok;
    var sent = runner.totalSent;
    var errors = runner.errorCount;
    out.event(
        'stopped',
        {'reason': reason, 'sent': sent, 'errors': errors, 'exitCode': exitCode.code},
        text: 'Stopped after ${DurationParser.format(runTime)} (${_describe(reason)}): '
            '${CliFormat.count(sent)} messages, $errors ${errors == 1 ? 'error' : 'errors'}.',
        level: OutputLevel.result);
    return exitCode.code;
  }

  static String _describe(String reason) {
    switch (reason) {
      case 'duration':
        return 'duration reached';
      case 'interrupted':
        return 'interrupted';
      case 'connectionLost':
        return 'connection lost';
      case 'finished':
        return 'everything finished';
    }
    return reason;
  }

  // Recorded devices without loop end, and topics can fail. Once nothing runs any more, the run ends instead of
  // waiting for Ctrl+C.
  void _onRunStateChanged(EventArgs? _) {
    if (runner.isAnyRunning) {
      _wasRunning = true;
    } else if (_wasRunning || runner.errorCount > 0) {
      _stop('finished');
    }
  }

  bool _wasRunning = false;

  void _stop(String reason) {
    if (!_stopped.isCompleted) {
      _stopped.complete(reason);
    }
  }

  void _onInterrupt() {
    if (_stopped.isCompleted) {
      // a second Ctrl+C while shutting down
      command.context.forceExit(CliExitCode.interrupted.code);
      return;
    }
    _stop('interrupted');
  }

  void _printStats() {
    var sent = runner.totalSent;
    var seconds = options.statsEvery.inMicroseconds / Duration.microsecondsPerSecond;
    var rate = (sent - _lastSent) / seconds;
    _lastSent = sent;
    var errors = runner.errorCount;
    out.event('stats', {'sent': sent, 'rate': double.parse(rate.toStringAsFixed(1)), 'errors': errors},
        text: '${_time.format(clock.now())}  sent ${CliFormat.count(sent).padRight(9)} '
            '${rate.toStringAsFixed(1).padLeft(7)} msg/s  errors $errors');
  }

  void _onTopicError(TopicErrorEventArgs args) {
    out.event('topicError', {'device': args.device, 'topic': args.topic, 'message': args.message},
        text: 'Error     ${args.device} / ${args.topic}: ${args.message}', level: OutputLevel.result);
  }

  void _onDisconnected(EventArgs _) {
    if (_stopped.isCompleted) {
      return;
    }
    if (!options.reconnect) {
      _stop('connectionLost');
      return;
    }
    if (!_reconnecting) {
      _reconnect();
    }
  }

  // the runner keeps its timers and skips messages until the connection is back
  Future _reconnect() async {
    _reconnecting = true;
    var attempt = 0;
    while (!_stopped.isCompleted && !adapter.isConnected()) {
      var delay = BrokerOptions.reconnectDelays[min(attempt, BrokerOptions.reconnectDelays.length - 1)];
      attempt++;
      out.event('reconnecting', {'attempt': attempt, 'delaySeconds': delay.inSeconds},
          text: 'Connection lost, reconnecting in ${delay.inSeconds} s (attempt $attempt)');
      await Future.delayed(delay);
      if (_stopped.isCompleted) {
        break;
      }
      try {
        await adapter.connect(settings);
      } catch (_) {
        // tried again after the next delay
      }
    }
    _reconnecting = false;
    if (adapter.isConnected() && !_stopped.isCompleted) {
      out.event('reconnected', {'attempts': attempt}, text: 'Reconnected.');
    }
  }
}
