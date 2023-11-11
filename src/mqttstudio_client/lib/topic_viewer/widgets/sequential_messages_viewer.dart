import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/mqtt/mqtt_global_viewmodel.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:mqttstudio/topic_viewer/topic_viewer_viewmodel.dart';
import 'package:provider/provider.dart';

import '../../common/widgets/fast_topic_chip.dart';

class SequentialMessagesViewer extends StatelessWidget {
  SequentialMessagesViewer({Key? key}) : super(key: key);
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Consumer<MqttGlobalViewmodel>(builder: (context, mqttGlobalViewmodel, child) {
      return Consumer<TopicViewerViewmodel>(builder: (context, viewmodel, child) {
        var messages = mqttGlobalViewmodel.messageBuffer.getMessages(viewmodel.filter);
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
                        children: List.generate(
                          messages.length,
                          (index) => MessagesViewerRow(messages[index], viewmodel),
                        )),
                  ),
                )));
      });
    });
  }
}

class MessagesViewerRow extends StatelessWidget {
  final ReceivedMqttMessage message;
  final TopicViewerViewmodel viewmodel;

  const MessagesViewerRow(this.message, this.viewmodel, {Key? key}) : super(key: key);

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
