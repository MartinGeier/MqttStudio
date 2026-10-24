import 'package:mqttstudio/cli/cli_context.dart';
import 'package:mqttstudio/cli/commands/cli_command.dart';
import 'package:mqttstudio/cli/exit_codes.dart';
import 'package:mqttstudio/cli/output.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';

class ProjectsCommand extends CliCommand {
  @override
  final String name = 'projects';
  @override
  final String description = 'List and inspect saved projects.';

  ProjectsCommand(CliContext context) : super(context) {
    addSubcommand(ProjectsListCommand(context));
    addSubcommand(ProjectsShowCommand(context));
  }
}

class ProjectsListCommand extends CliCommand {
  @override
  final String name = 'list';
  @override
  final String description = 'List the saved projects with their broker and simulation.';

  ProjectsListCommand(CliContext context) : super(context);

  @override
  Future<int> run() async {
    var projects = (await context.projects.projects())..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (projects.isEmpty) {
      out.event('done', {'exitCode': 0}, text: 'There are no saved projects.', level: OutputLevel.result);
      return CliExitCode.ok.code;
    }
    var nameWidth = projects.map((p) => p.name.length).reduce((a, b) => a > b ? a : b);
    for (var project in projects) {
      var simulation = project.simulation;
      var devices = simulation.devices.length;
      var topics = simulation.allTopics.length;
      out.event(
        'project',
        {
          'name': project.name,
          'broker': '${project.mqttSettings.hostname}:${project.mqttSettings.port}',
          'protocol': project.mqttSettings.protocolVersion.name,
          'devices': devices,
          'topics': topics,
        },
        text: '${project.name.padRight(nameWidth)}  ${CliFormat.broker(project.mqttSettings)}  '
            '$devices ${devices == 1 ? 'device' : 'devices'}, $topics ${topics == 1 ? 'topic' : 'topics'}',
        level: OutputLevel.result,
      );
    }
    out.event('done', {'exitCode': 0});
    return CliExitCode.ok.code;
  }
}

class ProjectsShowCommand extends CliCommand {
  @override
  final String name = 'show';
  @override
  final String description = 'Show the broker settings and the simulation of a project.';
  @override
  final String invocation = 'mqttstudio projects show <project>';

  ProjectsShowCommand(CliContext context) : super(context);

  @override
  Future<int> run() async {
    var project = await findProject(singleArgument('project'));
    var settings = project.mqttSettings;
    var lines = <String>[
      'Project   ${project.name}',
      'Broker    ${CliFormat.broker(settings)} as ${settings.clientId}',
      if (project.lastUsed != null) 'Last used ${project.lastUsed!.toLocal()}',
    ];
    var devices = <Map<String, Object?>>[];
    for (var device in project.simulation.devices) {
      lines.add('');
      lines.add('${device.name}: ${CliFormat.instances(device)}  [id ${device.id}]');
      var topics = <Map<String, Object?>>[];
      for (var topic in device.topics) {
        var resolved = SimulationRules.resolvedTopics(device, topic);
        var range = resolved.length == 1 ? resolved.first : '${resolved.first} … ${resolved.last}';
        lines.add('  ${topic.topic}  ${CliFormat.generator(topic.generator.type)}, ${CliFormat.interval(topic.interval)}, '
            '${CliFormat.qos(topic)}  → $range');
        topics.add({
          'id': topic.id,
          'topic': topic.topic,
          'generator': topic.generator.type.key,
          'intervalMs': topic.interval.minMs,
          'maxIntervalMs': topic.interval.maxMs,
          'qos': topic.qos.index,
          'retain': topic.retain,
        });
      }
      if (device.topics.isEmpty) {
        lines.add('  no topics');
      }
      var rate = SimulationRules.estimateRate(device.topics.map((topic) => (device, topic)));
      lines.add('  ≈ ${CliFormat.rate(rate)}');
      devices.add({
        'id': device.id,
        'name': device.name,
        'instances': device.instanceCount,
        'firstInstance': device.firstInstance,
        'estimatedRate': rate,
        'topics': topics,
      });
    }

    out.event(
      'project',
      {
        'name': project.name,
        'broker': '${settings.hostname}:${settings.port}',
        'protocol': settings.protocolVersion.name,
        'clientId': settings.clientId,
        'devices': devices,
      },
      text: lines.join('\n'),
      level: OutputLevel.result,
    );
    out.event('done', {'exitCode': 0});
    return CliExitCode.ok.code;
  }
}
