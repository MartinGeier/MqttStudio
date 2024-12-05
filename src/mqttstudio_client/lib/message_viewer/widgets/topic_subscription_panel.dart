import 'package:flutter/material.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/service/piwik_tracking_service.dart';
import 'package:mqttstudio/message_viewer/add_topic_dialog.dart';
import 'package:mqttstudio/project/project_viewmodel.dart';
import 'package:mqttstudio/common/widgets/topic_chip.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

class TopicSubscriptionPanel extends StatelessWidget {
  const TopicSubscriptionPanel({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ProjectViewmodel>(builder: (context, projectViewmodel, child) {
      return Consumer<MessageViewerViewmodel>(builder: (context, messageViewViewmodel, child) {
        return Container(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
            alignment: Alignment.topLeft,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.passthrough,
                    alignment: Alignment.center,
                    children: [
                      Center(
                        child: Text(
                          'topicsubscriptionpanel.watermark'.tr(),
                          style: Theme.of(context).textTheme.headlineMedium!.copyWith(color: Theme.of(context).dividerColor),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Wrap(
                        alignment: WrapAlignment.start,
                        runSpacing: 12,
                        spacing: 8,
                        children: List<Widget>.generate(projectViewmodel.currentProject?.topicSubscriptions.length ?? 0, (index) {
                          var topicSubscription = projectViewmodel.currentProject?.topicSubscriptions[index];
                          if (topicSubscription == null) {
                            return Container();
                          }
                          return TopicChip(
                            topic: topicSubscription.topic,
                            topicColor: topicSubscription.color,
                            onPressed: () => _topicPressed(topicSubscription.topic, messageViewViewmodel),
                            onDeletePressed: (topic) => _onDeletePressed(projectViewmodel, messageViewViewmodel, topic),
                            paused: topicSubscription.paused,
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                FloatingActionButton(
                  tooltip: "topicsubscriptionpanel.subscribebutton.tooltip".tr(),
                  child: Icon(Icons.add),
                  onPressed:
                      projectViewmodel.isProjectOpen ? () => _addTopicPressed(projectViewmodel, messageViewViewmodel, context) : null,
                  backgroundColor: projectViewmodel.isProjectOpen ? Theme.of(context).colorScheme.secondary : Colors.grey,
                )
              ],
            ));
      });
    });
  }

  _topicPressed(String topic, MessageViewerViewmodel viewmodel) {
    viewmodel.tooglePauseTopicSubscription(topic);
  }

  _onDeletePressed(ProjectViewmodel projectViewmodel, MessageViewerViewmodel messageViewerViewmodel, String topicName) {
    if (projectViewmodel.isProjectOpen) {
      messageViewerViewmodel.removeTopicSubscription(topicName);
    }
  }

  _addTopicPressed(ProjectViewmodel projectViewmodel, MessageViewerViewmodel messageViewerViewmodel, BuildContext context) async {
    if (projectViewmodel.isProjectOpen) {
      var topicSubscription = await showDialog(context: context, builder: (context) => AddTopicDialog());
      PiwikTrackingService().trackAction('Topic subscribed');
      if (topicSubscription != null) {
        messageViewerViewmodel.addTopicSubscription(topicSubscription);
      }
    }
  }
}
