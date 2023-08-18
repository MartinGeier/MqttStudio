import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/project/message_buffer_viewmodel.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:mqttstudio/common/widgets/topic_chip.dart';
import 'package:mqttstudio/topic_viewer/topic_viewer_viewmodel.dart';
import 'package:provider/provider.dart';

import '../../common/widgets/fast_topic_chip.dart';

class SequentialMessagesViewer extends StatelessWidget {
  const SequentialMessagesViewer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<MessageBufferViewmodel>(builder: (context, msgBufferViewmodel, child) {
      return Consumer<TopicViewerViewmodel>(builder: (context, viewmodel, child) {
        var messages = msgBufferViewmodel.getMessages();
        return Expanded(
            child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ListView.builder(
              itemCount: messages.length,
              itemBuilder: (context, index) {
                return MessagesViewerRow(messages[index], msgBufferViewmodel, viewmodel);
              }),
        ));
      });
    });
  }
}

class MessagesViewerRow extends StatelessWidget {
  final ReceivedMqttMessage message;
  final MessageBufferViewmodel msgBufferViewmodel;
  final TopicViewerViewmodel viewmodel;

  const MessagesViewerRow(this.message, this.msgBufferViewmodel, this.viewmodel, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('.000', context.locale.countryCode);
    var topic = FastTopicChip(
        topic: message.topicName,
        topicColor: GetIt.I.get<ProjectGlobalViewmodel>().getTopicColor(message.topicName),
        selected: viewmodel.selectedMessage == message,
        onPressed: () => viewmodel.selectedMessage = message,
        dense: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Column(
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  DateFormat('HH:mm:ss').format(message.receivedOn) + nf.format(message.receivedOn.millisecond / 1000),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              SizedBox(width: 16),
              topic,
            ],
          ),
          SizedBox(
            height: 12,
          ),
        ],
      ),
    );
  }
}
