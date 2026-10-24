import 'dart:async';
import 'dart:math';
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
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/recorder/engine/recording_player.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:mqttstudio/simulator/engine/simulator_runner.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';

// mqttstudio replay: plays a recording to a broker (doc/cli-design.md §7.1). One instance uses the app's
// RecordingPlayer; several instances run as a recorded device of the simulator, so {n} works like in the app.
class ReplayCommand extends CliCommand with BrokerOptions, RecordingArguments {
  @override
  final String name = 'replay';
  @override
  final String description = 'Play a recording to a broker.';

  @override
  String get invocation => 'mqttstudio replay <recording> [options]';

  ReplayCommand(CliContext context) : super(context) {
    argParser
      ..addOption('project', abbr: 'p', help: 'Saved project with the broker settings. Required unless --host is given.')
      ..addMultiOption('topic', abbr: 't', help: 'Recorded topic to play. Repeatable, all topics by default.')
      ..addOption('speed', defaultsTo: '1', help: '0.1 to 100, or max (limited by --max-rate).')
      ..addFlag('loop', negatable: false, help: 'Start over at the end of the range.')
      ..addOption('from', help: 'Start of the range as an offset, e.g. 5m.')
      ..addOption('to', help: 'End of the range as an offset, e.g. 12m30s.')
      ..addOption('compress-gaps', help: 'Shorten gaps longer than this to this.')
      ..addMultiOption('remap', help: 'Topic prefix rewrite <from>=<to>; <to> may contain {n}. Repeatable.')
      ..addOption('instances', defaultsTo: '1', help: 'Number of instances; more than one needs {n} in a remap.')
      ..addOption('instance-start', allowed: ['staggered', 'aligned', 'random'], defaultsTo: 'staggered')
      ..addOption('snapshot', allowed: ['publish', 'skip'], defaultsTo: 'publish', help: 'Retained snapshot first or not.')
      ..addOption('retain', allowed: ['as-recorded', 'never', 'always'], defaultsTo: 'as-recorded')
      ..addOption('qos', allowed: ['0', '1', '2'], help: 'QoS of all messages, as recorded by default.')
      ..addOption('duration', help: 'Stop after this time.')
      ..addOption('max-rate',
          defaultsTo: '${SimulationRules.maxRate.round()}',
          help: 'Refuse to start above this estimated rate in msg/s, at most ${SimulationRules.maxCliRate.round()}.')
      ..addFlag('reconnect', negatable: false, help: 'Reconnect after a lost connection and go on.')
      ..addFlag('dry-run', negatable: false, help: 'Print the plan without connecting.')
      ..addOption('stats-every', defaultsTo: '10s', help: 'Interval of the progress lines, 0 turns them off.');
    addBrokerOptions();
  }

  @override
  Future<int> run() async {
    var results = argResults!;
    var (library, info) = await findRecording(singleArgument('recording'));
    var projectName = results['project'] as String?;
    if (projectName == null && results['host'] == null) {
      usageException('--project or --host is required.');
    }
    checkBrokerOptions();
    var options = _playbackOptions(info);
    var instances = int.tryParse(results['instances'] as String) ?? 0;
    if (instances < 1) {
      usageException('--instances must be a number from 1.');
    }
    if (instances > 1 && options.isMaxSpeed) {
      usageException('--speed max needs a single instance.');
    }
    if (instances > 1 && !options.remaps.any((remap) => remap.to.contains('{n'))) {
      throw CliException(CliExitCode.invalid, 'With more than one instance a --remap target must contain {n}.');
    }
    var maxRate = double.tryParse(results['max-rate'] as String);
    if (maxRate == null || maxRate <= 0 || maxRate > SimulationRules.maxCliRate) {
      usageException('--max-rate must be a number between 1 and ${SimulationRules.maxCliRate.round()}.');
    }
    var project = projectName == null ? null : await findProject(projectName);
    var settings = connectionSettings(project?.mqttSettings);
    var estimate = RecordingPlayer.estimate(info, options, maxRate: maxRate);
    var rate = estimate.rate * instances;
    _printPlan(info, settings, options, instances, rate, estimate.peak);
    if (!options.isMaxSpeed && rate > maxRate) {
      throw CliException(CliExitCode.rateLimit,
          'The estimated rate of ${CliFormat.rate(rate)} is above --max-rate ${maxRate.round()}. Lower --speed or raise --max-rate.');
    }
    if (results['dry-run'] as bool) {
      out.event('done', {'exitCode': 0});
      return CliExitCode.ok.code;
    }
    var adapter = context.createAdapter();
    await connect(adapter, settings);
    var statsEvery = parseDuration(results['stats-every'] as String, 'stats-every');
    return _Replay(this, adapter, settings, library, info, options, instances, maxRate, statsEvery).execute();
  }

  PlaybackOptions _playbackOptions(RecordingInfo info) {
    var results = argResults!;
    var topics = results['topic'] as List<String>;
    for (var topic in topics) {
      if (!info.footer.topics.contains(topic)) {
        throw CliException(CliExitCode.notFound, 'The recording has no topic $topic.');
      }
    }
    var speedText = results['speed'] as String;
    var speed = speedText == 'max' ? PlaybackOptions.maxSpeed : double.tryParse(speedText);
    if (speed == null || (speed != PlaybackOptions.maxSpeed && (speed < 0.1 || speed > 100))) {
      usageException('--speed must be between 0.1 and 100, or max.');
    }
    var remaps = <TopicRemap>[];
    for (var text in results['remap'] as List<String>) {
      var equals = text.indexOf('=');
      if (equals <= 0) {
        usageException('--remap must look like <from>=<to>.');
      }
      remaps.add(TopicRemap(text.substring(0, equals), text.substring(equals + 1)));
    }
    var from = optionalDuration('from')?.inMicroseconds;
    var to = optionalDuration('to')?.inMicroseconds;
    if (from != null && to != null && to <= from) {
      usageException('--to must come after --from.');
    }
    var qos = results['qos'] as String?;
    return PlaybackOptions(
      topics: topics.isEmpty ? null : topics,
      speed: speed,
      loop: results['loop'] as bool,
      rangeStartMicros: from,
      rangeEndMicros: to,
      compressGapsOverMicros: optionalDuration('compress-gaps')?.inMicroseconds,
      remaps: remaps,
      snapshot: results['snapshot'] == 'skip' ? RetainedSnapshotMode.skip : RetainedSnapshotMode.publish,
      retain: switch (results['retain']) {
        'never' => RetainOverride.never,
        'always' => RetainOverride.always,
        _ => RetainOverride.asRecorded,
      },
      qos: qos == null ? null : MqttQos.values[int.parse(qos)],
    );
  }

  void _printPlan(RecordingInfo info, MqttSettings settings, PlaybackOptions options, int instances, double rate, double peak) {
    var topics = info.footer.topics.where(options.plays).toList();
    var speed = options.isMaxSpeed ? 'max' : '${options.speed}x';
    out.event(
        'plan',
        {
          'recording': info.name,
          'id': info.id,
          'broker': '${settings.hostname}:${settings.port}',
          'clientId': settings.clientId,
          'topics': topics.length,
          'messages': [for (var topic in topics) info.footer.summary.perTopic[topic]?.count ?? 0].fold<int>(0, (a, b) => a + b),
          'instances': instances,
          'speed': options.isMaxSpeed ? 'max' : options.speed,
          'estimatedRate': rate,
          'peakRate': peak,
        },
        text: [
          'MQTT Studio ${context.version} · replay',
          'Recording ${info.name} (${DurationParser.format(info.footer.duration)}, ${topics.length} topics)',
          'Broker    ${CliFormat.broker(settings)} as ${settings.clientId}',
          'Playback  $speed${options.loop ? ', loop' : ''}${instances > 1 ? ', $instances instances' : ''}',
          'Rate      ≈ ${CliFormat.rate(rate)}, peak ${CliFormat.rate(peak)}',
        ].join('\n'));
  }
}

// One replay, from the start until it stops
class _Replay {
  static final DateFormat _time = DateFormat('HH:mm:ss');
  static const Duration _socketFlushTime = Duration(milliseconds: 500);

  final ReplayCommand command;
  final MqttAdapter adapter;
  final MqttSettings settings;
  final RecordingLibrary library;
  final RecordingInfo info;
  final PlaybackOptions options;
  final int instances;
  final double maxRate;
  final Duration statsEvery;
  final Completer<String> _stopped = Completer();
  RecordingPlayer? _player;
  SimulatorRunner? _runner;
  late final SimulatedDevice _device;
  // sent by players that ended because the connection was lost
  int _sentBefore = 0;
  int _lastSent = 0;
  bool _reconnecting = false;

  _Replay(this.command, this.adapter, this.settings, this.library, this.info, this.options, this.instances, this.maxRate,
      this.statsEvery);

  Output get out => command.out;

  bool get _reconnect => command.argResults!['reconnect'] as bool;

  int get _sent => _sentBefore + (_player?.sent ?? _runner?.totalSent ?? 0);

  Future<int> execute() async {
    var interrupts = command.context.interrupts().listen((_) => _onInterrupt());
    adapter.onDisconnectedEvent.subscribe(_onDisconnected);
    var startedAt = clock.now();
    if (instances == 1) {
      await _startPlayer(null);
    } else {
      _startRunner();
    }
    out.event('started', {}, text: 'Started at ${_time.format(startedAt)}. Press Ctrl+C to stop.');
    Timer? durationTimer;
    var duration = command.optionalDuration('duration');
    if (duration != null) {
      durationTimer = Timer(duration, () => _stop('duration'));
    }
    Timer? statsTimer;
    if (statsEvery > Duration.zero) {
      statsTimer = Timer.periodic(statsEvery, (_) => _printStats());
    }

    var reason = await _stopped.future;
    durationTimer?.cancel();
    statsTimer?.cancel();
    adapter.onDisconnectedEvent.unsubscribe(_onDisconnected);
    var sent = _sent;
    await _player?.stop();
    await _player?.reader.close();
    _runner?.stopAll();
    _runner?.dispose();
    if (adapter.isConnected()) {
      adapter.disconnect();
      await Future.delayed(_socketFlushTime);
    }
    unawaited(interrupts.cancel());
    var exitCode = reason == 'connectionLost' ? CliExitCode.connectionLost : CliExitCode.ok;
    out.event('stopped', {'reason': reason, 'sent': sent, 'exitCode': exitCode.code},
        text: 'Stopped after ${DurationParser.format(clock.now().difference(startedAt))} (${_describe(reason)}): '
            '${CliFormat.count(sent)} messages.',
        level: OutputLevel.result);
    return exitCode.code;
  }

  static String _describe(String reason) => switch (reason) {
        'duration' => 'duration reached',
        'interrupted' => 'interrupted',
        'connectionLost' => 'connection lost',
        'finished' => 'end of the recording',
        _ => reason,
      };

  // after a reconnect the replay goes on where it was
  Future<void> _startPlayer(int? fromMicros) async {
    var reader = await library.open(info);
    var player = RecordingPlayer(reader, options, MqttAdapterPublisher(adapter), maxRate: maxRate, startPositionMicros: fromMicros);
    player.finishedEvent.subscribe((_) => _stop('finished'));
    player.connectionLostEvent.subscribe((_) => _onDisconnected(null));
    _player = player;
    await player.play();
  }

  void _startRunner() {
    var source = RecordedSource(
        recordingId: info.id,
        fileName: info.fileName,
        recordingName: info.name,
        playback: options,
        instanceStart: switch (command.argResults!['instance-start']) {
          'aligned' => InstanceStart.aligned,
          'random' => InstanceStart.randomPosition,
          _ => InstanceStart.staggered,
        });
    _device = SimulatedDevice(name: info.name, instanceCount: instances, kind: DeviceKind.recorded, recorded: source);
    var runner = SimulatorRunner(MqttAdapterPublisher(adapter), openRecording: (_) => library.store.open(info.fileName));
    runner.runStateChangedEvent.subscribe(_onRunStateChanged);
    _runner = runner;
    runner.startRecorded(_device);
  }

  bool _runnerStarted = false;

  void _onRunStateChanged(EventArgs? _) {
    if (_runner!.isAnyRunning) {
      _runnerStarted = true;
    } else if (_runnerStarted && !_reconnecting) {
      _stop('finished');
    }
  }

  void _stop(String reason) {
    if (!_stopped.isCompleted) {
      _stopped.complete(reason);
    }
  }

  void _onInterrupt() {
    if (_stopped.isCompleted) {
      command.context.forceExit(CliExitCode.interrupted.code);
      return;
    }
    _stop('interrupted');
  }

  void _onDisconnected(EventArgs? _) {
    if (_stopped.isCompleted || _reconnecting) {
      return;
    }
    if (!_reconnect) {
      _stop('connectionLost');
      return;
    }
    _reconnectLoop();
  }

  Future<void> _reconnectLoop() async {
    _reconnecting = true;
    var position = _player?.positionMicros;
    if (_player != null) {
      _sentBefore += _player!.sent;
      await _player!.stop();
      await _player!.reader.close();
      _player = null;
    }
    var attempt = 0;
    while (!_stopped.isCompleted && !adapter.isConnected()) {
      var delay = BrokerOptions.reconnectDelays[min(attempt, BrokerOptions.reconnectDelays.length - 1)];
      attempt++;
      out.event('reconnecting', {'attempt': attempt, 'delaySeconds': delay.inSeconds},
          text: 'Connection lost, reconnecting in ${delay.inSeconds} s (attempt $attempt)');
      await Future.delayed(delay);
      try {
        await adapter.connect(settings);
      } catch (_) {
        // tried again after the next delay
      }
    }
    if (!_stopped.isCompleted && adapter.isConnected()) {
      out.event('reconnected', {'attempts': attempt}, text: 'Reconnected.');
      if (instances == 1) {
        await _startPlayer(position);
      } else {
        // the instances start over
        _runner!.startRecorded(_device);
      }
    }
    _reconnecting = false;
  }

  void _printStats() {
    var sent = _sent;
    var rate = (sent - _lastSent) / (statsEvery.inMicroseconds / Duration.microsecondsPerSecond);
    _lastSent = sent;
    var position = _player?.positionMicros ?? _runner?.positionOf(_device.id) ?? 0;
    out.event(
        'stats',
        {
          'sent': sent,
          'rate': double.parse(rate.toStringAsFixed(1)),
          'position': position,
          if (_player != null) 'lag': _player!.lagMicros,
          if (_player != null) 'loop': _player!.loopCount,
        },
        text: '${_time.format(clock.now())}  sent ${CliFormat.count(sent).padRight(9)} '
            '${rate.toStringAsFixed(1).padLeft(7)} msg/s  at ${DurationParser.format(Duration(microseconds: position))}');
  }
}
