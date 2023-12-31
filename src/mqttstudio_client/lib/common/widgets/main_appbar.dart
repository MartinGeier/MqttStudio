import 'package:flutter/material.dart';
import 'package:mqttstudio/common/widgets/connect_button.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:easy_localization/easy_localization.dart';

class MainAppBar extends StatefulWidget implements PreferredSizeWidget {
  final ProjectGlobalViewmodel viewmodel;

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
                indicatorColor: Theme.of(context).colorScheme.primary,
                tabs: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Text('topicviewerpage.menuitem.topicviewer'.tr()),
                  ),
                  Visibility(
                    visible: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Text('topicviewerpage.menuitem.simulator'.tr()),
                    ),
                  ),
                  Visibility(
                    visible: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Text('topicviewerpage.menuitem.recorder'.tr()),
                    ),
                  ),
                  Visibility(
                    visible: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Text('topicviewerpage.menuitem.documentation'.tr()),
                    ),
                  ),
                ]),
          )
        ],
      ),
      actions: [ConnectButton(key: coachKey)],
    );
  }
}
