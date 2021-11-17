import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:mqttstudio/common/widgets/connect_button.dart';
import 'package:mqttstudio/topic_viewer/topic_viewer_viewmodel.dart';
import 'package:mqttstudio/topic_viewer/widgets/grouped_messages_viewer.dart';
import 'package:mqttstudio/common/widgets/navigation_drawer.dart';
import 'package:mqttstudio/topic_viewer/widgets/message_detail_view.dart';
import 'package:mqttstudio/topic_viewer/widgets/sequential_messages_viewer.dart';
import 'package:mqttstudio/topic_viewer/widgets/topic_subscription_panel.dart';
import 'package:mqttstudio/topic_viewer/widgets/topics_viewer_command_bar.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

class TopicViewerPage extends StatelessWidget {
  const TopicViewerPage();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
        length: 4,
        child: ChangeNotifierProvider(
          create: (context) => TopicViewerViewmodel(),
          child: Consumer<TopicViewerViewmodel>(builder: (context, viewmodel, child) {
            return Consumer<ProjectGlobalViewmodel>(builder: (context, projectGlobalViewmodel, child) {
              return ChangeNotifierProvider.value(
                  value: GetIt.I.get<ProjectGlobalViewmodel>().messageBufferViewmodel,
                  child: Scaffold(
                    appBar: AppBar(
                      leadingWidth: 24,
                      title: Row(
                        children: [
                          ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: 250),
                              child: Text(projectGlobalViewmodel.currentProject?.name ?? 'topicviewerpage.noproject.label'.tr())),
                          SizedBox(
                            width: 48,
                          ),
                          Expanded(
                            child: TabBar(
                                isScrollable: true,
                                labelPadding: EdgeInsets.symmetric(vertical: 6),
                                indicatorWeight: 3,
                                indicatorColor: Theme.of(context).colorScheme.primary,
                                tabs: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 36),
                                    child: Text('topicviewerpage.menuitem.topicviewer'.tr()),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 48),
                                    child: Text('topicviewerpage.menuitem.simulator'.tr()),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 48),
                                    child: Text('topicviewerpage.menuitem.recorder'.tr()),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 48),
                                    child: Text('topicviewerpage.menuitem.documentation'.tr()),
                                  ),
                                ]),
                          )
                        ],
                      ),
                      actions: [ConnectButton()],
                    ),
                    drawer: NavigationDrawer(),
                    body: Container(
                      child: Column(
                        children: [
                          TopicSubscriptionPanel(),
                          TopicsViewCommandBar(),
                          Expanded(
                            child: Row(
                              children: [
                                projectGlobalViewmodel.isProjectOpen
                                    ? viewmodel.topicViewMode == TopicViewMode.Grouped
                                        ? GroupedMessagesViewer()
                                        : SequentialMessagesViewer()
                                    : Container(),
                                projectGlobalViewmodel.isProjectOpen
                                    ? viewmodel.selectedMessage != null
                                        ? MessageDetailView()
                                        : Container()
                                    : Container(),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  ));
            });
          }),
        ));
  }
}
