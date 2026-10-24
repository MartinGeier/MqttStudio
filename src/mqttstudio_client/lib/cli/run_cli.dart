import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:mqttstudio/cli/cli_app.dart';
import 'package:mqttstudio/cli/cli_context.dart';

const String _versionArgument = '--app-version=';

// Entry point of the headless CLI, main() calls it when the app is started with --cli. Only what the commands need
// is set up: no window content, no dialogs, no tracking.
Future<int> runCli(List<String> args) async {
  // the console launcher passes the version from pubspec.yaml first, the build number is not shown
  var version = 'development build';
  if (args.isNotEmpty && args.first.startsWith(_versionArgument)) {
    version = args.first.substring(_versionArgument.length).split('+').first;
    args = args.sublist(1);
  }
  WidgetsFlutterBinding.ensureInitialized();
  var context = CliContext.standard(version);
  // the app logs with print, those lines must not mix with the output of the commands
  return runZoned(() => CliApp(context).run(args),
      zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
    if (context.verbose) {
      context.stderr.writeln(line);
    }
  }));
}
