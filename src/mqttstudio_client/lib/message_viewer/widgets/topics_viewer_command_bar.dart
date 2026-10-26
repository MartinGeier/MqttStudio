import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mqttstudio/mqtt/mqtt_connection_viewmodel.dart';
import 'package:mqttstudio/project/project_viewmodel.dart';
import 'package:mqttstudio/message_viewer/message_buffer.dart';
import 'package:mqttstudio/message_viewer/message_filter.dart';
import 'package:mqttstudio/message_viewer/retained_messages_dialog.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import '../publish_topic_dialog.dart';
import '../save_buffer_dialog.dart';
import 'package:mqttstudio/common/widgets/error_snackbar.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:srx_flutter/srx_flutter.dart';

class TopicsViewCommandBar extends StatefulWidget {
  const TopicsViewCommandBar({Key? key}) : super(key: key);

  @override
  State<TopicsViewCommandBar> createState() => _TopicsViewCommandBarState();
}

class _TopicsViewCommandBarState extends State<TopicsViewCommandBar> {
  var _filterController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var projectViewmodel = context.read<ProjectViewmodel>();
    return Consumer<MessageViewerViewmodel>(
      builder: (context, viewmodel, child) {
        return Consumer<MqttConnectionViewmodel>(
          builder: (context, mqttConnectionViewmodel, child) {
            return Container(
              child: Column(
                children: [
                  Divider(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          // play, pause and clear only apply to live messages
                          if (viewmodel.isLive) ...[
                            _buildPlayPauseButtons(projectViewmodel, viewmodel),
                            SizedBox(height: 40, child: VerticalDivider()),
                          ],
                          _buildViewModeSelectionButtons(viewmodel, projectViewmodel),
                          SizedBox(height: 40, child: VerticalDivider()),
                          _buildGroupingPeriodDropDown(viewmodel, projectViewmodel),
                          if (viewmodel.topicViewMode == TopicViewMode.Tree) _buildTreeButtons(viewmodel, projectViewmodel),
                          _buildFilter(viewmodel, projectViewmodel),
                        ],
                      ),
                      if (viewmodel.isLive) _buildPublishButton(projectViewmodel, mqttConnectionViewmodel, context),
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
  }

  Padding _buildPublishButton(ProjectViewmodel projectViewmodel, MqttConnectionViewmodel mqttConnectionViewmodel, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Tooltip(
        message: 'topicsviewer_commandbar.publishbutton.tooltip'.tr(),
        child: TextButton(
            onPressed: projectViewmodel.isProjectOpen && mqttConnectionViewmodel.isConnected()
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

  Visibility _buildGroupingPeriodDropDown(MessageViewerViewmodel viewmodel, ProjectViewmodel projectViewmodel) {
    return Visibility(
      visible: viewmodel.topicViewMode == TopicViewMode.Grouped,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: OverflowBar(
              children: [
                Tooltip(
                  message: "Choose grouping time period",
                  child: DropdownButton<MessageGroupTimePeriod>(
                      isDense: true,
                      onChanged: _canView(viewmodel, projectViewmodel) ? (value) => viewmodel.groupTimePeriod = value! : null,
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
          ),
          SizedBox(height: 40, child: VerticalDivider()),
        ],
      ),
    );
  }

  Widget _buildTreeButtons(MessageViewerViewmodel viewmodel, ProjectViewmodel projectViewmodel) {
    var enabled = _canView(viewmodel, projectViewmodel);
    return Row(
      children: [
        IconButton(
            onPressed: enabled ? viewmodel.expandAll : null,
            icon: Icon(Icons.unfold_more),
            tooltip: 'topicsviewer_commandbar.expandall.tooltip'.tr()),
        IconButton(
            onPressed: enabled ? viewmodel.collapseAll : null,
            icon: Icon(Icons.unfold_less),
            tooltip: 'topicsviewer_commandbar.collapseall.tooltip'.tr()),
        IconButton(
            onPressed: enabled ? () => viewmodel.showTopicStats = !viewmodel.showTopicStats : null,
            icon: Icon(Icons.speed),
            color: viewmodel.showTopicStats ? Theme.of(context).colorScheme.secondary : null,
            tooltip: 'topicsviewer_commandbar.topicstats.tooltip'.tr()),
        SizedBox(height: 40, child: VerticalDivider()),
      ],
    );
  }

  Widget _buildFilter(MessageViewerViewmodel viewmodel, ProjectViewmodel projectViewmodel) {
    var enabled = _canView(viewmodel, projectViewmodel);
    var mode = viewmodel.filterMode;
    return Row(
      children: [
        Icon(Icons.filter_alt),
        SizedBox(width: 6),
        Tooltip(
          message: 'topicsviewer_commandbar.filtermode.tooltip'.tr(),
          child: DropdownButton<MessageFilterMode>(
              isDense: true,
              value: mode,
              onChanged: enabled ? (value) => _applyFilter(viewmodel, mode: value) : null,
              items: [
                for (var item in MessageFilterMode.values)
                  DropdownMenuItem(value: item, child: Text('topicsviewer_commandbar.filtermode.${item.name}'.tr()))
              ]),
        ),
        SizedBox(width: 12),
        Tooltip(
          message: 'topicsviewer_commandbar.filter.${mode.name}.tooltip'.tr(),
          waitDuration: Duration(seconds: 1),
          child: SizedBox(
              width: 360,
              height: 40,
              child: TextField(
                controller: _filterController,
                decoration: InputDecoration(
                    contentPadding: EdgeInsets.only(left: 12),
                    border: OutlineInputBorder(),
                    enabledBorder: viewmodel.filterError == null
                        ? null
                        : OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.error)),
                    labelText: 'topicsviewer_commandbar.filter.${mode.name}.label'.tr(),
                    isDense: true,
                    suffixIcon: _buildFilterSuffix(viewmodel)),
                enabled: enabled,
                onChanged: (value) => onFilterChanged(viewmodel, value),
                onSubmitted: (_) => _applyFilter(viewmodel),
              )),
        ),
      ],
    );
  }

  Widget _buildFilterSuffix(MessageViewerViewmodel viewmodel) {
    var regexColor = viewmodel.filterRegex ? Theme.of(context).colorScheme.secondary : Theme.of(context).disabledColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (viewmodel.filterError != null)
          Tooltip(
              message: viewmodel.filterError!,
              child: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error)),
        if (viewmodel.filterMode != MessageFilterMode.condition)
          IconButton(
            onPressed: () => _applyFilter(viewmodel, regex: !viewmodel.filterRegex),
            tooltip: 'topicsviewer_commandbar.filterregex.tooltip'.tr(),
            icon: Text('.*', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: regexColor)),
          ),
        IconButton(
          onPressed: () {
            _filterController.clear();
            _applyFilter(viewmodel);
          },
          tooltip: 'topicsviewer_commandbar.clearfilter.tooltip'.tr(),
          icon: Icon(Icons.clear),
        ),
      ],
    );
  }

  void onFilterChanged(MessageViewerViewmodel viewmodel, String value) {
    if (_debounce?.isActive ?? false) {
      _debounce?.cancel();
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _applyFilter(viewmodel));
  }

  void _applyFilter(MessageViewerViewmodel viewmodel, {MessageFilterMode? mode, bool? regex}) {
    _debounce?.cancel();
    viewmodel.setFilter(_filterController.text, mode: mode, regex: regex);
  }

  ToggleButtons _buildViewModeSelectionButtons(MessageViewerViewmodel viewmodel, ProjectViewmodel projectViewmodel) {
    return ToggleButtons(
        isSelected: [
          viewmodel.topicViewMode == TopicViewMode.Grouped,
          viewmodel.topicViewMode == TopicViewMode.Tree,
          viewmodel.topicViewMode == TopicViewMode.Sequential
        ],
        renderBorder: false,
        onPressed: _canView(viewmodel, projectViewmodel)
            ? (index) {
                switch (index) {
                  case 0:
                    viewmodel.topicViewMode = TopicViewMode.Grouped;
                    break;
                  case 1:
                    viewmodel.topicViewMode = TopicViewMode.Tree;
                    break;
                  case 2:
                    viewmodel.topicViewMode = TopicViewMode.Sequential;
                    break;
                }
              }
            : null,
        children: [
          Tooltip(message: 'topicsviewer_commandbar.groupedviewer.tooltip'.tr(), child: Icon(Icons.view_agenda)),
          Tooltip(message: 'topicsviewer_commandbar.treeviewer.tooltip'.tr(), child: Icon(Icons.account_tree)),
          Tooltip(message: 'topicsviewer_commandbar.sequentialviewer.tooltip'.tr(), child: Icon(Icons.format_list_bulleted))
        ]);
  }

  // recorded messages can be viewed without a project
  bool _canView(MessageViewerViewmodel viewmodel, ProjectViewmodel projectViewmodel) =>
      !viewmodel.isLive || projectViewmodel.isProjectOpen;

  Widget _buildPlayPauseButtons(ProjectViewmodel projectViewmodel, MessageViewerViewmodel messageViewerViewmodel) {
    var live = projectViewmodel.isProjectOpen;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: OverflowBar(
        spacing: 6,
        children: [
          IconButton(
              onPressed: live && messageViewerViewmodel.paused ? () => messageViewerViewmodel.playAllTopics() : null,
              icon: Icon(Icons.play_arrow),
              color: Colors.green,
              tooltip: 'topicsviewer_commandbar.play.tooltip'.tr()),
          IconButton(
              onPressed: live && !messageViewerViewmodel.paused ? () => messageViewerViewmodel.pauseAllTopics() : null,
              icon: Icon(Icons.pause),
              color: Colors.blue,
              tooltip: 'topicsviewer_commandbar.pause.tooltip'.tr()),
          IconButton(
            onPressed: live
                ? () {
                    messageViewerViewmodel.clearMessages();
                    messageViewerViewmodel.selectedMessage = null;
                  }
                : null,
            icon: Icon(Icons.not_interested),
            tooltip: 'topicsviewer_commandbar.clear.tooltip'.tr(),
          ),
          if (messageViewerViewmodel.isLive)
            IconButton(
              onPressed: messageViewerViewmodel.canSaveAsRecording ? () => _saveAsRecording(messageViewerViewmodel) : null,
              icon: Icon(Icons.save_alt),
              tooltip: 'topicsviewer_commandbar.saverecording.tooltip'.tr(),
            ),
          if (messageViewerViewmodel.isLive)
            IconButton(
              onPressed: live && messageViewerViewmodel.isConnected ? () => showRetainedMessagesDialog(context) : null,
              icon: Icon(Icons.inventory_2_outlined),
              tooltip: 'topicsviewer_commandbar.retained.tooltip'.tr(),
            ),
        ],
      ),
    );
  }

  Future<void> _saveAsRecording(MessageViewerViewmodel viewmodel) async {
    var name = await showDialog<String>(
        context: context,
        builder: (_) => SrxTheme(
            data: CustomTheme.srxTheme,
            child: SaveBufferDialog(name: viewmodel.defaultRecordingName, messageCount: viewmodel.messageBuffer.length)));
    if (name == null || !mounted) {
      return;
    }
    try {
      var info = await viewmodel.saveAsRecording(name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('topicsviewer_commandbar.saverecording.done'.tr(args: [info.name, '${info.footer.summary.messages}']))));
      }
    } catch (exc) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(errorSnackBar('topicsviewer_commandbar.saverecording.error'.tr(args: [exc.toString()]), context));
      }
    }
  }

  _publishTopicPressed(ProjectViewmodel viewmodel, BuildContext context) async {
    if (viewmodel.isProjectOpen) {
      await showDialog(context: context, builder: (context) => PublishTopicDialog());
    }
  }
}
