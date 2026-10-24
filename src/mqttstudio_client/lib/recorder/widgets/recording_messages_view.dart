import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/common/widgets/fast_topic_chip.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/message_viewer/widgets/grouped_messages_viewer.dart';
import 'package:mqttstudio/message_viewer/widgets/message_detail_view.dart';
import 'package:mqttstudio/message_viewer/widgets/sequential_messages_viewer.dart';
import 'package:mqttstudio/message_viewer/widgets/topics_viewer_command_bar.dart';
import 'package:mqttstudio/message_viewer/widgets/tree_messages_viewer.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/recorder/analysis/recording_message_source.dart';
import 'package:mqttstudio/recorder/recording_messages_viewmodel.dart';
import 'package:mqttstudio/recorder/widgets/recorder_format.dart';
import 'package:provider/provider.dart';

// The MESSAGES tab (doc/recorder-design.md §7.2): the topic viewer's widgets on the messages of the selected range.
// Each filter of the recording is a chip that hides or shows its topics.
class RecordingMessagesView extends StatelessWidget {
  const RecordingMessagesView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<RecordingMessagesViewmodel>();
    var viewer = context.watch<MessageViewerViewmodel>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildFilters(context, vm),
      TopicsViewCommandBar(),
      if (vm.isLoading) LinearProgressIndicator(),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          switch (viewer.topicViewMode) {
            TopicViewMode.Grouped => GroupedMessagesViewer(),
            TopicViewMode.Tree => TreeMessagesViewer(),
            TopicViewMode.Sequential => SequentialMessagesViewer(),
          },
          if (viewer.selectedMessage != null) MessageDetailView(),
        ]),
      ),
    ]);
  }

  Widget _buildFilters(BuildContext context, RecordingMessagesViewmodel vm) {
    var theme = Theme.of(context);
    var hint = theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor);
    var subscriptions = vm.source.topicSubscriptions;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        Expanded(
          child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (var sub in subscriptions)
              Tooltip(
                message: sub.paused ? 'recordingmessages.showfilter.tooltip'.tr() : 'recordingmessages.hidefilter.tooltip'.tr(),
                child: Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: FastTopicChip(
                    topic: sub.topic,
                    topicColor: sub.paused ? TopicColor(theme.custom.watermark) : sub.color,
                    onPressed: () => vm.toggleFilter(sub.topic),
                  ),
                ),
              ),
          ]),
        ),
        SizedBox(width: 12),
        Flexible(child: _buildStatus(context, vm, hint)),
      ]),
    );
  }

  Widget _buildStatus(BuildContext context, RecordingMessagesViewmodel vm, TextStyle hint) {
    if (vm.isLoading) {
      return Text('recordingmessages.loading.label'.tr(), style: hint);
    }
    if (vm.failed) {
      return Text('recordingmessages.failed.label'.tr(), style: hint.copyWith(color: Theme.of(context).colorScheme.error));
    }
    if (vm.isCut) {
      return Text(
          'recordingmessages.cut.label'.tr(args: [
            RecorderFormat.count(RecordingMessageSource.maxMessages),
            RecorderFormat.count(vm.messagesInRange),
          ]),
          style: hint.copyWith(color: Theme.of(context).colorScheme.error),
          textAlign: TextAlign.right);
    }
    return Text('recordingmessages.count.label'.tr(args: [RecorderFormat.count(vm.loadedCount)]), style: hint);
  }
}
