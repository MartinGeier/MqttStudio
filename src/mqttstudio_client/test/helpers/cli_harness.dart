import 'dart:async';
import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/cli/cli_app.dart';
import 'package:mqttstudio/cli/cli_context.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';
import 'package:mqttstudio/service/service_error.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'fake_mqtt_adapter.dart';
import 'package:mqttstudio/mqtt/mqtt_will.dart';

// Runs the CLI with fake projects, fake brokers and a memory recordings library
class FakeProjects implements ProjectSource {
  final List<Project> list;
  FakeProjects(this.list);

  @override
  Future<List<Project>> projects() async => list;
}

class UnreachableBroker extends FakeMqttAdapter {
  @override
  Future connect(MqttSettings mqttSettings, {MqttWill? will}) async =>
      throw SrxServiceException('Connection refused', ServiceError.MqttCannotConnect);
}

class Cli {
  final out = StringBuffer();
  final err = StringBuffer();
  // created inside fakeAsync, a stream of the real zone would complete its futures outside the fake time
  late StreamController<void> interrupts;
  final List<FakeMqttAdapter> adapters = [];
  final List<int> forcedExits = [];
  late final CliContext context;
  FakeMqttAdapter Function() newAdapter = () => FakeMqttAdapter();

  Cli(List<Project> projects, {Map<String, String> environment = const {}, RecordingLibrary? library}) {
    context = CliContext(
      version: '9.9.9',
      stdout: out,
      stderr: err,
      projects: FakeProjects(projects),
      createAdapter: () {
        var adapter = newAdapter();
        adapters.add(adapter);
        return adapter;
      },
      interrupts: () => interrupts.stream,
      environment: environment,
      forceExit: forcedExits.add,
      recordings: () async => library ?? RecordingLibrary(MemoryRecordingStore()),
    );
  }

  FakeMqttAdapter get adapter => adapters.single;

  List<Map<String, dynamic>> get events =>
      out.toString().trim().split('\n').map((line) => jsonDecode(line) as Map<String, dynamic>).toList();

  // runs the command inside fakeAsync, elapsing the given time
  int run(List<String> args, {Duration elapse = Duration.zero, void Function(FakeAsync async)? during}) {
    int? exitCode;
    fakeAsync((async) {
      interrupts = StreamController<void>.broadcast();
      CliApp(context).run(args).then((code) => exitCode = code);
      async.flushMicrotasks();
      during?.call(async);
      async.elapse(elapse);
      // the shutdown waits for the socket to send the last packets
      async.elapse(Duration(seconds: 2));
      async.flushMicrotasks();
    });
    expect(exitCode, isNotNull, reason: 'the command did not finish');
    return exitCode!;
  }
}

extension RealCli on Cli {
  // runs the command with real time, for commands that read or write files
  Future<int> runReal(List<String> args) {
    interrupts = StreamController<void>.broadcast();
    return CliApp(context).run(args);
  }
}
