import 'package:flutter/material.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/viewmodel/project_global_viewmodel.dart';
import 'package:mqttstudio/widgets/topic_chip.dart';
import 'package:provider/provider.dart';

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
                        'Subscribed Topics',
                        style: Theme.of(context).textTheme.headline4!.copyWith(color: Theme.of(context).custom.watermark),
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
                          onPressed: () => _topicPressed(),
                          onDeletePressed: () => _onDeletePressed(),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              FloatingActionButton( child: Icon(Icons.add), onPressed: viewmodel.isProjectOpen ? () => _addTopicPressed(viewmodel) : null)
            ],
          ));
    });
  }

  _topicPressed() {}

  _onDeletePressed() {}

  _addTopicPressed(ProjectGlobalViewmodel viewmodel) {
    if (viewmodel.isProjectOpen) {
      viewmodel.addTopicSubscription(TopicSubscription('production/milling/m02/humitidy', MqttQos.atLeastOnce));
    }
  }
}
