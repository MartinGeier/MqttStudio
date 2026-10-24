import 'package:flutter/material.dart';
import 'package:mqttstudio/common/widgets/broker_info_button.dart';
import 'package:mqttstudio/common/widgets/connect_button.dart';
import 'package:mqttstudio/project/project_viewmodel.dart';
import 'package:mqttstudio/recorder/widgets/rec_indicator.dart';
import 'package:easy_localization/easy_localization.dart';

class MainAppBar extends StatefulWidget implements PreferredSizeWidget {
  static const int topicViewerTab = 0;
  static const int simulatorTab = 1;
  static const int recorderTab = 2;
  static const int documentationTab = 3;

  final ProjectViewmodel viewmodel;

  MainAppBar({required this.viewmodel, Key? key}) : super(key: key);
  @override
  State<MainAppBar> createState() => _MainAppBarState();

  @override
  Size get preferredSize => AppBar().preferredSize;
}

class _MainAppBarState extends State<MainAppBar> {
  final GlobalKey coachKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leadingWidth: 24,
      title: Row(
        children: [
          ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 250),
              child: Text(widget.viewmodel.currentProject?.name ?? 'topicviewerpage.noproject.label'.tr())),
          SizedBox(
            width: 48,
          ),
          Expanded(
            child: TabBar(
                isScrollable: true,
                labelPadding: EdgeInsets.symmetric(vertical: 6),
                indicatorWeight: 3,
                // the app bar is primary, so the indicator of the selected tab uses the color of its text
                indicatorColor: Theme.of(context).colorScheme.onPrimary,
                tabs: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Text('topicviewerpage.menuitem.topicviewer'.tr()),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Text('topicviewerpage.menuitem.simulator'.tr()),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Text('topicviewerpage.menuitem.recorder'.tr()),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Text('topicviewerpage.menuitem.documentation'.tr()),
                  ),
                ]),
          )
        ],
      ),
      actions: [
        RecIndicator(recorderTab: MainAppBar.recorderTab),
        BrokerInfoButton(),
        SizedBox(width: 6),
        ConnectButton(key: coachKey)
      ],
    );
  }
}
