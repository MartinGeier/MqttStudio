import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/model/project.dart';

void main() {
  group('Project.getHash', () {
    test('is stable for a project without id', () {
      var project = Project(MqttSettings('test.mosquitto.org', 'client', 1883));

      expect(project.id, isNull);
      expect(project.getHash(), project.getHash());
    });

    test('changes when the project is changed', () {
      var project = Project(MqttSettings('test.mosquitto.org', 'client', 1883));
      var hash = project.getHash();

      project.recentTopics.add('a/topic');

      expect(project.getHash(), isNot(hash));
    });
  });
}
