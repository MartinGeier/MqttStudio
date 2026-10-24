import 'dart:math';
import 'package:mqttstudio/cli/commands/cli_command.dart';
import 'package:mqttstudio/cli/duration_parser.dart';
import 'package:mqttstudio/cli/exit_codes.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:srx_flutter/srx_flutter.dart';

// The broker overrides of simulate, record and replay (doc/cli-design.md §2.4) and the connection with them
mixin BrokerOptions on CliCommand {
  static const String passwordVariable = 'MQTTSTUDIO_PASSWORD';
  static const String keyPasswordVariable = 'MQTTSTUDIO_KEY_PASSWORD';
  static const List<Duration> reconnectDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  void addBrokerOptions() {
    argParser
      ..addOption('host', help: 'Broker hostname or ws:// / wss:// URL instead of the one of the project.')
      ..addOption('port', help: 'Broker port.')
      ..addOption('client-id', help: 'Client id, by default the one of the project with -cli-<random> appended.')
      ..addOption('username', help: 'User name. The password is read from $passwordVariable.')
      ..addFlag('tls', defaultsTo: null, help: 'Use TLS, or --no-tls to turn it off.')
      ..addOption('ca-cert', help: 'PEM file of a CA to trust in addition to the system ones.')
      ..addOption('cert', help: 'PEM file of the client certificate.')
      ..addOption('key',
          help: 'PEM file of the private key, by default read from the certificate file. '
              'The key password is read from $keyPasswordVariable.');
  }

  void checkBrokerOptions() {
    var port = argResults!['port'] as String?;
    if (port != null && int.tryParse(port) == null) {
      usageException('--port must be a number.');
    }
  }

  Duration parseDuration(String text, String option) {
    try {
      return DurationParser.parse(text);
    } on FormatException catch (exc) {
      usageException('--$option: ${exc.message}');
    }
  }

  Duration? optionalDuration(String option) {
    var text = argResults![option] as String?;
    return text == null ? null : parseDuration(text, option);
  }

  // the project's settings with the overrides; without a project only --host and the defaults
  MqttSettings connectionSettings(MqttSettings? projectSettings) {
    var results = argResults!;
    var settings = projectSettings == null ? MqttSettings('', 'mqttstudio', 1883) : MqttSettings.fromJson(projectSettings.toJson());
    var host = results['host'] as String?;
    if (host != null) {
      var lower = host.toLowerCase();
      if (lower.startsWith('ws://') || lower.startsWith('wss://')) {
        settings.useWebSockets = true;
        settings.useSsl = lower.startsWith('wss://');
        host = host.substring(lower.startsWith('ws://') ? 5 : 6);
      }
      settings.hostname = host;
    }
    if (results['port'] != null) {
      settings.port = int.parse(results['port'] as String);
    }
    if (results['tls'] != null) {
      settings.useSsl = results['tls'] as bool;
    }
    if (results['username'] != null) {
      settings.username = results['username'] as String;
    }
    var password = context.environment[passwordVariable];
    if (password != null) {
      settings.password = password;
    }
    _applyCertificates(settings);
    // its own client id, so the broker does not disconnect an app window that uses the project
    settings.clientId = (results['client-id'] as String?) ??
        '${settings.clientId}-cli-${Random().nextInt(0x10000).toRadixString(16).padLeft(4, '0')}';
    return settings;
  }

  void _applyCertificates(MqttSettings settings) {
    var results = argResults!;
    if (results['ca-cert'] != null) {
      settings.caCertificatePath = results['ca-cert'] as String;
    }
    if (results['cert'] != null) {
      settings.clientCertificatePath = results['cert'] as String;
      // the key of the project belongs to the certificate of the project
      settings.clientKeyPath = null;
    }
    if (results['key'] != null) {
      if (settings.clientCertificatePath == null || settings.clientCertificatePath!.isEmpty) {
        usageException('--key needs a client certificate, from --cert or the project.');
      }
      settings.clientKeyPath = results['key'] as String;
    }
    var keyPassword = context.environment[keyPasswordVariable];
    if (keyPassword != null) {
      settings.clientKeyPassword = keyPassword;
    }
  }

  Future<void> connect(MqttAdapter adapter, MqttSettings settings) async {
    try {
      await adapter.connect(settings);
    } on SrxServiceException catch (exc) {
      throw CliException(CliExitCode.connectFailed, 'Cannot connect to MQTT broker: ${exc.errorMessage}');
    } catch (exc) {
      throw CliException(CliExitCode.connectFailed, 'Cannot connect to MQTT broker: $exc');
    }
    if (!adapter.isConnected()) {
      throw CliException(CliExitCode.connectFailed, 'Cannot connect to MQTT broker');
    }
  }
}
