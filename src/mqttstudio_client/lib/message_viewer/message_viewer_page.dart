import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:mqttstudio/common/browser_performance_warning.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:mqttstudio/common/newsletter_signup_dialog.dart';
import 'package:mqttstudio/common/widgets/main_appbar.dart';
import 'package:mqttstudio/project/project_viewmodel.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/message_viewer/widgets/grouped_messages_viewer.dart';
import 'package:mqttstudio/message_viewer/widgets/message_detail_view.dart';
import 'package:mqttstudio/message_viewer/widgets/sequential_messages_viewer.dart';
import 'package:mqttstudio/message_viewer/widgets/topic_subscription_panel.dart';
import 'package:mqttstudio/message_viewer/widgets/topics_viewer_command_bar.dart';
import 'package:mqttstudio/message_viewer/widgets/tree_messages_viewer.dart';
import 'package:mqttstudio/simulator/simulator_page.dart';
import 'package:mqttstudio/recorder/recorder_page.dart';
import 'package:mqttstudio/documentation/documentation_page.dart';
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:event/event.dart';
import 'package:mqttstudio/recorder/engine/recorder_service.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:get_it/get_it.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:provider/provider.dart';
import 'package:mqttstudio/common/widgets/navigation_drawer.dart' as navDrawer;
import 'package:flutter/foundation.dart';
import 'package:mqttstudio/protocol/widgets/fleet_viewer.dart';
import 'package:mqttstudio/common/leave_page_guard.dart'
    if (dart.library.js_interop) 'package:mqttstudio/common/leave_page_guard_web.dart';

class MessageViewerPage extends StatefulWidget {
  const MessageViewerPage();

  @override
  State<MessageViewerPage> createState() => _MessageViewerPageState();
}

class _MessageViewerPageState extends State<MessageViewerPage> {
  late final AppLifecycleListener _lifecycleListener;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onExitRequested: _onExitRequested);
    installLeavePageGuard(() => GetIt.I.get<RecorderService>().isRecording);
    // the recorder tab opens the documentation tab
    GetIt.I.get<DocumentationService>().discoverRequestedEvent.subscribe(_showDocumentation);
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
            create: (context) => MessageViewerViewmodel(),
            builder: (context, child) {
              return Consumer<MessageViewerViewmodel>(builder: (context, viewmodel, child) {
                return Consumer<ProjectViewmodel>(builder: (context, projectViewmodel, child) {
                  var tabController = DefaultTabController.of(context);
                  _tabController = tabController;
                  return Scaffold(
                    appBar: MainAppBar(viewmodel: projectViewmodel),
                    drawer: navDrawer.NavigationDrawer(),
                    // IndexedStack keeps the state of the topic viewer while another tab is shown
                    body: AnimatedBuilder(
                      animation: tabController,
                      builder: (context, _) => IndexedStack(
                          index: tabController.index.clamp(MainAppBar.topicViewerTab, MainAppBar.documentationTab),
                          children: [
                            _buildTopicViewer(viewmodel, projectViewmodel),
                            SimulatorPage(),
                            RecorderPage(),
                            DocumentationPage(),
                          ]),
                    ),
                  );
                });
              });
            }));
  }

  Widget _buildTopicViewer(MessageViewerViewmodel viewmodel, ProjectViewmodel projectViewmodel) {
    return Column(
      children: [
        TopicSubscriptionPanel(),
        TopicsViewCommandBar(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              projectViewmodel.isProjectOpen
                  ? switch (viewmodel.topicViewMode) {
                      TopicViewMode.Grouped => GroupedMessagesViewer(),
                      TopicViewMode.Tree => TreeMessagesViewer(),
                      TopicViewMode.Sequential => SequentialMessagesViewer(),
                      TopicViewMode.Fleet => FleetViewer(),
                    }
                  : Container(),
              projectViewmodel.isProjectOpen
                  ? viewmodel.selectedMessage != null
                      ? MessageDetailView()
                      : Container()
                  : Container(),
            ],
          ),
        )
      ],
    );
  }

  void _showDocumentation(EventArgs? _) => _tabController?.animateTo(MainAppBar.documentationTab);

  @override
  void dispose() {
    GetIt.I.get<DocumentationService>().discoverRequestedEvent.unsubscribe(_showDocumentation);
    _lifecycleListener.dispose();
    super.dispose();
  }

  // closing the app while recording asks first; yes stops and saves the recording (doc/recorder-design.md §5.1)
  Future<AppExitResponse> _onExitRequested() async {
    var recorder = GetIt.I.get<RecorderService>();
    if (!recorder.isRecording) {
      return AppExitResponse.exit;
    }
    var stop = await showDialog<bool>(
        context: context,
        builder: (_) => SrxTheme(
            data: CustomTheme.srxTheme,
            child: SrxDialog.yesNo(bodyText: 'recorder.closeapp.confirm'.tr(args: [recorder.config?.name ?? '']))));
    if (stop != true) {
      return AppExitResponse.cancel;
    }
    await recorder.stop();
    return AppExitResponse.exit;
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
