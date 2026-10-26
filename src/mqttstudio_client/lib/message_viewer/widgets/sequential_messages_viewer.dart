import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/protocol/widgets/interpreted_payload_view.dart';
import 'package:provider/provider.dart';

import '../../common/widgets/fast_topic_chip.dart';

class SequentialMessagesViewer extends StatelessWidget {
  SequentialMessagesViewer({Key? key}) : super(key: key);
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Consumer<MessageViewerViewmodel>(builder: (context, viewmodel, child) {
      var messages = viewmodel.messageBuffer.getMessages(viewmodel.filter);
      return Expanded(
          child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  viewmodel.delayViewUpdate();
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
  }
}

class MessagesViewerRow extends StatelessWidget {
  final ReceivedMqttMessage message;
  final MessageViewerViewmodel viewmodel;

  const MessagesViewerRow(this.message, this.viewmodel, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('.000', context.locale.countryCode);
    var topic = FastTopicChip(
        topic: message.topicName,
        topicColor: context.read<MessageViewerViewmodel>().getTopicColor(message.topicName),
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
              ..._buildSummary(context),
            ],
          ),
          SizedBox(
            height: 12,
          ),
        ],
      ),
    );
  }

  // what the message says, for a protocol like VDA 5050 (doc/vda5050-design.md §7)
  List<Widget> _buildSummary(BuildContext context) {
    var interpretation = viewmodel.interpret(message);
    if (interpretation == null || interpretation.summary.isEmpty) {
      return [];
    }
    var icon = InterpretationStyle.iconOf(interpretation.level);
    return [
      SizedBox(width: 28),
      if (icon != null) ...[
        Icon(icon, size: 16, color: InterpretationStyle.colorOf(context, interpretation.level)),
        SizedBox(width: 6),
      ],
      Expanded(
          child: Text(interpretation.summary,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyLarge)),
    ];
  }
}
