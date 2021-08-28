import 'package:flutter/material.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import '../publish_topic_dialog.dart';

class TopicsViewCommandBar extends StatelessWidget {
  const TopicsViewCommandBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var viewmodel = context.read<ProjectGlobalViewmodel>();
    return Container(
      child: Column(
        children: [
          Divider(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  ButtonBar(
                    children: [
                      IconButton(
                          onPressed: viewmodel.isProjectOpen && viewmodel.paused ? () => viewmodel.playAllTopics() : null,
                          icon: Icon(Icons.play_arrow),
                          color: Colors.green,
                          tooltip: 'topicsviewer_commandbar.play.tooltip'.tr()),
                      IconButton(
                          onPressed: viewmodel.isProjectOpen && !viewmodel.paused ? () => viewmodel.pauseAllTopics() : null,
                          icon: Icon(Icons.pause),
                          color: Colors.blue,
                          tooltip: 'topicsviewer_commandbar.pause.tooltip'.tr()),
                      IconButton(
                        onPressed: viewmodel.isProjectOpen ? () => viewmodel.clearMessages() : null,
                        icon: Icon(Icons.not_interested),
                        tooltip: 'topicsviewer_commandbar.clear.tooltip'.tr(),
                      ),
                    ],
                  ),
                  SizedBox(height: 40, child: VerticalDivider()),
                  ButtonBar(children: [
                    IconButton(
                        onPressed: viewmodel.isProjectOpen ? () {} : null,
                        icon: Icon(Icons.timer),
                        tooltip: 'topicsviewer_commandbar.groupedviewer.tooltip'.tr()),
                    IconButton(
                        onPressed: viewmodel.isProjectOpen ? () {} : null,
                        icon: Icon(Icons.format_list_bulleted),
                        tooltip: 'topicsviewer_commandbar.listviewer.tooltip'.tr()),
                  ]),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: TextButton(
                    onPressed: viewmodel.isProjectOpen ? () => _publishTopicPressed(viewmodel, context) : null,
                    child: Row(
                      children: [
                        Icon(Icons.send),
                        SizedBox(width: 6),
                        Text('PUBLISH'),
                      ],
                    )),
              ),
            ],
          ),
          Divider(height: 4),
        ],
      ),
    );
  }

  _publishTopicPressed(ProjectGlobalViewmodel viewmodel, BuildContext context) async {
    if (viewmodel.isProjectOpen) {
      await showDialog(context: context, builder: (context) => PublishTopicDialog());
    }
  }
}
