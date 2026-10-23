import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/project/project_edit_viewmodel.dart';
import '../helpers/test_setup.dart';

void main() {
  setUp(() => setUpServices());
  tearDown(tearDownServices);

  ProjectEditViewmodel validNewProject() {
    var viewmodel = ProjectEditViewmodel(null);
    viewmodel.form.control(ProjectEditViewmodel.projectNameField).value = 'Project';
    viewmodel.form.control(ProjectEditViewmodel.mqttHostnameField).value = 'test.mosquitto.org';
    return viewmodel;
  }

  group('ProjectEditViewmodel protocol version', () {
    test('new projects use MQTT 5', () {
      var viewmodel = validNewProject();

      expect(viewmodel.isMqtt5, isTrue);
      expect(viewmodel.saveModel(), isTrue);
      expect(viewmodel.project!.mqttSettings.protocolVersion, MqttProtocolVersion.v5);
    });

    test('existing projects keep their version', () {
      var project = Project(MqttSettings('test.mosquitto.org', 'client', 1883), name: 'Old project');

      var viewmodel = ProjectEditViewmodel(project);

      expect(viewmodel.form.control(ProjectEditViewmodel.protocolVersionField).value, MqttProtocolVersion.v311);
      expect(viewmodel.isMqtt5, isFalse);
    });

    test('saves the MQTT 5 session settings', () {
      var viewmodel = validNewProject();
      viewmodel.form.control(ProjectEditViewmodel.cleanStartField).value = false;
      viewmodel.form.control(ProjectEditViewmodel.sessionExpiryIntervalField).value = 3600;

      expect(viewmodel.saveModel(), isTrue);

      var settings = viewmodel.project!.mqttSettings;
      expect(settings.cleanStart, isFalse);
      expect(settings.sessionExpiryInterval, 3600);
    });

    test('changes the version of an existing project', () {
      var project = Project(MqttSettings('test.mosquitto.org', 'client', 1883), name: 'Old project');
      var viewmodel = ProjectEditViewmodel(project);

      viewmodel.form.control(ProjectEditViewmodel.protocolVersionField).value = MqttProtocolVersion.v5;
      expect(viewmodel.saveModel(), isTrue);

      expect(project.mqttSettings.protocolVersion, MqttProtocolVersion.v5);
    });

    test('disables the session settings for MQTT 3.1.1', () async {
      var viewmodel = validNewProject();
      var notified = 0;
      viewmodel.addListener(() => notified++);

      viewmodel.form.control(ProjectEditViewmodel.protocolVersionField).value = MqttProtocolVersion.v311;
      await Future.delayed(Duration.zero);

      expect(notified, greaterThan(0));
      expect(viewmodel.form.control(ProjectEditViewmodel.cleanStartField).disabled, isTrue);
      expect(viewmodel.form.control(ProjectEditViewmodel.sessionExpiryIntervalField).disabled, isTrue);

      viewmodel.form.control(ProjectEditViewmodel.protocolVersionField).value = MqttProtocolVersion.v5;
      await Future.delayed(Duration.zero);

      expect(viewmodel.form.control(ProjectEditViewmodel.sessionExpiryIntervalField).enabled, isTrue);
    });

    test('an invalid session expiry only blocks saving for MQTT 5', () async {
      var viewmodel = validNewProject();
      viewmodel.form.control(ProjectEditViewmodel.sessionExpiryIntervalField).value = -1;
      expect(viewmodel.saveModel(), isFalse);

      viewmodel.form.control(ProjectEditViewmodel.protocolVersionField).value = MqttProtocolVersion.v311;
      await Future.delayed(Duration.zero);
      expect(viewmodel.saveModel(), isTrue);
    });
  });
}
