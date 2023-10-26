import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:mqttstudio/common/widgets/connect_button.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

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
  late TutorialCoachMark tutorialCoachMark;

  @override
  void initState() {
    createTutorial();
    super.initState();
    Future.delayed(Duration(seconds: 1), showTutorial);
  }

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

  void createTutorial() {
    tutorialCoachMark = TutorialCoachMark(
      targets: _createTargets(),
      colorShadow: Colors.grey,
      paddingFocus: 0,
      opacityShadow: 0.5,
      hideSkip: true,
      imageFilter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
    );
  }

  List<TargetFocus> _createTargets() {
    List<TargetFocus> targets = [];
    targets.add(
      TargetFocus(
        keyTarget: coachKey,
        enableOverlayTab: true,
        contents: [
          TargetContent(
              padding: EdgeInsets.only(top: 110, right: 24),
              align: ContentAlign.bottom,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.arrow_circle_right, size: 32),
                  SizedBox(width: 6),
                  Text('connectbutton.coach.caption'.tr(), style: TextStyle(fontSize: 20, fontStyle: FontStyle.italic)),
                ],
              )),
        ],
      ),
    );

    return targets;
  }

  Future showTutorial() async {
    if (!await LocalStore().getCoachingCompleted()) {
      tutorialCoachMark.show(context: context);
      await LocalStore().saveCoachingCompleted(true);
    }
  }
}
