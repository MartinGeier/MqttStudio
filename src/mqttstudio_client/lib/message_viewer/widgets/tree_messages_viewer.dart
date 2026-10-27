import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqttstudio/common/widgets/error_snackbar.dart';
import 'package:mqttstudio/message_viewer/retained_messages_dialog.dart';
import 'package:mqttstudio/message_viewer/topic_stats.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/message_viewer/message_buffer.dart';
import 'package:mqttstudio/common/widgets/topic_chip.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:flutter_simple_treeview/flutter_simple_treeview.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:mqttstudio/protocol/protocol_profile.dart';
import 'package:mqttstudio/protocol/widgets/interpreted_payload_view.dart';
import 'package:mqttstudio/protocol/widgets/rebirth_request.dart';

enum _TreeAction {
  copyTopic,
  copyBranch,
  copyLevel,
  subscribe,
  unsubscribe,
  expandBranch,
  collapseBranch,
  expandAll,
  collapseAll,
  retained,
  rebirth
}

class TreeMessagesViewer extends StatelessWidget {
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Consumer<MessageViewerViewmodel>(builder: (context, viewmodel, child) {
      var rootNode = viewmodel.messageBuffer.getMessagesTree(viewmodel.filter);
      var nodes = _buildNodes(rootNode.children, '', viewmodel, context, viewmodel.statsReference);
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
              treeController: viewmodel.treeController,
            ),
          ),
        ),
      ));
    });
  }

  List<TreeNode> _buildNodes(List<MessageNode> messageNodes, String parentPath, MessageViewerViewmodel viewmodel,
      BuildContext context, DateTime reference) {
    List<TreeNode> result = [];
    for (var msgNode in messageNodes) {
      var path = parentPath.isEmpty ? msgNode.topicLevelName : '$parentPath/${msgNode.topicLevelName}';
      var childNodes = _buildNodes(msgNode.children, path, viewmodel, context, reference);
      var realTopic = msgNode.isTopic;
      var title = realTopic ? viewmodel.documentedTitleOf(msgNode.message!.topicName) : null;
      var chip = TopicChip(
        topic: msgNode.topicLevelName,
        countLabel: realTopic ? msgNode.messageCount.toString() : null,
        receivedTime: realTopic ? msgNode.message!.receivedOn : null,
        topicColor: realTopic
            ? context.read<MessageViewerViewmodel>().getTopicColor(msgNode.message!.topicName)
            : TopicColor(Colors.grey),
        selected: realTopic ? viewmodel.selectedMessage == msgNode.message : false,
        onPressed: realTopic ? () => viewmodel.selectedMessage = msgNode.message : () {},
      );
      var interpretation = realTopic ? viewmodel.interpret(msgNode.message!) : null;
      var content = Row(mainAxisSize: MainAxisSize.min, children: [
        // the documented title of the topic
        title == null ? chip : Tooltip(message: title, child: chip),
        // what the last message says, for a protocol like VDA 5050
        if (interpretation != null && interpretation.summary.isNotEmpty)
          Flexible(child: _buildSummary(context, interpretation)),
        if (realTopic && viewmodel.showTopicStats)
          Padding(padding: const EdgeInsets.only(left: 12), child: _buildStats(context, msgNode.stats, reference)),
      ]);
      result.add(TreeNode(
          key: MessageViewerViewmodel.treeKeyOf(path),
          content: GestureDetector(
              onSecondaryTapDown: (details) => _showContextMenu(context, viewmodel, path, msgNode, details.globalPosition),
              child: content),
          children: childNodes));
    }

    return result;
  }

  Widget _buildSummary(BuildContext context, Interpretation interpretation) {
    var icon = InterpretationStyle.iconOf(interpretation.level);
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: InterpretationStyle.colorOf(context, interpretation.level)),
          SizedBox(width: 4),
        ],
        Flexible(
            child: Text(interpretation.summary,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium)),
      ]),
    );
  }

  Widget _buildStats(BuildContext context, TopicStats stats, DateTime reference) {
    var since = stats.sinceLast(reference);
    var mean = stats.meanInterval;
    var jitter = stats.jitter;
    var parts = [
      'treeviewer.stats.rate'.tr(args: [TopicStats.formatRate(stats.messagesPerSecond(reference))]),
      TopicStats.formatBytesPerSecond(stats.bytesPerSecond(reference)),
      if (since != null) 'treeviewer.stats.since'.tr(args: [TopicStats.formatDuration(since)]),
      if (mean != null && jitter != null)
        'treeviewer.stats.interval'.tr(args: [TopicStats.formatDuration(mean), TopicStats.formatDuration(jitter)])
      else if (mean != null)
        'treeviewer.stats.mean'.tr(args: [TopicStats.formatDuration(mean)]),
    ];
    return Tooltip(
      message: 'treeviewer.stats.tooltip'.tr(),
      waitDuration: Duration(seconds: 1),
      child: Text(parts.join(' | '),
          style: Theme.of(context).textTheme.labelLarge!.copyWith(color: Theme.of(context).hintColor)),
    );
  }

  Future<void> _showContextMenu(
      BuildContext context, MessageViewerViewmodel viewmodel, String path, MessageNode node, Offset position) async {
    var overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    var branch = MessageViewerViewmodel.branchFilterOf(path);
    var level = path.contains('/') ? '${path.substring(0, path.lastIndexOf('/'))}/+' : '+';
    var edgeNodes = viewmodel.edgeNodesIn(path);
    var action = await showMenu<_TreeAction>(
        context: context,
        position: RelativeRect.fromRect(position & Size(1, 1), Offset.zero & overlay.size),
        items: [
          _buildMenuItem(_TreeAction.copyTopic, Icons.copy, 'treeviewer.menu.copytopic'.tr(args: [path])),
          _buildMenuItem(_TreeAction.copyBranch, Icons.copy, 'treeviewer.menu.copytopic'.tr(args: [branch])),
          _buildMenuItem(_TreeAction.copyLevel, Icons.copy, 'treeviewer.menu.copytopic'.tr(args: [level])),
          if (viewmodel.canChangeSubscriptions) ..._buildSubscriptionItems(viewmodel, path, branch),
          PopupMenuDivider(),
          if (node.children.isNotEmpty) ...[
            _buildMenuItem(_TreeAction.expandBranch, Icons.unfold_more, 'treeviewer.menu.expandbranch'.tr()),
            _buildMenuItem(_TreeAction.collapseBranch, Icons.unfold_less, 'treeviewer.menu.collapsebranch'.tr()),
          ],
          _buildMenuItem(_TreeAction.expandAll, Icons.unfold_more_double, 'treeviewer.menu.expandall'.tr()),
          _buildMenuItem(_TreeAction.collapseAll, Icons.unfold_less_double, 'treeviewer.menu.collapseall'.tr()),
          if (viewmodel.canChangeSubscriptions) ...[
            PopupMenuDivider(),
            _buildMenuItem(_TreeAction.retained, Icons.inventory_2_outlined, 'treeviewer.menu.retained'.tr(args: [branch]),
                enabled: viewmodel.isConnected),
          ],
          // Sparkplug: the edge nodes of the branch (doc/sparkplug-design.md §12.2, R2)
          if (viewmodel.isLive && edgeNodes.isNotEmpty)
            _buildMenuItem(
                _TreeAction.rebirth,
                Icons.autorenew,
                edgeNodes.length == 1
                    ? 'treeviewer.menu.rebirth.one'.tr(args: [edgeNodes.single.edgeNode])
                    : 'treeviewer.menu.rebirth.other'.tr(args: ['${edgeNodes.length}']),
                enabled: viewmodel.canRequestRebirth),
        ]);
    if (action == null || !context.mounted) {
      return;
    }
    if (action == _TreeAction.rebirth) {
      await RebirthRequest.confirmAndSend(context, viewmodel, edgeNodes);
      return;
    }
    await _onAction(context, viewmodel, action, path, branch, level);
  }

  List<PopupMenuEntry<_TreeAction>> _buildSubscriptionItems(MessageViewerViewmodel viewmodel, String path, String branch) {
    var inBranch = viewmodel.subscriptionsInBranch(path);
    var unsubscribe = inBranch.isEmpty
        ? 'treeviewer.menu.nounsubscribe'.tr()
        : 'treeviewer.menu.unsubscribe'.plural(inBranch.length, namedArgs: {'topic': inBranch.first.topic});
    return [
      PopupMenuDivider(),
      _buildMenuItem(_TreeAction.subscribe, Icons.add, 'treeviewer.menu.subscribe'.tr(args: [branch]),
          enabled: !viewmodel.isSubscribed(branch)),
      _buildMenuItem(_TreeAction.unsubscribe, Icons.remove, unsubscribe, enabled: inBranch.isNotEmpty),
    ];
  }

  PopupMenuItem<_TreeAction> _buildMenuItem(_TreeAction action, IconData icon, String label, {bool enabled = true}) {
    return PopupMenuItem(
        value: action,
        enabled: enabled,
        child: Row(children: [Icon(icon, size: 20), SizedBox(width: 12), Flexible(child: Text(label))]));
  }

  Future<void> _onAction(BuildContext context, MessageViewerViewmodel viewmodel, _TreeAction action, String path,
      String branch, String level) async {
    switch (action) {
      case _TreeAction.copyTopic:
        await Clipboard.setData(ClipboardData(text: path));
      case _TreeAction.copyBranch:
        await Clipboard.setData(ClipboardData(text: branch));
      case _TreeAction.copyLevel:
        await Clipboard.setData(ClipboardData(text: level));
      case _TreeAction.subscribe:
        try {
          viewmodel.subscribeToBranch(path);
        } on SrxServiceException catch (exc) {
          ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(exc.errorMessage, context));
        }
      case _TreeAction.unsubscribe:
        viewmodel.unsubscribeFromBranch(path);
      case _TreeAction.expandBranch:
        viewmodel.expandBranch(path);
      case _TreeAction.collapseBranch:
        viewmodel.collapseBranch(path);
      case _TreeAction.expandAll:
        viewmodel.expandAll();
      case _TreeAction.collapseAll:
        viewmodel.collapseAll();
      case _TreeAction.retained:
        await showRetainedMessagesDialog(context, filter: branch);
      case _TreeAction.rebirth:
        // sent with the edge nodes of the menu, see _showContextMenu
        break;
    }
  }
}

class MessagesViewerRow extends StatelessWidget {
  final ReceivedMqttMessage message;
  final MessageViewerViewmodel viewmodel;

  const MessagesViewerRow(this.message, this.viewmodel, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('.000', context.locale.countryCode);
    var topic = TopicChip(
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
