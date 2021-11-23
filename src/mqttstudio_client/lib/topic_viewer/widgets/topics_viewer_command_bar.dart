import 'package:flutter/material.dart';
import 'package:mqttstudio/common/mqtt_global_viewmodel.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:mqttstudio/project/message_buffer_viewmodel.dart';
import 'package:mqttstudio/topic_viewer/topic_viewer_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import '../publish_topic_dialog.dart';

class TopicsViewCommandBar extends StatelessWidget {
  const TopicsViewCommandBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var projectViewmodel = context.read<ProjectGlobalViewmodel>();
    return Consumer<MessageBufferViewmodel>(builder: (context, msgBufferViewmodel, child) {
      return Consumer<TopicViewerViewmodel>(
        builder: (context, viewmodel, child) {
          return Consumer<MqttGlobalViewmodel>(
            builder: (context, mqttGlobalViewmodel, child) {
              return Container(
                child: Column(
                  children: [
                    Divider(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            _buildPlayPauseButtons(projectViewmodel, msgBufferViewmodel, viewmodel),
                            SizedBox(height: 40, child: VerticalDivider()),
                            _buildViewModeSelectionButtons(viewmodel, projectViewmodel),
                            SizedBox(height: 40, child: VerticalDivider()),
                            _buildGroupingPeriodDropDown(viewmodel, projectViewmodel),
                          ],
                        ),
                        _buildPublishButton(projectViewmodel, mqttGlobalViewmodel, context),
                      ],
                    ),
                    Divider(height: 4),
                  ],
                ),
              );
            },
          );
        },
      );
    });
  }

  Padding _buildPublishButton(ProjectGlobalViewmodel projectViewmodel, MqttGlobalViewmodel mqttGlobalViewmodel, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Tooltip(
        message: 'topicsviewer_commandbar.publishbutton.tooltip'.tr(),
        child: TextButton(
            onPressed: projectViewmodel.isProjectOpen && mqttGlobalViewmodel.isConnected()
                ? () => _publishTopicPressed(projectViewmodel, context)
                : null,
            child: Row(
              children: [
                Icon(Icons.send),
                SizedBox(width: 6),
                Text('topicsviewer_commandbar.publishbutton.label'.tr()),
              ],
            )),
      ),
    );
  }

  Visibility _buildGroupingPeriodDropDown(TopicViewerViewmodel viewmodel, ProjectGlobalViewmodel projectViewmodel) {
    return Visibility(
      visible: viewmodel.topicViewMode == TopicViewMode.Grouped,
      child: ButtonBar(
        children: [
          Tooltip(
            message: "Choose grouping time period",
            child: DropdownButton<MessageGroupTimePeriod>(
                isDense: true,
                onChanged: projectViewmodel.isProjectOpen ? (value) => viewmodel.groupTimePeriod = value! : null,
                value: viewmodel.groupTimePeriod,
                items: [
                  DropdownMenuItem(value: MessageGroupTimePeriod.second, child: Text('1s')),
                  DropdownMenuItem(value: MessageGroupTimePeriod.tenSeconds, child: Text('10s')),
                  DropdownMenuItem(value: MessageGroupTimePeriod.minute, child: Text('1m')),
                  DropdownMenuItem(value: MessageGroupTimePeriod.hour, child: Text('1h'))
                ]),
          )
        ],
      ),
    );
  }

  ToggleButtons _buildViewModeSelectionButtons(TopicViewerViewmodel viewmodel, ProjectGlobalViewmodel projectViewmodel) {
    return ToggleButtons(
        isSelected: [viewmodel.topicViewMode == TopicViewMode.Grouped, viewmodel.topicViewMode == TopicViewMode.Sequential],
        renderBorder: false,
        onPressed: projectViewmodel.isProjectOpen
            ? (index) {
                switch (index) {
                  case 0:
                    viewmodel.topicViewMode = TopicViewMode.Grouped;
                    break;
                  case 1:
                    viewmodel.topicViewMode = TopicViewMode.Sequential;
                    break;
                }
              }
            : null,
        children: [
          Tooltip(message: 'topicsviewer_commandbar.groupedviewer.tooltip'.tr(), child: Icon(Icons.timer)),
          Tooltip(message: 'topicsviewer_commandbar.sequentialviewer.tooltip'.tr(), child: Icon(Icons.format_list_bulleted))
        ]);
  }

  ButtonBar _buildPlayPauseButtons(
      ProjectGlobalViewmodel projectViewmodel, MessageBufferViewmodel messageBufferViewmodel, TopicViewerViewmodel topicViewerViewmodel) {
    return ButtonBar(
      children: [
        IconButton(
            onPressed: projectViewmodel.isProjectOpen && messageBufferViewmodel.paused ? () => messageBufferViewmodel.play() : null,
            icon: Icon(Icons.play_arrow),
            color: Colors.green,
            tooltip: 'topicsviewer_commandbar.play.tooltip'.tr()),
        IconButton(
            onPressed: projectViewmodel.isProjectOpen && !messageBufferViewmodel.paused ? () => messageBufferViewmodel.pause() : null,
            icon: Icon(Icons.pause),
            color: Colors.blue,
            tooltip: 'topicsviewer_commandbar.pause.tooltip'.tr()),
        IconButton(
          onPressed: projectViewmodel.isProjectOpen
              ? () {
                  projectViewmodel.clearMessages();
                  topicViewerViewmodel.selectedMessage = null;
                }
              : null,
          icon: Icon(Icons.not_interested),
          tooltip: 'topicsviewer_commandbar.clear.tooltip'.tr(),
        ),
      ],
    );
  }

  _publishTopicPressed(ProjectGlobalViewmodel viewmodel, BuildContext context) async {
    if (viewmodel.isProjectOpen) {
      await showDialog(context: context, builder: (context) => PublishTopicDialog());
    }
  }
}
