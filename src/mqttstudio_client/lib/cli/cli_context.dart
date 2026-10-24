import 'dart:async';
import 'dart:io' as io;
import 'package:mqttstudio/cli/output.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';

// Read-only access to the saved projects. The CLI never writes to the store.
abstract class ProjectSource {
  Future<List<Project>> projects();
}

class LocalStoreProjectSource implements ProjectSource {
  @override
  Future<List<Project>> projects() => LocalStore().getProjects();
}

// Everything a command needs from its environment, replaceable in tests
class CliContext {
  final String version;
  final StringSink stdout;
  final StringSink stderr;
  final ProjectSource projects;
  final MqttAdapter Function() createAdapter;
  // Ctrl+C
  final Stream<void> Function() interrupts;
  final Map<String, String> environment;
  // ends the process at once, for a second Ctrl+C during shutdown
  final void Function(int exitCode) forceExit;

  // set by CliApp from the global options
  late Output out;
  bool verbose = false;

  CliContext({
    required this.version,
    required this.stdout,
    required this.stderr,
    required this.projects,
    required this.createAdapter,
    required this.interrupts,
    required this.environment,
    required this.forceExit,
  });

  factory CliContext.standard(String version) => CliContext(
        version: version,
        stdout: io.stdout,
        stderr: io.stderr,
        projects: LocalStoreProjectSource(),
        createAdapter: () => MqttAdapter(),
        interrupts: () => io.ProcessSignal.sigint.watch().map((_) {}),
        environment: io.Platform.environment,
        forceExit: io.exit,
      );
}
