import 'package:flutter/material.dart';
import 'package:mqttstudio/topic_viewer/add_topic_dialog.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:mqttstudio/common/widgets/topic_chip.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

class TopicSubscriptionPanel extends StatelessWidget {
  const TopicSubscriptionPanel({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ProjectGlobalViewmodel>(builder: (context, viewmodel, child) {
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
                        style: Theme.of(context).textTheme.headline4!.copyWith(color: Theme.of(context).dividerColor),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.start,
                      runSpacing: 12,
                      spacing: 8,
                      children: List<Widget>.generate(viewmodel.currentProject?.topicSubscriptions.length ?? 0, (index) {
                        var topicSubscription = viewmodel.currentProject?.topicSubscriptions[index];
                        if (topicSubscription == null) {
                          return Container();
                        }
                        return TopicChip(
                          topic: topicSubscription.topic,
                          topicColor: topicSubscription.color,
                          onPressed: () => _topicPressed(topicSubscription.topic, viewmodel),
                          onDeletePressed: (topic) => _onDeletePressed(viewmodel, topic),
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
                onPressed: viewmodel.isProjectOpen ? () => _addTopicPressed(viewmodel, context) : null,
                backgroundColor: viewmodel.isProjectOpen ? Theme.of(context).colorScheme.secondary : Colors.grey,
              )
            ],
          ));
    });
  }

  _topicPressed(String topic, ProjectGlobalViewmodel viewmodel) {
    viewmodel.tooglePauseTopicSubscription(topic);
  }

  _onDeletePressed(ProjectGlobalViewmodel viewmodel, String topicName) {
    if (viewmodel.isProjectOpen) {
      viewmodel.removeTopicSubscription(topicName);
    }
  }

  _addTopicPressed(ProjectGlobalViewmodel viewmodel, BuildContext context) async {
    if (viewmodel.isProjectOpen) {
      var topicSubscription = await showDialog(context: context, builder: (context) => AddTopicDialog());
      if (topicSubscription != null) {
        viewmodel.addTopicSubscription(topicSubscription);
      }
    }
  }
}
