import 'package:flutter/material.dart';
import 'package:mqttstudio/common/browser_performance_warning.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:mqttstudio/common/newsletter_signup_dialog.dart';
import 'package:mqttstudio/common/widgets/main_appbar.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:mqttstudio/topic_viewer/topic_detailviewer_viewmodel.dart';
import 'package:mqttstudio/topic_viewer/widgets/grouped_messages_viewer.dart';
import 'package:mqttstudio/topic_viewer/widgets/message_detail_view.dart';
import 'package:mqttstudio/topic_viewer/widgets/sequential_messages_viewer.dart';
import 'package:mqttstudio/topic_viewer/widgets/topic_subscription_panel.dart';
import 'package:mqttstudio/topic_viewer/widgets/topics_viewer_command_bar.dart';
import 'package:mqttstudio/topic_viewer/widgets/tree_messages_viewer.dart';
import 'package:provider/provider.dart';
import 'package:mqttstudio/common/widgets/navigation_drawer.dart' as navDrawer;
import 'package:flutter/foundation.dart';

class TopicDetailViewerPage extends StatefulWidget {
  const TopicDetailViewerPage();

  @override
  State<TopicDetailViewerPage> createState() => _TopicDetailViewerPageState();
}

class _TopicDetailViewerPageState extends State<TopicDetailViewerPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kIsWeb) {
        _showBrowserPerformanceWarning(context);
      } else {
        _showNewsletterSignup(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
        length: 4,
        child: ChangeNotifierProvider(
            create: (context) => TopicDetailViewerViewmodel(),
            child: Consumer<TopicDetailViewerViewmodel>(builder: (context, viewmodel, child) {
              return Consumer<ProjectGlobalViewmodel>(builder: (context, projectGlobalViewmodel, child) {
                return Scaffold(
                  appBar: MainAppBar(viewmodel: projectGlobalViewmodel),
                  drawer: navDrawer.NavigationDrawer(),
                  body: Container(
                    child: Column(
                      children: [
                        TopicSubscriptionPanel(),
                        TopicsViewCommandBar(),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              projectGlobalViewmodel.isProjectOpen
                                  ? viewmodel.topicViewMode == TopicViewMode.Grouped
                                      ? GroupedMessagesViewer()
                                      : viewmodel.topicViewMode == TopicViewMode.Tree
                                          ? TreeMessagesViewer()
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
                );
              });
            })));
  }

  void _showBrowserPerformanceWarning(BuildContext context) async {
    var browserPerformanceWarningDoNotShow = await LocalStore().getBrowserPerformanceWarningDoNotShow();
    if (!(browserPerformanceWarningDoNotShow)) {
      showDialog(context: context, builder: (_) => BrowserPerformanceWarning());
    }
  }

  void _showNewsletterSignup(BuildContext context) async {
    var newsletterSignupDoNotShow = await LocalStore().getNewsletterSignupDoNotShow();
    if (!(newsletterSignupDoNotShow)) {
      showDialog(context: context, builder: (_) => NewsletterSignupDialog());
    }
  }
}
