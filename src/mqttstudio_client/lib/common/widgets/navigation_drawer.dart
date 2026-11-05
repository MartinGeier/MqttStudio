import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/about_mqttstudio.dart';
import 'package:mqttstudio/project/project_commands.dart';
import 'package:mqttstudio/project/project_viewmodel.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:provider/provider.dart';

class NavigationDrawer extends SrxNavigationDrawer {
  NavigationDrawer()
      : super(
            showLogout: false,
            copyrightText: 'copyright_text'.tr(),
            developedByText: 'www.mqttstudio.com',
            developedByUrl: 'https://www.mqttstudio.com',
            logoUrl: "https://www.mqttstudio.com",
            logo: Image.asset(
              './assets/images/logo.png',
            ));

  @override
  List<Widget> buildItems(BuildContext context) {
    var projectViewmodel = context.read<ProjectViewmodel>();
    return [
      Divider(),
      ListTile(
          onTap: () => _closeAndRun(newProject),
          leading: Icon(Icons.create_new_folder_outlined),
          title: Text('navigator.newproject_menuitem'.tr())),
      ListTile(
          onTap: () => _closeAndRun(openProject),
          leading: Icon(Icons.folder_open),
          title: Text('navigator.openproject_menuitem'.tr())),
      ListTile(
          onTap: projectViewmodel.isProjectOpen ? () => _closeAndRun(saveProject) : null,
          leading: Icon(Icons.save),
          title: Text('navigator.saveproject_menuitem'.tr()),
          enabled: projectViewmodel.isProjectOpen),
      ListTile(
          onTap: projectViewmodel.isProjectOpen ? () => _closeAndRun(closeProject) : null,
          leading: Icon(Icons.close),
          title: Text('navigator.closeproject_menuitem'.tr()),
          enabled: projectViewmodel.isProjectOpen),
      Divider(),
      ListTile(
          onTap: () => _closeAndRun(editProjectSettings),
          leading: Icon(Icons.settings),
          title: Text('navigator.projectsettings_menuitem'.tr()),
          enabled: projectViewmodel.isProjectOpen),
      Divider(),
      ListTile(
          onTap: () => _closeAndRun(showAboutMqttStudio),
          leading: Icon(Icons.info),
          title: Text('navigator.about_menuitem'.tr())),
    ];
  }

  // the commands show their dialogs on the navigator, so the drawer can close first
  Future _closeAndRun(Future Function() command) async {
    await GetIt.I.get<SrxNavigationService>().pop();
    await command();
  }
}
