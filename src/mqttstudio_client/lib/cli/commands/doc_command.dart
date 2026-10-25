import 'dart:async';
import 'dart:io';
import 'package:clock/clock.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/cli/cli_context.dart';
import 'package:mqttstudio/cli/commands/broker_options.dart';
import 'package:mqttstudio/cli/commands/cli_command.dart';
import 'package:mqttstudio/cli/commands/recording_arguments.dart';
import 'package:mqttstudio/cli/duration_parser.dart';
import 'package:mqttstudio/cli/exit_codes.dart';
import 'package:mqttstudio/cli/output.dart';
import 'package:mqttstudio/documentation/check_service.dart';
import 'package:mqttstudio/documentation/discovery_service.dart';
import 'package:mqttstudio/documentation/engine/conformance_checker.dart';
import 'package:mqttstudio/documentation/engine/discovery_merger.dart';
import 'package:mqttstudio/documentation/export/asyncapi_importer.dart';
import 'package:mqttstudio/documentation/export/doc_export.dart';
import 'package:mqttstudio/documentation/export/import_merge.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';

// mqttstudio doc …: the topic documentation from the command line (doc/documentation-design.md §10). The CLI never
// writes to the project store, so discover and import write the resulting documentation to an AsyncAPI file
// (--out) that the app's IMPORT reads back.
class DocCommand extends CliCommand {
  @override
  final String name = 'doc';
  @override
  final String description = 'Discover, check, export and import the topic documentation of a project.';

  DocCommand(CliContext context) : super(context) {
    addSubcommand(DocDiscoverCommand(context));
    addSubcommand(DocCheckCommand(context));
    addSubcommand(DocExportCommand(context));
    addSubcommand(DocImportCommand(context));
  }
}

mixin _ProjectOption on CliCommand {
  void addProjectOption() =>
      argParser.addOption('project', abbr: 'p', help: 'Saved project whose documentation is used. Required.');

  Future<Project> loadProject() async {
    var name = argResults!['project'] as String?;
    if (name == null) {
      usageException('--project is required.');
    }
    return findProject(name);
  }

  // an MQTT Studio AsyncAPI export restores everything, so the app can import the result
  Future<String> writeDocumentation(TopicDocumentation documentation, String path, Project project) async {
    var format = path.toLowerCase().endsWith('.json') ? DocExportFormat.asyncapiJson : DocExportFormat.asyncapiYaml;
    var text = DocExport.run(documentation, DocExportOptions(format, includeObserved: true),
        broker: project.mqttSettings, exportedAt: clock.now());
    var file = File(path).absolute;
    try {
      await file.writeAsString(text);
    } on FileSystemException catch (exc) {
      throw CliException(CliExitCode.failure, 'Cannot write ${file.path}: ${exc.osError?.message ?? exc.message}');
    }
    return file.path;
  }
}

// a waiting run that Ctrl+C ends early; a second Ctrl+C exits at once
Future<void> _untilDone(CliContext context, Future<void> done, void Function() stop) async {
  var interrupted = false;
  var interrupts = context.interrupts().listen((_) {
    if (interrupted) {
      context.forceExit(CliExitCode.interrupted.code);
      return;
    }
    interrupted = true;
    stop();
  });
  try {
    await done;
  } finally {
    unawaited(interrupts.cancel());
  }
}

class DocDiscoverCommand extends CliCommand with BrokerOptions, RecordingArguments, _ProjectOption {
  @override
  final String name = 'discover';
  @override
  final String description = 'Discover topics from the broker or a recording and compare them with the documentation.';

  DocDiscoverCommand(CliContext context) : super(context) {
    addProjectOption();
    argParser
      ..addMultiOption('filter', abbr: 't', help: 'Topic filter to discover. Required.')
      ..addMultiOption('exclude', abbr: 'x', help: 'Topic filter to leave out.')
      ..addOption('duration', help: 'Listen this long, default 5m. Ctrl+C stops earlier.')
      ..addOption('count', help: 'Stop after this many messages instead of a duration.')
      ..addOption('from-recording', help: 'Read a recording (name, id or .mqttrec file) instead of the broker.')
      ..addOption('out',
          help: 'Apply the result with the review defaults and write the documentation to this AsyncAPI file '
              '(.yaml or .json). Import it in the app.')
      ..addFlag('no-templates', negatable: false, help: 'Do not detect topic templates.')
      ..addFlag('no-schemas', negatable: false, help: 'Do not infer JSON schemas.')
      ..addFlag('reconnect', negatable: false, help: 'Reconnect after a lost connection instead of stopping.');
    addBrokerOptions();
  }

  @override
  Future<int> run() async {
    var results = argResults!;
    var settings = _settings();
    checkBrokerOptions();
    var project = await loadProject();
    var documentation = TopicDocumentation.fromJson(project.documentation.toJson());
    var recordingText = results['from-recording'] as String?;
    RecordingInfo? recording;
    var source = DiscoverySource.live;
    var broker = connectionSettings(project.mqttSettings);
    var discovery = DiscoveryService(
        connectionFactory: context.createAdapter, withProjects: false, reconnect: results['reconnect'] as bool);
    try {
      var library = await context.recordings();
      if (recordingText != null) {
        (library, recording) = await findRecording(recordingText);
        source = DiscoverySource.recording;
      }
      out.event(
          'plan',
          {
            'project': project.name,
            'source': source.name,
            if (recording != null) 'recording': recording.name else 'broker': '${broker.hostname}:${broker.port}',
            'filters': [for (var filter in settings.filters) '${filter.exclude ? '-' : ''}${filter.filter}'],
          },
          text: [
            'MQTT Studio ${context.version} · doc discover',
            'Project   ${project.name}',
            if (recording != null) 'Recording ${recording.name}' else 'Broker    ${CliFormat.broker(broker)}',
            'Topics    ${settings.filters.map((filter) => '${filter.exclude ? '-' : ''}${filter.filter}').join(', ')}',
          ].join('\n'));
      var done = Completer<void>();
      discovery.resultEvent.subscribe((_) => done.isCompleted ? null : done.complete());
      discovery.stateChangedEvent.subscribe((_) {
        if (!discovery.isRunning && !done.isCompleted) {
          done.complete();
        }
      });
      discovery.errorEvent.subscribe((args) => out.error(args.message));
      try {
        await discovery.start(settings,
            source: source, recording: recording, documentation: documentation, broker: broker, library: library);
      } catch (exc) {
        throw CliException(CliExitCode.connectFailed, 'Cannot start the discovery: $exc');
      }
      if (source == DiscoverySource.live) {
        out.event('started', {}, text: 'Listening. Press Ctrl+C to stop.');
      }
      await _untilDone(context, done.future, () => unawaited(discovery.stop()));
      var result = discovery.lastResult;
      if (result == null) {
        throw CliException(CliExitCode.failure, 'The discovery has no result.');
      }
      _printResult(result);
      var outPath = results['out'] as String?;
      if (outPath != null) {
        DiscoveryMerger.apply(documentation, result, settings, isMqtt5: broker.isMqtt5);
        var file = await writeDocumentation(documentation, outPath, project);
        out.event('written', {'file': file}, text: 'Documentation written to $file', level: OutputLevel.result);
      }
      return (discovery.lostConnection ? CliExitCode.connectionLost : CliExitCode.ok).code;
    } finally {
      discovery.dispose();
    }
  }

  DiscoverySettings _settings() {
    var results = argResults!;
    var filters = [
      for (var text in results['filter'] as List<String>) _filter(text, exclude: false),
      for (var text in results['exclude'] as List<String>) _filter(text, exclude: true),
    ];
    if (filters.every((filter) => filter.exclude)) {
      usageException('At least one --filter is required.');
    }
    var count = results['count'] as String?;
    if (count != null && (int.tryParse(count) ?? 0) < 1) {
      usageException('--count must be a number from 1.');
    }
    var duration = optionalDuration('duration');
    return DiscoverySettings(
      filters: filters,
      stop: count == null ? DiscoveryStop.duration : DiscoveryStop.messages,
      durationSeconds: duration?.inSeconds ?? DiscoverySettings.defaultDurationSeconds,
      maxMessages: count == null ? 100000 : int.parse(count),
      detectTemplates: !(results['no-templates'] as bool),
      inferSchemas: !(results['no-schemas'] as bool),
    );
  }

  RecorderFilter _filter(String text, {required bool exclude}) {
    if (RecorderRules.validateFilter(text) != null) {
      usageException('$text is no valid topic filter.');
    }
    return RecorderFilter(text, exclude: exclude, qos: MqttQos.exactlyOnce);
  }

  void _printResult(DiscoveryResult result) {
    for (var item in result.added) {
      out.event('new', {'path': item.path, 'template': item.isTemplate, 'messages': item.observed.messages},
          text: '  new      ${item.path}  (${CliFormat.count(item.observed.messages)} messages)',
          level: OutputLevel.detail);
    }
    for (var item in result.changed) {
      out.event('changed', {'path': item.node.path, 'differences': item.differences.length},
          text: '  changed  ${item.node.path}  (${item.differences.length} differences)', level: OutputLevel.detail);
    }
    for (var node in result.notSeen) {
      out.event('notSeen', {'path': node.path}, text: '  not seen ${node.path}', level: OutputLevel.detail);
    }
    out.event(
        'result',
        {
          'messages': result.messages,
          'topics': result.topicCount,
          'new': result.added.length,
          'templates': result.templates.length,
          'changed': result.changed.length,
          'notSeen': result.notSeen.length,
          'errors': result.errors,
        },
        text: '${CliFormat.count(result.messages)} messages on ${CliFormat.count(result.topicCount)} topics: '
            '${result.added.length} new (${result.templates.length} templates), ${result.changed.length} changed, '
            '${result.notSeen.length} documented but not seen.',
        level: OutputLevel.result);
  }
}

class DocCheckCommand extends CliCommand with BrokerOptions, _ProjectOption {
  @override
  final String name = 'check';
  @override
  final String description = 'Check the messages on the broker against the documentation.';

  DocCheckCommand(CliContext context) : super(context) {
    addProjectOption();
    argParser
      ..addOption('duration', help: 'Check this long. Without it the check runs until Ctrl+C.')
      ..addOption('fail-on',
          allowed: ['error', 'warning', 'never'],
          defaultsTo: 'error',
          help: 'Exit with 8 when a finding of this severity or worse occurs.')
      ..addMultiOption('filter',
          abbr: 't',
          help: 'Topic filter to check, by default the filters of the last discovery or the documented topics.')
      ..addFlag('reconnect', negatable: false, help: 'Reconnect after a lost connection instead of stopping.');
    addBrokerOptions();
  }

  @override
  Future<int> run() async {
    var results = argResults!;
    var duration = optionalDuration('duration');
    checkBrokerOptions();
    var project = await loadProject();
    var broker = connectionSettings(project.mqttSettings);
    var filters = results['filter'] as List<String>;
    var check = CheckService(
        connectionFactory: context.createAdapter, withProjects: false, reconnect: results['reconnect'] as bool);
    try {
      var done = Completer<void>();
      check.finishedEvent.subscribe((_) => done.isCompleted ? null : done.complete());
      check.errorEvent.subscribe((args) => out.error(args.message));
      try {
        await check.start(
            documentation: project.documentation,
            settings: broker,
            filters: filters.isEmpty ? null : filters,
            duration: duration);
      } on ArgumentError catch (exc) {
        throw CliException(CliExitCode.invalid, '${exc.message}');
      } catch (exc) {
        throw CliException(CliExitCode.connectFailed, 'Cannot connect to MQTT broker: $exc');
      }
      out.event(
          'plan', {'project': project.name, 'broker': '${broker.hostname}:${broker.port}', 'filters': check.filters},
          text: [
            'MQTT Studio ${context.version} · doc check',
            'Project   ${project.name}',
            'Broker    ${CliFormat.broker(broker)}',
            'Topics    ${check.filters.join(', ')}',
            duration == null ? 'Checking. Press Ctrl+C to stop.' : 'Checking for ${DurationParser.format(duration)}.',
          ].join('\n'));
      check.stateChangedEvent.subscribe((_) {
        if (check.state == CheckState.reconnecting) {
          out.event('reconnecting', {'attempt': check.reconnectAttempt}, text: 'Connection lost, reconnecting.');
        }
      });
      await _untilDone(context, done.future, check.stop);
      return _report(check);
    } finally {
      check.dispose();
    }
  }

  int _report(CheckService check) {
    var checker = check.checker!;
    for (var finding in checker.findings) {
      out.event('finding', finding.toJson(),
          text: '${finding.severity == FindingSeverity.error ? 'ERROR  ' : 'WARNING'} ${finding.topic}  '
              '${finding.rule.name}  ×${finding.count}  ${finding.detail}',
          level: OutputLevel.result);
    }
    var errors = checker.countOf(FindingSeverity.error);
    var warnings = checker.countOf(FindingSeverity.warning);
    var failOn = argResults!['fail-on'] as String;
    var failed = switch (failOn) {
      'error' => errors > 0,
      'warning' => errors + warnings > 0,
      _ => false,
    };
    var exitCode = check.lostConnection ? CliExitCode.connectionLost : (failed ? CliExitCode.mismatch : CliExitCode.ok);
    out.event(
        'summary', {'messages': checker.messages, 'errors': errors, 'warnings': warnings, 'exitCode': exitCode.code},
        text: '${CliFormat.count(checker.messages)} messages checked: $errors errors, $warnings warnings.'
            '${check.lostConnection ? ' The connection was lost.' : ''}',
        level: OutputLevel.result);
    return exitCode.code;
  }
}

class DocExportCommand extends CliCommand with _ProjectOption {
  static const Map<String, DocExportFormat> formats = {
    'md': DocExportFormat.markdown,
    'html': DocExportFormat.html,
    'asyncapi-yaml': DocExportFormat.asyncapiYaml,
    'asyncapi-json': DocExportFormat.asyncapiJson,
    'jsonschema': DocExportFormat.jsonSchema,
    'csv': DocExportFormat.csv,
  };

  @override
  final String name = 'export';
  @override
  final String description = 'Export the documentation as Markdown, HTML, AsyncAPI, JSON Schema or CSV.';

  DocExportCommand(CliContext context) : super(context) {
    addProjectOption();
    argParser
      ..addOption('format', allowed: formats.keys, help: 'Export format. Required.')
      ..addOption('out', help: 'Write to this file instead of stdout.')
      ..addOption('scope', help: 'Only this namespace or topic and everything below it.')
      ..addFlag('observed', negatable: false, help: 'Include what discovery observed.')
      ..addFlag('broker', negatable: false, help: 'Include host, port and protocol of the broker, never credentials.')
      ..addFlag('no-examples', negatable: false, help: 'Leave out the example payloads.');
  }

  @override
  Future<int> run() async {
    var results = argResults!;
    var format = formats[results['format'] as String?];
    if (format == null) {
      usageException('--format is required.');
    }
    var project = await loadProject();
    var scope = results['scope'] as String?;
    if (scope != null && project.documentation.nodeAt(scope) == null) {
      throw CliException(CliExitCode.notFound, '"$scope" is not documented in ${project.name}.');
    }
    var options = DocExportOptions(format,
        scope: scope,
        includeExamples: !(results['no-examples'] as bool),
        includeObserved: results['observed'] as bool,
        includeBroker: results['broker'] as bool);
    var text = DocExport.run(project.documentation, options, broker: project.mqttSettings, exportedAt: clock.now());
    var outPath = results['out'] as String?;
    if (outPath == null) {
      context.stdout.write(text);
      return CliExitCode.ok.code;
    }
    var file = File(outPath).absolute;
    try {
      await file.writeAsString(text);
    } on FileSystemException catch (exc) {
      throw CliException(CliExitCode.failure, 'Cannot write ${file.path}: ${exc.osError?.message ?? exc.message}');
    }
    out.event('written', {'file': file.path}, text: 'Exported to ${file.path}', level: OutputLevel.result);
    return CliExitCode.ok.code;
  }
}

class DocImportCommand extends CliCommand with _ProjectOption {
  @override
  final String name = 'import';
  @override
  final String description = 'Compare an AsyncAPI file with the documentation and write the merged result.';

  @override
  String get invocation => 'mqttstudio doc import -p <project> <file> [--out <file>] [--replace]';

  DocImportCommand(CliContext context) : super(context) {
    addProjectOption();
    argParser
      ..addOption('out', help: 'Write the merged documentation to this AsyncAPI file (.yaml or .json).')
      ..addFlag('replace', negatable: false, help: 'Replace the documentation instead of merging.');
  }

  @override
  Future<int> run() async {
    var path = singleArgument('AsyncAPI file');
    var project = await loadProject();
    String text;
    try {
      text = await File(path).readAsString();
    } on FileSystemException catch (exc) {
      throw CliException(CliExitCode.notFound, 'Cannot read $path: ${exc.osError?.message ?? exc.message}');
    }
    ImportedDocumentation imported;
    try {
      imported = AsyncApiImporter.read(text);
    } on FormatException catch (exc) {
      throw CliException(CliExitCode.invalid, '$path: ${exc.message}');
    }
    for (var warning in imported.warnings) {
      out.event('warning', {'message': warning}, text: 'Warning: $warning');
    }
    var current = TopicDocumentation.fromJson(project.documentation.toJson());
    var plan = ImportPlan.of(current, imported.documentation);
    for (var item in plan.items.where((item) => item.state != ImportState.same)) {
      out.event('item', {'path': item.imported.path, 'state': item.state.name, 'existing': item.existing?.path},
          text: '  ${item.state.name.padRight(8)} ${item.imported.path}'
              '${item.state == ImportState.conflict ? '  (covered by ${item.existing!.path})' : ''}',
          level: OutputLevel.detail);
    }
    out.event(
        'plan',
        {
          'version': imported.version,
          for (var state in ImportState.values) state.name: plan.countOf(state),
        },
        text: 'AsyncAPI ${imported.version}: ${plan.countOf(ImportState.added)} new, '
            '${plan.countOf(ImportState.changed)} changed, ${plan.countOf(ImportState.same)} unchanged, '
            '${plan.countOf(ImportState.conflict)} conflicts.',
        level: OutputLevel.result);
    var outPath = argResults!['out'] as String?;
    if (outPath != null) {
      plan.applyTo(current, replaceAll: argResults!['replace'] as bool);
      var file = await writeDocumentation(current, outPath, project);
      out.event('written', {'file': file}, text: 'Documentation written to $file', level: OutputLevel.result);
    }
    return CliExitCode.ok.code;
  }
}
