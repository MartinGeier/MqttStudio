import 'dart:convert';
import 'package:clock/clock.dart';

enum OutputLevel {
  // only with --verbose
  detail,
  // not with --quiet
  info,
  // always, e.g. the final summary
  result,
}

// What a command reports. In text mode the text of an event is printed, in JSON mode the event itself as one line.
abstract class Output {
  void event(String name, Map<String, Object?> data, {String? text, OutputLevel level = OutputLevel.info});

  // errors go to stderr in both modes
  void error(String message, {Map<String, Object?> data = const {}});
}

class TextOutput implements Output {
  final StringSink out;
  final StringSink err;
  final bool quiet;
  final bool verbose;

  TextOutput(this.out, this.err, {this.quiet = false, this.verbose = false});

  @override
  void event(String name, Map<String, Object?> data, {String? text, OutputLevel level = OutputLevel.info}) {
    if (text == null) {
      return;
    }
    if (level == OutputLevel.detail && !verbose) {
      return;
    }
    if (level == OutputLevel.info && quiet) {
      return;
    }
    out.writeln(text);
  }

  @override
  void error(String message, {Map<String, Object?> data = const {}}) => err.writeln(message);
}

class JsonLinesOutput implements Output {
  final StringSink out;
  final StringSink err;
  final bool verbose;

  JsonLinesOutput(this.out, this.err, {this.verbose = false});

  @override
  void event(String name, Map<String, Object?> data, {String? text, OutputLevel level = OutputLevel.info}) {
    if (level == OutputLevel.detail && !verbose) {
      return;
    }
    out.writeln(_encode(name, data));
  }

  @override
  void error(String message, {Map<String, Object?> data = const {}}) =>
      err.writeln(_encode('error', {'message': message, ...data}));

  static String _encode(String name, Map<String, Object?> data) =>
      jsonEncode({'event': name, 'time': clock.now().toUtc().toIso8601String(), ...data});
}
