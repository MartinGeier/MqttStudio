import 'package:flutter/material.dart';
import 'package:mqttstudio/viewmodel/project_global_viewmodel.dart';
import 'package:mqttstudio/widgets/connect_button.dart';
import 'package:mqttstudio/widgets/navigation_drawer.dart';
import 'package:mqttstudio/widgets/topic_subscription_panel.dart';
import 'package:provider/provider.dart';

class HomePage extends StatelessWidget {
  const HomePage();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Consumer<ProjectGlobalViewmodel>(
        builder: (context, projectController, child) {
          return Scaffold(
            appBar: AppBar(
              leadingWidth: 24,
              title: Row(
                children: [
                  ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 250), child: Text(projectController.currentProject?.name ?? '<No project>')),
                  SizedBox(
                    width: 48,
                  ),
                  Expanded(
                    child: TabBar(
                        isScrollable: true,
                        labelPadding: EdgeInsets.symmetric(vertical: 6),
                        indicatorWeight: 3,
                        indicatorColor: Theme.of(context).primaryColorLight,
                        tabs: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 36),
                            child: Text('TOPICS'),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 48),
                            child: Text('SIMULATOR'),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 48),
                            child: Text('RECORDER'),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 48),
                            child: Text('DOCUMENTATION'),
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
                  Divider(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
