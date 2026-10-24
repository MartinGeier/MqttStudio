// Exit codes shared by every command of the CLI (doc/cli-design.md §4.1)
enum CliExitCode {
  ok(0),
  failure(1),
  usage(2),
  notFound(3),
  invalid(4),
  connectFailed(5),
  connectionLost(6),
  rateLimit(7),
  interrupted(130);

  final int code;
  const CliExitCode(this.code);
}

// Thrown by a command to end with an exit code and a message
class CliException implements Exception {
  final CliExitCode exitCode;
  final String message;

  CliException(this.exitCode, this.message);

  @override
  String toString() => message;
}
