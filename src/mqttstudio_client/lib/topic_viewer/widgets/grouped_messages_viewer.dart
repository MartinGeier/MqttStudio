import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/project/message_buffer_viewmodel.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:mqttstudio/common/widgets/topic_chip.dart';
import 'package:mqttstudio/topic_viewer/topic_viewer_viewmodel.dart';
import 'package:provider/provider.dart';

class GroupedMessagesViewer extends StatelessWidget {
  const GroupedMessagesViewer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<MessageBufferViewmodel>(builder: (context, msgBufferViewmodel, child) {
      return Consumer<TopicViewerViewmodel>(builder: (context, viewmodel, child) {
        var groupedMessages = msgBufferViewmodel.getGroupMessages(viewmodel.groupTimePeriod);
        return Expanded(
            child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Scrollbar(
              isAlwaysShown: true,
              showTrackOnHover: true,
              child: ListView.builder(
                  itemCount: groupedMessages.length,
                  itemBuilder: (context, index) {
                    return GroupedMessagesViewerRow(groupedMessages[index], msgBufferViewmodel, viewmodel);
                  })),
        ));
      });
    });
  }
}

class GroupedMessagesViewerRow extends StatelessWidget {
  final MessageGroup messageGroup;
  final MessageBufferViewmodel msgBufferViewmodel;
  final TopicViewerViewmodel viewmodel;

  const GroupedMessagesViewerRow(this.messageGroup, this.msgBufferViewmodel, this.viewmodel, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var topics = List<TopicChip>.generate(messageGroup.messages.length, (index) {
      var topicName = messageGroup.messages[index].topicName;
      return TopicChip(
          topic: topicName,
          topicColor: GetIt.I.get<ProjectGlobalViewmodel>().getTopicColor(topicName),
          selected: viewmodel.selectedMessage == messageGroup.messages[index],
          onPressed: () => viewmodel.selectedMessage = messageGroup.messages[index]);
    });
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Column(
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  DateFormat('HH:mm:ss').format(messageGroup.beginOfPeriod),
                  style: Theme.of(context).textTheme.headline4,
                ),
              ),
              Expanded(
                child: Wrap(
                  runSpacing: 6,
                  spacing: 6,
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
