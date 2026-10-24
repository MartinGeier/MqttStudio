import 'package:event/event.dart';
import 'package:mqttstudio/message_viewer/message_buffer.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/model/topic_subscription.dart';

// Where the topic viewer widgets get their messages from: the live MessageViewer or a recording
// (doc/recorder-design.md §7.2)
abstract class MessageSource {
  MQTTMessageBuffer get messageBuffer;
  Event<ReceivedMqttMessage> get messageReceivedEvent;
  Event get messagesClearedEvent;
  Event get topicSubscriptionsChangedEvent;
  List<TopicSubscription> get topicSubscriptions;
  TopicColor getTopicColor(String topicName);
  // false for recorded messages: subscribe, play, pause and clear don't apply
  bool get isLive;
  bool get paused;
}
