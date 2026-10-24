import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/project/open_project_viewmodel.dart';
import 'package:mqttstudio/project/project_edit_viewmodel.dart';
import 'package:mqttstudio/project/project_viewmodel.dart';
import '../helpers/test_setup.dart';

void main() {
  setUp(() => setUpServices());
  tearDown(tearDownServices);

  group('ProjectEditViewmodel for a new project', () {
    test('suggests a client id and the default port', () {
      var viewmodel = ProjectEditViewmodel(null);

      expect(viewmodel.form.control(ProjectEditViewmodel.clientIdField).value, isNotEmpty);
      expect(viewmodel.form.control(ProjectEditViewmodel.portField).value, 1883);
    });

    test('requires a valid name and hostname', () {
      var viewmodel = ProjectEditViewmodel(null);
      viewmodel.form.control(ProjectEditViewmodel.projectNameField).value = 'ab';
      viewmodel.form.control(ProjectEditViewmodel.mqttHostnameField).value = 'abcd';

      expect(viewmodel.saveModel(), isFalse);
      expect(viewmodel.project, isNull);
      expect(viewmodel.form.control(ProjectEditViewmodel.projectNameField).hasError('minLength'), isTrue);
      expect(viewmodel.form.control(ProjectEditViewmodel.mqttHostnameField).hasError('minLength'), isTrue);
    });

    test('requires a port between 1 and 65535', () {
      var viewmodel = ProjectEditViewmodel(null);
      viewmodel.form.control(ProjectEditViewmodel.projectNameField).value = 'Project';
      viewmodel.form.control(ProjectEditViewmodel.mqttHostnameField).value = 'test.mosquitto.org';

      viewmodel.form.control(ProjectEditViewmodel.portField).value = 0;
      expect(viewmodel.saveModel(), isFalse);
      viewmodel.form.control(ProjectEditViewmodel.portField).value = 65536;
      expect(viewmodel.saveModel(), isFalse);
      viewmodel.form.control(ProjectEditViewmodel.portField).value = 8883;
      expect(viewmodel.saveModel(), isTrue);
    });

    test('creates a project from the form', () {
      var viewmodel = ProjectEditViewmodel(null);
      viewmodel.form.control(ProjectEditViewmodel.projectNameField).value = 'Project';
      viewmodel.form.control(ProjectEditViewmodel.mqttHostnameField).value = 'test.mosquitto.org';
      viewmodel.form.control(ProjectEditViewmodel.clientIdField).value = 'client-42';
      viewmodel.form.control(ProjectEditViewmodel.portField).value = 8883;
      viewmodel.form.control(ProjectEditViewmodel.usernameField).value = 'user';
      viewmodel.form.control(ProjectEditViewmodel.passwordField).value = 'secret';
      viewmodel.form.control(ProjectEditViewmodel.useSslField).value = true;

      expect(viewmodel.saveModel(), isTrue);

      var project = viewmodel.project!;
      expect(project.name, 'Project');
      expect(project.mqttSettings.hostname, 'test.mosquitto.org');
      expect(project.mqttSettings.clientId, 'client-42');
      expect(project.mqttSettings.port, 8883);
      expect(project.mqttSettings.username, 'user');
      expect(project.mqttSettings.password, 'secret');
      expect(project.mqttSettings.useSsl, isTrue);
      expect(project.mqttSettings.useWebSockets, isFalse);
    });

    test('saves the certificate files', () {
      var viewmodel = ProjectEditViewmodel(null);
      viewmodel.form.control(ProjectEditViewmodel.projectNameField).value = 'Project';
      viewmodel.form.control(ProjectEditViewmodel.mqttHostnameField).value = 'broker.local';
      viewmodel.form.control(ProjectEditViewmodel.useSslField).value = true;
      viewmodel.form.control(ProjectEditViewmodel.caCertificateField).value = r' C:\certs\ca.crt ';
      viewmodel.form.control(ProjectEditViewmodel.clientCertificateField).value = r'C:\certs\client.crt';
      viewmodel.form.control(ProjectEditViewmodel.clientKeyField).value = '';
      viewmodel.form.control(ProjectEditViewmodel.clientKeyPasswordField).value = 'secret';

      expect(viewmodel.saveModel(), isTrue);

      var settings = viewmodel.project!.mqttSettings;
      expect(settings.caCertificatePath, r'C:\certs\ca.crt');
      expect(settings.clientCertificatePath, r'C:\certs\client.crt');
      expect(settings.clientKeyPath, isNull);
      expect(settings.clientKeyPassword, 'secret');
    });

    test('enables the certificate fields only for TLS over TCP', () async {
      var viewmodel = ProjectEditViewmodel(null);
      var certificate = viewmodel.form.control(ProjectEditViewmodel.clientCertificateField);
      expect(viewmodel.isCertificateEnabled, isFalse);
      expect(certificate.disabled, isTrue);

      viewmodel.form.control(ProjectEditViewmodel.useSslField).value = true;
      await Future.delayed(Duration.zero);
      expect(viewmodel.isCertificateEnabled, isTrue);
      expect(certificate.enabled, isTrue);

      viewmodel.form.control(ProjectEditViewmodel.useWebSocketField).value = true;
      await Future.delayed(Duration.zero);
      expect(viewmodel.isCertificateEnabled, isFalse);
      expect(certificate.disabled, isTrue);
    });

    test('a private key needs a client certificate', () async {
      var viewmodel = ProjectEditViewmodel(null);
      viewmodel.form.control(ProjectEditViewmodel.projectNameField).value = 'Project';
      viewmodel.form.control(ProjectEditViewmodel.mqttHostnameField).value = 'broker.local';
      viewmodel.form.control(ProjectEditViewmodel.useSslField).value = true;
      await Future.delayed(Duration.zero);
      viewmodel.form.control(ProjectEditViewmodel.clientKeyField).value = 'client.key';

      expect(viewmodel.saveModel(), isFalse);
      expect(viewmodel.form.control(ProjectEditViewmodel.clientKeyField).hasError('certificateRequired'), isTrue);

      viewmodel.form.control(ProjectEditViewmodel.clientCertificateField).value = 'client.crt';
      await Future.delayed(Duration.zero);

      expect(viewmodel.saveModel(), isTrue);
    });

    test('toggles the password visibility', () {
      var viewmodel = ProjectEditViewmodel(null);
      expect(viewmodel.isPasswordObscureText, isTrue);

      viewmodel.isPasswordObscureText = false;

      expect(viewmodel.isPasswordObscureText, isFalse);
    });
  });

  group('ProjectEditViewmodel for an existing project', () {
    Project existing() => Project(
        MqttSettings('broker.local', 'client', 1884, username: 'user', password: 'secret', useSsl: true)
          ..useWebSockets = true,
        name: 'Existing');

    test('fills the certificate fields from the project', () {
      var project = existing()
        ..mqttSettings.useWebSockets = false
        ..mqttSettings.clientCertificatePath = 'client.crt'
        ..mqttSettings.clientKeyPath = 'client.key';

      var viewmodel = ProjectEditViewmodel(project);

      expect(viewmodel.form.control(ProjectEditViewmodel.clientCertificateField).value, 'client.crt');
      expect(viewmodel.form.control(ProjectEditViewmodel.clientKeyField).value, 'client.key');
      expect(viewmodel.form.control(ProjectEditViewmodel.clientKeyField).enabled, isTrue);
    });

    test('fills the form from the project', () {
      var viewmodel = ProjectEditViewmodel(existing());

      expect(viewmodel.form.control(ProjectEditViewmodel.projectNameField).value, 'Existing');
      expect(viewmodel.form.control(ProjectEditViewmodel.mqttHostnameField).value, 'broker.local');
      expect(viewmodel.form.control(ProjectEditViewmodel.clientIdField).value, 'client');
      expect(viewmodel.form.control(ProjectEditViewmodel.portField).value, 1884);
      expect(viewmodel.form.control(ProjectEditViewmodel.usernameField).value, 'user');
      expect(viewmodel.form.control(ProjectEditViewmodel.passwordField).value, 'secret');
      expect(viewmodel.form.control(ProjectEditViewmodel.useSslField).value, isTrue);
      expect(viewmodel.form.control(ProjectEditViewmodel.useWebSocketField).value, isTrue);
    });

    test('updates the same project instance', () {
      var project = existing();
      var viewmodel = ProjectEditViewmodel(project);
      viewmodel.form.control(ProjectEditViewmodel.mqttHostnameField).value = 'other.broker';
      viewmodel.form.control(ProjectEditViewmodel.useWebSocketField).value = false;

      expect(viewmodel.saveModel(), isTrue);

      expect(viewmodel.project, same(project));
      expect(project.mqttSettings.hostname, 'other.broker');
      expect(project.mqttSettings.useWebSockets, isFalse);
      expect(project.mqttSettings.username, 'user');
    });
  });

  group('OpenProjectViewmodel', () {
    test('lists the saved projects, most recently used first', () async {
      await LocalStore().saveProject(createProject('Old')..lastUsed = DateTime(2025, 1, 1));
      await LocalStore().saveProject(createProject('Never used'));
      await LocalStore().saveProject(createProject('Recent')..lastUsed = DateTime(2026, 10, 1));

      var viewmodel = OpenProjectViewmodel();
      await pumpEventQueue();

      expect(viewmodel.projects.map((x) => x.name), ['Recent', 'Old', 'Never used']);
    });

    test('deletes a project', () async {
      await LocalStore().saveProject(createProject('First'));
      await LocalStore().saveProject(createProject('Second'));
      var viewmodel = OpenProjectViewmodel();
      await pumpEventQueue();

      await viewmodel.deleteProject(viewmodel.projects.firstWhere((x) => x.name == 'First'));

      expect(viewmodel.projects.map((x) => x.name), ['Second']);
      expect((await LocalStore().getProjects()).map((x) => x.name), ['Second']);
    });
  });

  group('ProjectViewmodel', () {
    test('opens and closes projects and notifies', () async {
      var viewmodel = ProjectViewmodel();
      var notified = 0;
      viewmodel.addListener(() => notified++);

      await viewmodel.openProject(createProject());
      expect(viewmodel.isProjectOpen, isTrue);
      expect(viewmodel.currentProject!.name, 'Test project');

      expect(await viewmodel.closeProject(), isTrue);
      expect(viewmodel.isProjectOpen, isFalse);
      expect(notified, greaterThanOrEqualTo(2));
    });
  });
}
