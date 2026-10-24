import 'dart:math';
import 'package:event/event.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/recorder/engine/recording_player.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:mqttstudio/simulator/simulator.dart';

// thrown when the playback would publish more messages per second than the app allows, together with the simulator
class PlaybackRateException implements Exception {
  final double rate;

  PlaybackRateException(this.rate);
}

// Plays recordings in the RECORDER tab on the main connection, to the broker of the open project (R10). Stops when
// that connection is lost or the project is closed (§6.5).
class PlaybackService {
  final RecordingLibrary library;
  final _mqttAdapter = GetIt.I.get<MqttAdapter>();
  final _projectManager = GetIt.I.get<ProjectManager>();
  final SimulatorPublisher _publisher;

  // state, position or counts changed
  final changedEvent = Event();
  final stoppedByDisconnectEvent = Event();
  final finishedEvent = Event();

  RecordingPlayer? _player;
  RecordingInfo? _recording;

  PlaybackService(this.library, {SimulatorPublisher? publisher})
      : _publisher = publisher ?? MqttAdapterPublisher(GetIt.I.get<MqttAdapter>()) {
    _mqttAdapter.onDisconnectedEvent.subscribe(_onDisconnected);
    _projectManager.projectClosedEvent.subscribe(_onProjectClosed);
  }

  void dispose() {
    _mqttAdapter.onDisconnectedEvent.unsubscribe(_onDisconnected);
    _projectManager.projectClosedEvent.unsubscribe(_onProjectClosed);
    _closePlayer();
  }

  RecordingInfo? get recording => _recording;

  RecordingPlayer? get player => _player;

  PlaybackState get state => _player?.state ?? PlaybackState.stopped;

  bool get isActive => state != PlaybackState.stopped;

  bool isPlayingRecording(String id) => _recording?.id == id && isActive;

  // msg/s the simulator leaves for the playback
  double get availableRate => max(0, SimulationRules.maxRate - _simulatorRate);

  double get _simulatorRate => GetIt.I.isRegistered<Simulator>() ? GetIt.I.get<Simulator>().runner.runningRate : 0;

  // starts the recording from its range start, or resumes it when it is paused
  Future<void> play(RecordingInfo info, PlaybackOptions options) async {
    if (_recording?.id == info.id && _player != null && state == PlaybackState.paused) {
      await _player!.play();
      return;
    }
    var estimate = RecordingPlayer.estimate(info, options, maxRate: availableRate);
    if (!options.isMaxSpeed && estimate.rate > availableRate) {
      throw PlaybackRateException(estimate.rate + _simulatorRate);
    }
    await _open(info, options);
    await _player!.play();
  }

  void pause() => _player?.pause();

  // stops and lets go of the recording's file
  Future<void> stop() async {
    await _player?.stop();
    await _closePlayer();
    changedEvent.broadcast();
  }

  // stops the playback if it plays this recording, so its file can be deleted
  Future<void> release(String recordingId) async {
    if (_recording?.id == recordingId) {
      await stop();
    }
  }

  Future<void> step(RecordingInfo info, PlaybackOptions options) async {
    if (_recording?.id != info.id || _player == null) {
      await _open(info, options);
    }
    await _player!.step();
  }

  void setSpeed(double speed) {
    _player?.maxRate = availableRate;
    _player?.setSpeed(speed);
  }

  void setLoop(bool loop) => _player?.setLoop(loop);

  // new options for the recording that is playing; it starts again from its range start
  Future<void> applyOptions(RecordingInfo info, PlaybackOptions options) async {
    if (_recording?.id == info.id && _player != null) {
      await _player!.setOptions(options);
    }
  }

  Future<void> _open(RecordingInfo info, PlaybackOptions options) async {
    await _closePlayer();
    var reader = await library.open(info);
    var player = RecordingPlayer(reader, options, _publisher, maxRate: availableRate);
    player.stateChangedEvent.subscribe(_onChanged);
    player.progressChangedEvent.subscribe(_onChanged);
    player.connectionLostEvent.subscribe(_onConnectionLost);
    player.finishedEvent.subscribe(_onFinished);
    _player = player;
    _recording = info;
  }

  // A stopped player is never resumed, so it closes its file right away. An open file would keep Windows from
  // deleting or replacing the recording.
  Future<void> _closePlayer() async {
    var player = _player;
    if (player == null) {
      return;
    }
    player.stateChangedEvent.unsubscribe(_onChanged);
    player.progressChangedEvent.unsubscribe(_onChanged);
    player.connectionLostEvent.unsubscribe(_onConnectionLost);
    player.finishedEvent.unsubscribe(_onFinished);
    player.dispose();
    _player = null;
    _recording = null;
    await player.reader.close();
  }

  void _onChanged(EventArgs? _) => changedEvent.broadcast();

  void _onFinished(EventArgs? _) {
    finishedEvent.broadcast();
    _closeAndNotify();
  }

  void _onConnectionLost(EventArgs? _) {
    stoppedByDisconnectEvent.broadcast();
    _closeAndNotify();
  }

  void _onDisconnected(EventArgs? _) {
    if (_player?.isPlaying ?? false) {
      stoppedByDisconnectEvent.broadcast();
    }
    stop();
  }

  void _onProjectClosed(EventArgs? _) => stop();

  Future<void> _closeAndNotify() async {
    await _closePlayer();
    changedEvent.broadcast();
  }
}
