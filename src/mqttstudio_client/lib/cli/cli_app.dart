import 'dart:async';
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:mqttstudio/cli/cli_context.dart';
import 'package:mqttstudio/cli/commands/doc_command.dart';
import 'package:mqttstudio/cli/commands/projects_command.dart';
import 'package:mqttstudio/cli/commands/record_command.dart';
import 'package:mqttstudio/cli/commands/recordings_command.dart';
import 'package:mqttstudio/cli/commands/replay_command.dart';
import 'package:mqttstudio/cli/commands/simulate_command.dart';
import 'package:mqttstudio/cli/exit_codes.dart';
import 'package:mqttstudio/cli/output.dart';

class _Runner extends CommandRunner<int> {
  final CliContext context;

  _Runner(this.context) : super('mqttstudio', 'Run MQTT Studio from the command line.');

  @override
  void printUsage() => context.stdout.writeln(usage);
}

// The headless CLI: parses the command line, runs the command and maps its result to an exit code.
// New commands are added in the constructor.
class CliApp {
  final CliContext context;
  late final _Runner _runner;

  CliApp(this.context) {
    _runner = _Runner(context)
      ..argParser.addFlag('version', negatable: false, help: 'Print the MQTT Studio version.')
      ..argParser.addOption('output', abbr: 'o', allowed: ['text', 'json'], defaultsTo: 'text', help: 'Output format.')
      ..argParser.addFlag('quiet', abbr: 'q', negatable: false, help: 'Only print errors and the final summary.')
      ..argParser.addFlag('verbose', abbr: 'v', negatable: false, help: 'Print per-topic details and MQTT client logs.')
      ..addCommand(ProjectsCommand(context))
      ..addCommand(SimulateCommand(context))
      ..addCommand(RecordCommand(context))
      ..addCommand(ReplayCommand(context))
      ..addCommand(RecordingsCommand(context))
      ..addCommand(DocCommand(context));
  }

  Future<int> run(List<String> args) async {
    ArgResults options;
    try {
      options = _runner.parse(args);
    } on UsageException catch (exc) {
      context.stderr.writeln(exc.message);
      context.stderr.writeln();
      context.stderr.writeln(exc.usage);
      return CliExitCode.usage.code;
    }

    context.verbose = options['verbose'] as bool;
    context.out = options['output'] == 'json'
        ? JsonLinesOutput(context.stdout, context.stderr, verbose: context.verbose)
        : TextOutput(context.stdout, context.stderr, quiet: options['quiet'] as bool, verbose: context.verbose);

    if (options['version'] as bool) {
      context.stdout.writeln('MQTT Studio ${context.version}');
      return CliExitCode.ok.code;
    }

    try {
      return await _runner.runCommand(options) ?? CliExitCode.ok.code;
    } on UsageException catch (exc) {
      context.out.error(exc.message);
      context.stderr.writeln();
      context.stderr.writeln(exc.usage);
      return CliExitCode.usage.code;
    } on CliException catch (exc) {
      context.out.error(exc.message, data: {'exitCode': exc.exitCode.code});
      return exc.exitCode.code;
    } catch (exc) {
      context.out.error('$exc', data: {'exitCode': CliExitCode.failure.code});
      return CliExitCode.failure.code;
    }
  }
}
