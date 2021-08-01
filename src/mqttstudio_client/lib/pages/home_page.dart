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
                  Center(
                      child: Column(
                    children: [
                      Text(
                        'headline1',
                        style: Theme.of(context).textTheme.headline1,
                      ),
                      Text(
                        'headline2',
                        style: Theme.of(context).textTheme.headline2,
                      ),
                      Text(
                        'headline3',
                        style: Theme.of(context).textTheme.headline3,
                      ),
                      Text(
                        'headline4',
                        style: Theme.of(context).textTheme.headline4,
                      ),
                      Text(
                        'headline5',
                        style: Theme.of(context).textTheme.headline5,
                      ),
                      Text(
                        'headline6',
                        style: Theme.of(context).textTheme.headline6,
                      ),
                      Text(
                        'bodyText1',
                        style: Theme.of(context).textTheme.bodyText1,
                      ),
                      Text(
                        'bodyText2',
                        style: Theme.of(context).textTheme.bodyText2,
                      ),
                      Text(
                        'subtitle1',
                        style: Theme.of(context).textTheme.subtitle1,
                      ),
                      Text(
                        'subtitle2',
                        style: Theme.of(context).textTheme.subtitle2,
                      ),
                      Text(
                        'overline',
                        style: Theme.of(context).textTheme.overline,
                      ),
                    ],
                  )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
