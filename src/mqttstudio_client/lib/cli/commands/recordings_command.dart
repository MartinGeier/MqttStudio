import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:mqttstudio/cli/cli_context.dart';
import 'package:mqttstudio/cli/commands/cli_command.dart';
import 'package:mqttstudio/cli/commands/recording_arguments.dart';
import 'package:mqttstudio/cli/duration_parser.dart';
import 'package:mqttstudio/cli/exit_codes.dart';
import 'package:mqttstudio/cli/output.dart';
import 'package:mqttstudio/common/utils/json_path.dart';
import 'package:mqttstudio/recorder/analysis/recording_analysis.dart';
import 'package:mqttstudio/recorder/model/anonymize_rule.dart';
import 'package:mqttstudio/recorder/model/compare_options.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/tools/recording_comparer.dart';
import 'package:mqttstudio/recorder/tools/recording_editor.dart';
import 'package:mqttstudio/recorder/tools/recording_export.dart';
import 'package:mqttstudio/recorder/tools/recording_import.dart';

// mqttstudio recordings …: the recordings library from the command line (doc/cli-design.md §7.1)
class RecordingsCommand extends CliCommand {
  @override
  final String name = 'recordings';
  @override
  final String description = 'List, inspect, export, import, edit and compare recordings.';

  RecordingsCommand(CliContext context) : super(context) {
    addSubcommand(RecordingsListCommand(context));
    addSubcommand(RecordingsShowCommand(context));
    addSubcommand(RecordingsExportCommand(context));
    addSubcommand(RecordingsImportCommand(context));
    addSubcommand(RecordingsEditCommand(context));
    addSubcommand(RecordingsCompareCommand(context));
  }
}

String _date(DateTime time) => DateFormat('yyyy-MM-dd HH:mm').format(time.toLocal());

String _bytes(int bytes) => bytes < 1024 * 1024 ? '${(bytes / 1024).toStringAsFixed(1)} KB' : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

String _pathOf(RecordingLibrary library, RecordingInfo info) =>
    library.location == null ? info.fileName : '${library.location}${Platform.pathSeparator}${info.fileName}';

Map<String, Object?> _infoJson(RecordingLibrary library, RecordingInfo info) => {
      'id': info.id,
      'name': info.name,
      'startedAt': info.header.startedAt.toIso8601String(),
      'durationMicros': info.footer.durationMicros,
      'messages': info.footer.summary.messages,
      'size': info.size,
      'origin': info.header.origin.name,
      'project': info.projectName,
      'filters': [for (var filter in info.header.filters) '${filter.exclude ? '-' : ''}${filter.filter}'],
      'file': _pathOf(library, info),
    };

class RecordingsListCommand extends CliCommand {
  @override
  final String name = 'list';
  @override
  final String description = 'List the recordings of the library.';

  RecordingsListCommand(CliContext context) : super(context) {
    argParser.addOption('project', abbr: 'p', help: 'Only the recordings of this project.');
  }

  @override
  Future<int> run() async {
    var library = await context.recordings();
    var project = argResults!['project'] as String?;
    var recordings = [
      for (var info in await library.list())
        if (project == null || info.belongsTo(project)) info
    ];
    if (recordings.isEmpty) {
      out.event('done', {'exitCode': 0},
          text: project == null
              ? 'There are no recordings in ${library.location ?? 'the library'}.'
              : 'There are no recordings of project "$project".',
          level: OutputLevel.result);
      return CliExitCode.ok.code;
    }
    var nameWidth = recordings.map((info) => info.name.length).reduce((a, b) => a > b ? a : b);
    for (var info in recordings) {
      out.event('recording', _infoJson(library, info),
          text: '${info.name.padRight(nameWidth)}  ${_date(info.header.startedAt)}  '
              '${DurationParser.format(info.footer.duration).padLeft(10)}  '
              '${CliFormat.count(info.footer.summary.messages).padLeft(10)} msgs  ${_bytes(info.size).padLeft(9)}  ${info.id}',
          level: OutputLevel.result);
    }
    out.event('done', {'exitCode': 0});
    return CliExitCode.ok.code;
  }
}

class RecordingsShowCommand extends CliCommand with RecordingArguments {
  @override
  final String name = 'show';
  @override
  final String description = 'Show a recording with its per-topic summary.';

  @override
  String get invocation => 'mqttstudio recordings show <recording> [--gaps] [--duplicates]';

  RecordingsShowCommand(CliContext context) : super(context) {
    argParser
      ..addFlag('gaps', negatable: false, help: 'List the gaps of each topic.')
      ..addFlag('duplicates', negatable: false, help: 'List repeated payloads per topic.');
  }

  @override
  Future<int> run() async {
    var (library, info) = await findRecording(singleArgument('recording'));
    var footer = info.footer;
    var header = info.header;
    out.event('recording', {..._infoJson(library, info), 'broker': header.broker, 'notes': footer.notes},
        text: [
          '${info.name}  (${info.id})',
          'Started   ${_date(header.startedAt)}, ${DurationParser.format(footer.duration)}, '
              '${CliFormat.count(footer.summary.messages)} messages, ${_bytes(info.size)}',
          'Broker    ${header.broker} as ${header.clientId}',
          'Project   ${info.projectName ?? '–'}',
          'Filters   ${header.filters.map((f) => '${f.exclude ? 'not ' : ''}${f.filter}').join(', ')}',
          if (footer.notes.isNotEmpty) 'Notes     ${footer.notes}',
          if (footer.bookmarks.isNotEmpty)
            'Bookmarks ${footer.bookmarks.map((b) => '${b.label} at ${DurationParser.format(b.offset)}').join(', ')}',
          'File      ${_pathOf(library, info)}',
        ].join('\n'),
        level: OutputLevel.result);
    var seconds = footer.durationMicros / Duration.microsecondsPerSecond;
    for (var topic in List.of(footer.topics)..sort()) {
      var stats = footer.summary.perTopic[topic];
      if (stats == null) {
        continue;
      }
      var median = stats.medianInterval;
      out.event(
          'topic',
          {
            'topic': topic,
            'messages': stats.count,
            'rate': seconds <= 0 ? 0 : stats.count / seconds,
            'medianIntervalMicros': median?.inMicroseconds,
            'averagePayload': stats.averagePayload.round(),
            'payload': stats.mainKind,
            'duplicates': stats.consecutiveDuplicates,
            'retained': stats.retainedCount,
          },
          text: '  ${topic.padRight(40)} ${CliFormat.count(stats.count).padLeft(9)} msgs  '
              '${median == null ? '–' : DurationParser.format(median)} interval  ${stats.mainKind ?? ''}',
          level: OutputLevel.result);
    }
    var gaps = argResults!['gaps'] as bool;
    var duplicates = argResults!['duplicates'] as bool;
    if (gaps || duplicates) {
      var reader = await library.open(info);
      RecordingAnalysis? analysis;
      try {
        analysis = await RecordingAnalyzer.analyze(reader);
      } finally {
        await reader.close();
      }
      if (gaps) {
        _printGaps(info, analysis!);
      }
      if (duplicates) {
        _printDuplicates(info, analysis!);
      }
    }
    out.event('done', {'exitCode': 0});
    return CliExitCode.ok.code;
  }

  void _printGaps(RecordingInfo info, RecordingAnalysis analysis) {
    for (var topic in List.of(info.footer.topics)..sort()) {
      var threshold = RecordingAnalysis.defaultGapThreshold(info.footer.summary.perTopic[topic]);
      for (var gap in analysis.gapsOf(topic, threshold)) {
        out.event(
            'gap',
            {'topic': topic, 'startMicros': gap.startMicros, 'lengthMicros': gap.lengthMicros, 'connectionLost': gap.connectionLost},
            text: '  gap  $topic at ${DurationParser.format(Duration(microseconds: gap.startMicros))} for '
                '${DurationParser.format(Duration(microseconds: gap.lengthMicros))}${gap.connectionLost ? ' (connection lost)' : ''}',
            level: OutputLevel.result);
      }
    }
  }

  void _printDuplicates(RecordingInfo info, RecordingAnalysis analysis) {
    for (var topic in List.of(info.footer.topics)..sort()) {
      var consecutive = info.footer.summary.perTopic[topic]?.consecutiveDuplicates ?? 0;
      var quick = analysis.topics[topic]?.quickRepeats ?? 0;
      if (consecutive > 0 || quick > 0) {
        out.event('duplicates', {'topic': topic, 'consecutive': consecutive, 'within100ms': quick},
            text: '  duplicates  $topic: $consecutive same as before, $quick again within 100 ms', level: OutputLevel.result);
      }
    }
  }
}

class RecordingsExportCommand extends CliCommand with RecordingArguments {
  @override
  final String name = 'export';
  @override
  final String description = 'Export a recording as JSON lines, CSV or a copy of the file.';

  @override
  String get invocation => 'mqttstudio recordings export <recording> --format <jsonl|csv|mqttrec> [options]';

  RecordingsExportCommand(CliContext context) : super(context) {
    argParser
      ..addOption('format', allowed: ['jsonl', 'csv', 'mqttrec'], defaultsTo: 'jsonl')
      ..addOption('out', help: 'File to write, by default the recording name with the extension of the format.')
      ..addMultiOption('topic', abbr: 't', help: 'Topic to export. Repeatable, all by default.')
      ..addOption('from', help: 'Start of the range as an offset.')
      ..addOption('to', help: 'End of the range as an offset.')
      ..addMultiOption('column', help: 'CSV: an extra column with the value at this JSON path. Repeatable.');
  }

  @override
  Future<int> run() async {
    var results = argResults!;
    var (library, info) = await findRecording(singleArgument('recording'));
    var format = switch (results['format']) {
      'csv' => ExportFormat.csv,
      'mqttrec' => ExportFormat.mqttrec,
      _ => ExportFormat.jsonLines,
    };
    var path = (results['out'] as String?) ?? '${info.name}.${RecordingExport.extensionOf(format)}';
    var topics = results['topic'] as List<String>;
    var columns = <JsonPath>[];
    for (var column in results['column'] as List<String>) {
      var parsed = JsonPath.tryParse(column);
      if (parsed == null) {
        usageException('--column $column is no JSON path like \$.a.b[0].');
      }
      columns.add(parsed);
    }
    int? count;
    if (format == ExportFormat.mqttrec) {
      var file = await library.store.open(info.fileName);
      try {
        await File(path).writeAsBytes(await file.read(0, await file.length()));
      } finally {
        await file.close();
      }
      count = info.footer.summary.messages;
    } else {
      var reader = await library.open(info);
      var sink = File(path).openWrite();
      try {
        count = await RecordingExport.writeText(reader, sink,
            format: format,
            topics: topics.isEmpty ? null : topics.toSet(),
            fromMicros: _offset('from'),
            toMicros: _offset('to'),
            columns: columns);
      } finally {
        await sink.close();
        await reader.close();
      }
    }
    out.event('exported', {'file': path, 'messages': count, 'exitCode': 0},
        text: 'Exported ${CliFormat.count(count ?? 0)} messages to $path', level: OutputLevel.result);
    return CliExitCode.ok.code;
  }

  int? _offset(String option) {
    var text = argResults![option] as String?;
    if (text == null) {
      return null;
    }
    try {
      return DurationParser.parse(text).inMicroseconds;
    } on FormatException catch (exc) {
      usageException('--$option: ${exc.message}');
    }
  }
}

class RecordingsImportCommand extends CliCommand with RecordingArguments {
  @override
  final String name = 'import';
  @override
  final String description = 'Import a .mqttrec file, JSON lines, CSV or mosquitto_sub output into the library.';

  @override
  String get invocation => 'mqttstudio recordings import <file> [--format <mqttrec|jsonl|csv|mosquitto>] [options]';

  RecordingsImportCommand(CliContext context) : super(context) {
    argParser
      ..addOption('format', allowed: ['mqttrec', 'jsonl', 'csv', 'mosquitto'], help: 'By default from the file.')
      ..addOption('interval', defaultsTo: '1s', help: 'mosquitto_sub -v output without times: the time between lines.')
      ..addOption('name', help: 'Name of the recording, by default the file name.');
  }

  @override
  Future<int> run() async {
    var results = argResults!;
    var path = singleArgument('file');
    var file = File(path);
    if (!await file.exists()) {
      throw CliException(CliExitCode.notFound, 'File $path not found.');
    }
    var fileName = file.uri.pathSegments.last;
    var library = await context.recordings();
    RecordingInfo info;
    var skipped = 0;
    try {
      var bytes = await file.readAsBytes();
      var text = results['format'] == 'mqttrec' ? '' : utf8.decode(bytes, allowMalformed: true);
      var format = switch (results['format']) {
            'mqttrec' => ImportFormat.mqttrec,
            'jsonl' => ImportFormat.jsonLines,
            'csv' => ImportFormat.csv,
            _ => null,
          } ??
          RecordingImport.formatOf(fileName, const LineSplitter().convert(text).firstOrNull ?? '') ??
          ImportFormat.mosquittoVerbose;
      // mosquitto output with times starts with a Unix time
      if (results['format'] == 'mosquitto') {
        format = RecordingImport.formatOf('.txt', const LineSplitter().convert(text).firstOrNull ?? '') ?? ImportFormat.mosquittoVerbose;
      }
      if (format == ImportFormat.mqttrec) {
        info = await library.importBytes(fileName, bytes);
      } else {
        var interval = DurationParser.parse(results['interval'] as String);
        var dot = fileName.lastIndexOf('.');
        var importer = RecordingImport(library);
        info = await importer.importText(text, format,
            name: (results['name'] as String?) ?? (dot > 0 ? fileName.substring(0, dot) : fileName), interval: interval);
        skipped = importer.skipped;
      }
    } on FormatException catch (exc) {
      throw CliException(CliExitCode.invalid, 'Cannot import $path: ${exc.message}');
    }
    out.event('imported', {..._infoJson(library, info), 'skipped': skipped, 'exitCode': 0},
        text: 'Imported ${CliFormat.count(info.footer.summary.messages)} messages as "${info.name}" (${info.id})'
            '${skipped > 0 ? ', $skipped lines skipped' : ''}',
        level: OutputLevel.result);
    return CliExitCode.ok.code;
  }
}

class RecordingsEditCommand extends CliCommand with RecordingArguments {
  @override
  final String name = 'edit';
  @override
  final String description = 'Write a new recording: trimmed, with fewer or renamed topics, or anonymized.';

  @override
  String get invocation => 'mqttstudio recordings edit <recording> [options]';

  RecordingsEditCommand(CliContext context) : super(context) {
    argParser
      ..addOption('from', help: 'Trim: start of the range as an offset.')
      ..addOption('to', help: 'Trim: end of the range as an offset.')
      ..addMultiOption('topic', abbr: 't', help: 'Keep only these topics. Repeatable.')
      ..addMultiOption('exclude-topic', help: 'Leave out these topics. Repeatable.')
      ..addMultiOption('rename', help: 'Rename topics by prefix <from>=<to>. Repeatable.')
      ..addOption('anonymize', help: 'JSON file with anonymize rules, as saved in the app.')
      ..addFlag('anonymize-properties', negatable: false, help: 'Apply the whole payload rules to user properties too.')
      ..addOption('name', help: 'Name of the new recording.');
  }

  @override
  Future<int> run() async {
    var results = argResults!;
    var (library, source) = await findRecording(singleArgument('recording'));
    var editor = RecordingEditor(library);
    var steps = <Future<RecordingInfo> Function(RecordingInfo)>[];
    var from = _offset('from');
    var to = _offset('to');
    if (from != null || to != null) {
      steps.add((info) => editor.trim(info, from ?? 0, to ?? info.footer.durationMicros));
    }
    var keep = (results['topic'] as List<String>).toSet();
    var drop = (results['exclude-topic'] as List<String>).toSet();
    if (keep.isNotEmpty || drop.isNotEmpty) {
      steps.add((info) => editor.keepTopics(
          info, info.footer.topics.where((t) => (keep.isEmpty || keep.contains(t)) && !drop.contains(t)).toSet()));
    }
    var renames = <TopicRemap>[];
    for (var text in results['rename'] as List<String>) {
      var equals = text.indexOf('=');
      if (equals <= 0) {
        usageException('--rename must look like <from>=<to>.');
      }
      renames.add(TopicRemap(text.substring(0, equals), text.substring(equals + 1)));
    }
    if (renames.isNotEmpty) {
      steps.add((info) => editor.renameTopics(info, renames));
    }
    var rulesFile = results['anonymize'] as String?;
    if (rulesFile != null) {
      List<AnonymizeRule> rules;
      try {
        rules = AnonymizeRule.decodeList(await File(rulesFile).readAsString());
      } on FileSystemException catch (exc) {
        throw CliException(CliExitCode.notFound, 'Cannot read $rulesFile: ${exc.message}');
      } on FormatException catch (exc) {
        throw CliException(CliExitCode.invalid, '$rulesFile: ${exc.message}');
      }
      var problem = rules.where((rule) => rule.problem != null).firstOrNull;
      if (problem != null) {
        throw CliException(CliExitCode.invalid, '$rulesFile: the rule for ${problem.topicFilter} has no valid ${problem.problem}.');
      }
      steps.add((info) => editor.anonymize(info, rules, properties: results['anonymize-properties'] as bool));
    }
    if (steps.isEmpty) {
      usageException('Nothing to do: give --from/--to, --topic, --exclude-topic, --rename or --anonymize.');
    }
    // each step writes a new recording; the intermediate ones are removed again
    var current = source;
    for (var i = 0; i < steps.length; i++) {
      var next = await steps[i](current);
      if (current != source) {
        await library.delete(current);
      }
      current = next;
    }
    var name = results['name'] as String?;
    if (name != null) {
      current = await library.updateMetadata(current, name: name);
    }
    out.event('edited', {..._infoJson(library, current), 'source': source.id, 'exitCode': 0},
        text: 'Wrote "${current.name}" (${current.id}), ${CliFormat.count(current.footer.summary.messages)} messages',
        level: OutputLevel.result);
    return CliExitCode.ok.code;
  }

  int? _offset(String option) {
    var text = argResults![option] as String?;
    if (text == null) {
      return null;
    }
    try {
      return DurationParser.parse(text).inMicroseconds;
    } on FormatException catch (exc) {
      usageException('--$option: ${exc.message}');
    }
  }
}

class RecordingsCompareCommand extends CliCommand with RecordingArguments {
  @override
  final String name = 'compare';
  @override
  final String description = 'Compare two recordings by topic. Exits with 8 when they differ.';

  @override
  String get invocation => 'mqttstudio recordings compare <a> <b> [options]';

  RecordingsCompareCommand(CliContext context) : super(context) {
    argParser
      ..addFlag('counts', negatable: false, help: 'Compare the message counts per topic.')
      ..addFlag('payloads', negatable: false, help: 'Compare the payloads per topic in order.')
      ..addFlag('timing', negatable: false, help: 'Compare the median interval per topic.')
      ..addMultiOption('ignore', help: 'JSON path left out of the payload comparison, e.g. \$.ts. Repeatable.')
      ..addOption('count-tolerance', defaultsTo: '0', help: 'Percent.')
      ..addOption('number-tolerance', defaultsTo: '0', help: 'Absolute, for numbers in payloads.')
      ..addOption('timing-tolerance', defaultsTo: '10', help: 'Percent.')
      ..addMultiOption('remap', help: 'Map topics of B onto A by prefix <from>=<to>. Repeatable.')
      ..addOption('report', help: 'Write the result as JSON to this file.');
  }

  @override
  Future<int> run() async {
    var results = argResults!;
    var rest = results.rest;
    if (rest.length != 2) {
      usageException('Expected two recordings.');
    }
    var (libraryA, a) = await findRecording(rest[0]);
    var (libraryB, b) = await findRecording(rest[1]);
    var all = !(results['counts'] as bool) && !(results['payloads'] as bool) && !(results['timing'] as bool);
    for (var path in results['ignore'] as List<String>) {
      if (JsonPath.tryParse(path) == null) {
        usageException('--ignore $path is no JSON path like \$.a.b[0].');
      }
    }
    var remaps = <TopicRemap>[];
    for (var text in results['remap'] as List<String>) {
      var equals = text.indexOf('=');
      if (equals <= 0) {
        usageException('--remap must look like <from>=<to>.');
      }
      remaps.add(TopicRemap(text.substring(0, equals), text.substring(equals + 1)));
    }
    var options = CompareOptions(
      remaps: remaps,
      counts: all || results['counts'] as bool,
      payloads: all || results['payloads'] as bool,
      timing: all || results['timing'] as bool,
      ignorePaths: results['ignore'] as List<String>,
      countTolerance: _number('count-tolerance'),
      numberTolerance: _number('number-tolerance'),
      timingTolerance: _number('timing-tolerance'),
    );
    // B may sit in another folder than A
    var comparer = RecordingComparer(libraryA);
    var result = libraryA == libraryB ? await comparer.compare(a, b, options) : await _compareAcross(libraryA, libraryB, a, b, options);
    for (var topic in result.topics.where((topic) => topic.status != TopicCompareStatus.equal)) {
      var difference = topic.firstDifference;
      out.event('difference', topic.toJson(),
          text: '  ${topic.status.name.padRight(10)} ${topic.topic}  messages ${topic.countA} / ${topic.countB}'
              '${difference == null ? '' : ', message ${difference.index + 1} differs${difference.path == null ? '' : ' at ${difference.path}'}'}',
          level: OutputLevel.result);
    }
    var report = results['report'] as String?;
    if (report != null) {
      await File(report).writeAsString(JsonEncoder.withIndent('  ').convert(result.toJson()));
    }
    var exitCode = result.isEqual ? CliExitCode.ok : CliExitCode.mismatch;
    out.event(
        'compared',
        {
          'equal': result.isEqual,
          'topics': result.topics.length,
          'different': result.countOf(TopicCompareStatus.different),
          'onlyInA': result.countOf(TopicCompareStatus.onlyInA),
          'onlyInB': result.countOf(TopicCompareStatus.onlyInB),
          'exitCode': exitCode.code,
        },
        text: result.isEqual
            ? '"${a.name}" and "${b.name}" are equal (${result.topics.length} topics).'
            : '"${a.name}" and "${b.name}" differ: ${result.countOf(TopicCompareStatus.different)} topics different, '
                '${result.countOf(TopicCompareStatus.onlyInA)} only in A, ${result.countOf(TopicCompareStatus.onlyInB)} only in B.',
        level: OutputLevel.result);
    return exitCode.code;
  }

  // the comparer reads both from one library, so B is copied into A's for the comparison
  Future<CompareResult> _compareAcross(
      RecordingLibrary libraryA, RecordingLibrary libraryB, RecordingInfo a, RecordingInfo b, CompareOptions options) async {
    var file = await libraryB.store.open(b.fileName);
    RecordingInfo copy;
    try {
      copy = await libraryA.importBytes('compare ${b.fileName}', await file.read(0, await file.length()));
    } finally {
      await file.close();
    }
    try {
      return await RecordingComparer(libraryA).compare(a, copy, options);
    } finally {
      await libraryA.delete(copy);
    }
  }

  double _number(String option) {
    var value = double.tryParse(argResults![option] as String);
    if (value == null || value < 0) {
      usageException('--$option must be a number from 0.');
    }
    return value;
  }
}
