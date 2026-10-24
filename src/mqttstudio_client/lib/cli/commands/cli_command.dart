import 'package:args/command_runner.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/cli/cli_context.dart';
import 'package:mqttstudio/cli/exit_codes.dart';
import 'package:mqttstudio/cli/output.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';

// A command of the CLI. run() returns the exit code, failures throw a CliException.
abstract class CliCommand extends Command<int> {
  final CliContext context;

  CliCommand(this.context);

  Output get out => context.out;

  @override
  void printUsage() => context.stdout.writeln(usage);

  // matched by name, exactly and then ignoring case. Projects are stored by name, so names are unique.
  Future<Project> findProject(String name) async {
    var projects = await context.projects.projects();
    for (var project in projects) {
      if (project.name == name) {
        return project;
      }
    }
    for (var project in projects) {
      if (project.name.toLowerCase() == name.toLowerCase()) {
        return project;
      }
    }
    var names = projects.map((p) => p.name).join(', ');
    throw CliException(
        CliExitCode.notFound, 'Project "$name" not found.${names.isEmpty ? ' There are no saved projects.' : ' Saved projects: $names'}');
  }

  // the one rest argument a command expects, e.g. the project of "projects show"
  String singleArgument(String name) {
    var rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Expected one $name.');
    }
    return rest.single;
  }
}

// English texts of the CLI
class CliFormat {
  static String broker(MqttSettings settings) {
    var scheme = settings.useWebSockets ? (settings.useSsl ? 'wss://' : 'ws://') : (settings.useSsl ? 'tls://' : '');
    var certificate = settings.useSsl && !settings.useWebSockets && (settings.clientCertificatePath ?? '').isNotEmpty
        ? ', client certificate'
        : '';
    return '$scheme${settings.hostname}:${settings.port} (${settings.protocolVersion.displayName}$certificate)';
  }

  static String generator(GeneratorType type) {
    switch (type) {
      case GeneratorType.randomString:
        return 'Random string';
      case GeneratorType.randomNumber:
        return 'Random number';
      case GeneratorType.counter:
        return 'Counter';
      case GeneratorType.boolean:
        return 'Boolean';
      case GeneratorType.valueList:
        return 'Value list';
      case GeneratorType.randomWalk:
        return 'Random walk';
      case GeneratorType.wave:
        return 'Wave';
      case GeneratorType.timestamp:
        return 'Timestamp';
      case GeneratorType.gpsTrack:
        return 'GPS track';
      case GeneratorType.randomImage:
        return 'Random image';
      case GeneratorType.template:
        return 'Template';
    }
  }

  static String instances(SimulatedDevice device) => device.instanceCount == 1
      ? '1 instance'
      : '${device.instanceCount} instances ({n} = ${device.firstInstance}–${device.lastInstance})';

  static String interval(PublishInterval interval) {
    String ms(int value) => value < 1000 ? '$value ms' : '${_trim(value / 1000)} s';
    return interval.isRandom ? '${ms(interval.minMs)} – ${ms(interval.maxMs)}' : ms(interval.minMs);
  }

  static String qos(SimulatedTopic topic) {
    var level = topic.qos == MqttQos.exactlyOnce ? 2 : (topic.qos == MqttQos.atLeastOnce ? 1 : 0);
    return topic.retain ? 'QoS $level, retained' : 'QoS $level';
  }

  static String rate(double rate) => '${rate < 10 && rate > 0 ? rate.toStringAsFixed(1) : rate.round()} msg/s';

  static String count(int value) {
    var digits = value.toString();
    var buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static String _trim(double value) => value == value.roundToDouble() ? '${value.round()}' : '$value';
}
