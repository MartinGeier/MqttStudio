import 'dart:math';

class Project {
  String name;
  String mqttHostname;
  late String clientId;

  Project(this.mqttHostname, this.clientId, {this.name = 'New Project'});
}
