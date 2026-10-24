import 'dart:io';
import 'package:mqttstudio/cli/commands/cli_command.dart';
import 'package:mqttstudio/cli/exit_codes.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/storage/recording_storage.dart';

// A <recording> argument (doc/cli-design.md §7.1): a .mqttrec file, or a name or id in the recordings library
mixin RecordingArguments on CliCommand {
  // the library the recording is in: its folder for a file path
  Future<(RecordingLibrary, RecordingInfo)> findRecording(String text) async {
    var file = File(text);
    if (text.toLowerCase().endsWith(RecordingNames.extension) && await file.exists()) {
      var library = RecordingLibrary(FolderRecordingStore(file.absolute.parent));
      var fileName = file.uri.pathSegments.last;
      var info = (await library.list()).where((info) => info.fileName == fileName).firstOrNull;
      if (info == null) {
        throw CliException(CliExitCode.notFound, '$text is not a readable MQTT Studio recording.');
      }
      return (library, info);
    }
    var library = await context.recordings();
    return (library, await findInLibrary(library, text));
  }

  // by id, then by name exactly, then ignoring case; an ambiguous name lists the ids
  Future<RecordingInfo> findInLibrary(RecordingLibrary library, String text) async {
    var all = await library.list();
    var byId = all.where((info) => info.id == text).toList();
    if (byId.isNotEmpty) {
      return byId.first;
    }
    var matches = all.where((info) => info.name == text).toList();
    if (matches.isEmpty) {
      matches = all.where((info) => info.name.toLowerCase() == text.toLowerCase()).toList();
    }
    if (matches.length == 1) {
      return matches.single;
    }
    if (matches.length > 1) {
      throw CliException(CliExitCode.notFound,
          'The recording name "$text" is used more than once, use one of the ids: ${matches.map((info) => info.id).join(', ')}');
    }
    throw CliException(CliExitCode.notFound,
        'Recording "$text" not found in ${library.location ?? 'the recordings library'}. List them with "recordings list".');
  }

  // 1GB, 500MB, 64KB or bytes
  int parseSize(String text, String option) {
    var match = RegExp(r'^(\d+(?:\.\d+)?)\s*(b|kb|mb|gb)?$', caseSensitive: false).firstMatch(text.trim());
    if (match == null) {
      usageException('--$option: use e.g. 500MB, 1GB or 64KB.');
    }
    var value = double.parse(match.group(1)!);
    var unit = (match.group(2) ?? 'b').toLowerCase();
    var factor = switch (unit) { 'kb' => 1024, 'mb' => 1024 * 1024, 'gb' => 1024 * 1024 * 1024, _ => 1 };
    return (value * factor).round();
  }
}
