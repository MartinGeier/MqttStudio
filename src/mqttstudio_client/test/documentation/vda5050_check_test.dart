import 'dart:typed_data';
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/documentation/engine/conformance_checker.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/presets/vda5050_preset.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_rules.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:mqttstudio/simulator/engine/simulator_runner.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/model/vda5050_source.dart';
import 'package:mqttstudio/simulator/vda5050/robot_fault.dart';
import 'package:mqttstudio/simulator/vda5050/simulated_fleet.dart';
import 'package:typed_data/typed_buffers.dart';

// hands every published message to the check, as the broker would deliver it
class _CheckingPublisher implements SimulatorPublisher {
  final ConformanceChecker checker;
  @override
  bool isConnected = true;
  @override
  bool supportsProperties = true;

  _CheckingPublisher(this.checker);

  @override
  void publish(String topic, Uint8Buffer payload, MqttQos qos, bool retain, MqttMessageProperties? properties) {
    checker.check(
        RecordedMessage(
            offsetMicros: 0,
            topic: topic,
            payload: Uint8List.fromList(payload),
            qos: qos,
            retain: retain,
            properties: properties),
        clock.now());
  }
}

// runs a simulated fleet through the check against the preset; the faults are injected into the first robot
List<Finding> _check(VdaVersion version, TopicDocumentation documentation, {List<RobotFault> faults = const []}) {
  late List<Finding> findings;
  fakeAsync((async) {
    var checker = ConformanceChecker(documentation);
    var runner = SimulatorRunner(_CheckingPublisher(checker), seed: 1);
    var device = SimulatedDevice(
        name: 'fleet',
        kind: DeviceKind.vda5050,
        instanceCount: 3,
        vda5050: Vda5050Source(
            version: version,
            interfaceName: Vda5050Preset.defaultInterfaceName(version),
            columns: 4,
            rows: 3,
            maxIdleSec: 1,
            minOrderNodes: 2,
            maxOrderNodes: 6,
            actionProbability: 0.5,
            seed: 5));
    runner.startDevice(device);
    void tick(Duration time) {
      for (var i = 0; i < time.inSeconds; i++) {
        async.elapse(const Duration(seconds: 1));
        checker.checkStale(clock.now());
      }
    }

    tick(const Duration(seconds: 30));
    var fleet = runner.fleetOf(device.id)!;
    for (var fault in faults) {
      fleet.inject(fleet.robots.first, fault);
      tick(const Duration(seconds: 1));
    }
    tick(const Duration(minutes: 3));
    runner.stopAll();
    findings = checker.findings;
    runner.dispose();
  });
  return findings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (var version in VdaVersion.values) {
    group(Vda5050Preset.nameOf(version), () {
      late TopicDocumentation documentation;

      setUpAll(() async {
        documentation = (await Vda5050Preset.build(version, interfaceName: Vda5050Preset.defaultInterfaceName(version)))
            .documentation;
      });

      test('a clean simulation gives no findings', () {
        var findings = _check(version, documentation);
        expect(findings.map((finding) => '${finding.ruleId} ${finding.topic}: ${finding.detail}'), isEmpty);
      });

      // each protocol fault of the simulator makes exactly its rule fire, and nothing else
      var expected = {
        RobotFault.skipHeaderIds: Vda5050Rule.headerIdGap,
        RobotFault.clockSkew: Vda5050Rule.timestampSkew,
        RobotFault.wrongSerialNumber: Vda5050Rule.headerDiffers,
        RobotFault.brokenOrder: Vda5050Rule.orderStructure,
        RobotFault.lowerOrderUpdate: Vda5050Rule.orderUpdate,
        if (version.isV3) RobotFault.responseWithoutRequest: Vda5050Rule.responseWithoutRequest,
      };
      for (var entry in expected.entries) {
        test('${entry.key.name} is found as ${entry.value}', () {
          var findings = _check(version, documentation, faults: [entry.key]);
          expect(findings.map((finding) => finding.ruleId).toSet(), {entry.value},
              reason: findings.map((finding) => '${finding.ruleId} ${finding.detail}').join('\n'));
        });
      }

      // a broken connection is the robot's trouble, not a protocol violation; the other robots keep the state
      // template from going stale
      test('robot and connection faults are no findings', () {
        var findings = _check(version, documentation,
            faults: [RobotFault.fatal, RobotFault.pause, RobotFault.emergencyStop, RobotFault.connectionBroken]);
        expect(findings.map((finding) => '${finding.ruleId} ${finding.detail}'), isEmpty);
      });
    });
  }

  test('an unanswered request is found after 10 s', () async {
    var documentation = (await Vda5050Preset.build(VdaVersion.v3, interfaceName: 'vda5050')).documentation;
    var findings = _check(VdaVersion.v3, documentation, faults: [RobotFault.unansweredRequest]);
    // the fault holds back the answer to the next request for 15 s
    expect(findings.map((finding) => finding.ruleId).toSet(), {Vda5050Rule.unansweredRequest});
    expect(findings.single.severity, FindingSeverity.warning);
    expect(findings.single.toJson()['rule'], Vda5050Rule.unansweredRequest);
  });

  test('the simulator knows the protocol rules it can break', () {
    expect(SimulatedFleet.skippedHeaderIds, greaterThan(1));
  });
}
