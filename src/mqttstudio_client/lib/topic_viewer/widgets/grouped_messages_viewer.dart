import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/mqtt/mqtt_global_viewmodel.dart';
import 'package:mqttstudio/mqtt/mqtt_message_buffer.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:mqttstudio/topic_viewer/topic_viewer_viewmodel.dart';
import 'package:provider/provider.dart';

import '../../common/widgets/fast_topic_chip.dart';

class GroupedMessagesViewer extends StatelessWidget {
  GroupedMessagesViewer({Key? key}) : super(key: key);
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Consumer<MqttGlobalViewmodel>(builder: (context, mqttGlobalViewmodel, child) {
      return Consumer<TopicViewerViewmodel>(builder: (context, viewmodel, child) {
        var groupedMessages = mqttGlobalViewmodel.messageBuffer.getGroupMessages(viewmodel.groupTimePeriod, viewmodel.filter);
        return Expanded(
            child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              mqttGlobalViewmodel.delayViewUpdate();
              return true;
            },
            child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                trackVisibility: true,
                child: ListView(
                  controller: _scrollController,
                  children: List.generate(groupedMessages.length, (index) => GroupedMessagesViewerRow(groupedMessages[index], viewmodel)),
                )),
          ),
        ));
      });
    });
  }
}

class GroupedMessagesViewerRow extends StatelessWidget {
  final MessageGroup messageGroup;
  final TopicViewerViewmodel viewmodel;

  const GroupedMessagesViewerRow(this.messageGroup, this.viewmodel, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var topics = List<FastTopicChip>.generate(messageGroup.messages.length, (index) {
      var topicName = messageGroup.messages[index].topicName;
      return FastTopicChip(
          topic: topicName,
          topicColor: GetIt.I.get<ProjectGlobalViewmodel>().getTopicColor(topicName),
          selected: viewmodel.selectedMessage == messageGroup.messages[index],
          onPressed: () => viewmodel.selectedMessage = messageGroup.messages[index]);
    });
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 32, 4),
      child: Column(
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  DateFormat('HH:mm:ss').format(messageGroup.beginOfPeriod),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              Expanded(
                child: Wrap(
                  runSpacing: 6,
                  spacing: 24,
                  children: topics,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Divider()
        ],
      ),
    );
  }
}
