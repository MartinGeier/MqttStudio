import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/project/message_buffer_viewmodel.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:mqttstudio/common/widgets/topic_chip.dart';
import 'package:mqttstudio/topic_viewer/topic_viewer_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:flutter_simple_treeview/flutter_simple_treeview.dart';

class TreeMessagesViewer extends StatelessWidget {
  final _treeController = TreeController();
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Consumer<MessageBufferViewmodel>(builder: (context, msgBufferViewmodel, child) {
      return Consumer<TopicViewerViewmodel>(builder: (context, viewmodel, child) {
        var rootNode = msgBufferViewmodel.messagesTree;
        var nodes = _buildNodes(rootNode.children, viewmodel);
        return Expanded(
            child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: TreeView(
                nodes: nodes,
                indent: 32,
                treeController: _treeController,
              ),
            ),
          ),
        ));
      });
    });
  }

  List<TreeNode> _buildNodes(List<MessageNode> messageNodes, TopicViewerViewmodel viewmodel) {
    List<TreeNode> result = [];
    for (var msgNode in messageNodes) {
      var childNodes = (_buildNodes(msgNode.children, viewmodel));
      var realTopic = msgNode.message!.topicName.endsWith(msgNode.topicLevelName);
      var newNode = TreeNode(
          content: TopicChip(
            topic: msgNode.topicLevelName,
            countLabel: realTopic ? msgNode.messageCount.toString() : null,
            receivedTime: realTopic ? msgNode.message!.receivedOn : null,
            topicColor:
                realTopic ? GetIt.I.get<ProjectGlobalViewmodel>().getTopicColor(msgNode.message!.topicName) : TopicColor(Colors.grey),
            selected: realTopic ? viewmodel.selectedMessage == msgNode.message : false,
            onPressed: realTopic ? () => viewmodel.selectedMessage = msgNode.message : () {},
            showGlowAnimation: DateTime.now().difference(msgNode.message!.receivedOn) < Duration(milliseconds: 300),
          ),
          children: childNodes);
      result.add(newNode);
    }

    return result;
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
    var topic = TopicChip(
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
