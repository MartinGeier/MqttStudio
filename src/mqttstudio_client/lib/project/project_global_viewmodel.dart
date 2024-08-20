import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/project/project_service.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel for all project related operations.
class ProjectGlobalViewmodel extends SrxChangeNotifier {
  late ProjectService _projectService;
  bool paused = false;

  ProjectGlobalViewmodel() {
    _projectService = GetIt.I.get<ProjectService>();
    _projectService.projectOpenedEvent.subscribe((_) => _projectOpened());
    _projectService.projectClosedEvent.subscribe((_) => _projectClosed());
    _projectService.topicSubscriptionsChangedEvent.subscribe((_) => _topicSubriptionsChanged());
  }

  @override
  void dispose() {
    _projectService.projectOpenedEvent.unsubscribeAll();
    _projectService.projectClosedEvent.unsubscribeAll();
    _projectService.topicSubscriptionsChangedEvent.unsubscribeAll();
    super.dispose();
  }

  Project? get currentProject => _projectService.currentProject;

  bool get isProjectOpen => _projectService.isProjectOpen;

  Future openProject(Project? newProject) async {
    await _projectService.openProject(newProject);
    notifyListeners();
  }

  Future<bool> closeProject([bool forceSave = false]) async {
    bool result = await _projectService.closeProject(forceSave);
    if (result) {
      notifyListeners();
    }
    return result;
  }

  Future saveProject() async {
    await _projectService.saveProject();
  }

  TopicColor getTopicColor(String topicName) {
    return _projectService.getTopicColor(topicName);
  }

  void addTopicSubscription(TopicSubscription subscription) {
    _projectService.addTopicSubscription(subscription);
  }

  void removeTopicSubscription(String topic) {
    _projectService.removeTopicSubscription(topic);
  }

  void tooglePauseTopicSubscription(String topic) {
    _projectService.tooglePauseTopicSubscription(topic);
  }

  void pauseAllTopics() {
    _projectService.pauseAllTopics();
  }

  void playAllTopics() {
    _projectService.playAllTopics();
  }

  void clearMessages() {
    _projectService.clearMessages();
  }

  void publishTopic(String topic, dynamic payload, MqttPayloadType payloadType, bool retain, [MqttQos qos = MqttQos.atMostOnce]) {
    _projectService.publishTopic(topic, payload, payloadType, retain, qos);
  }

  _projectOpened() {
    notifyListeners();
  }

  _projectClosed() {
    notifyListeners();
  }

  _topicSubriptionsChanged() {
    notifyListeners();
  }
}
