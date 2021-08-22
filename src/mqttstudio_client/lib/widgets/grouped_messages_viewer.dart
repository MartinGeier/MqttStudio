import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/viewmodel/message_buffer_viewmodel.dart';
import 'package:mqttstudio/viewmodel/project_global_viewmodel.dart';
import 'package:mqttstudio/widgets/topic_chip.dart';
import 'package:provider/provider.dart';

class GroupedMessagesViewer extends StatelessWidget {
  const GroupedMessagesViewer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: GetIt.I.get<ProjectGlobalViewmodel>().messageBufferViewmodel,
        child: Consumer<MessageBufferViewmodel>(builder: (context, viewmodel, child) {
          var groupedMessages = viewmodel.getGroupMessages(MessageGroupTimePeriod.tenSeconds);
          return Expanded(
              child: Scrollbar(
                  isAlwaysShown: true,
                  showTrackOnHover: true,
                  child: ListView.builder(
                      itemCount: groupedMessages.length,
                      itemBuilder: (context, index) {
                        return GroupedMessagesViewerRow(groupedMessages[index], viewmodel);
                      })));
        }));
  }
}

class GroupedMessagesViewerRow extends StatelessWidget {
  final MessageGroup messageGroup;
  final MessageBufferViewmodel viewmodel;

  const GroupedMessagesViewerRow(this.messageGroup, this.viewmodel, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var topics = List<TopicChip>.generate(messageGroup.messages.length, (index) {
      var topicName = messageGroup.messages[index].topicName;
      return TopicChip(topic: topicName, topicColor: GetIt.I.get<ProjectGlobalViewmodel>().getTopicColor(topicName), onPressed: () {});
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
