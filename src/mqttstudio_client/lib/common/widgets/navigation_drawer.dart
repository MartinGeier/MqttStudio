import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/project/open_project_dialog.dart';
import 'package:mqttstudio/project/project_edit_dialog.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
    var projectGlobalViewmodel = GetIt.I.get<ProjectGlobalViewmodel>();
    return [
      Divider(),
      ListTile(
          onTap: () => _onNewProjectTap(projectGlobalViewmodel, context),
          leading: Icon(Icons.create_new_folder_outlined),
          title: Text('navigator.newproject_menuitem'.tr())),
      ListTile(
          onTap: () => _onOpenProjectTap(projectGlobalViewmodel, context),
          leading: Icon(Icons.folder_open),
          title: Text('navigator.openproject_menuitem'.tr())),
      ListTile(
          onTap: projectGlobalViewmodel.isProjectOpen ? () => _onsaveProjectTap(projectGlobalViewmodel, context) : null,
          leading: Icon(Icons.save),
          title: Text('navigator.saveproject_menuitem'.tr()),
          enabled: projectGlobalViewmodel.isProjectOpen),
      ListTile(
          onTap: projectGlobalViewmodel.isProjectOpen ? () => _onCloseProjectTap(projectGlobalViewmodel, context) : null,
          leading: Icon(Icons.close),
          title: Text('navigator.closeproject_menuitem'.tr()),
          enabled: projectGlobalViewmodel.isProjectOpen),
      Divider(),
      ListTile(
          onTap: () => _onProjectSettingsTap(context),
          leading: Icon(Icons.settings),
          title: Text('navigator.projectsettings_menuitem'.tr()),
          enabled: projectGlobalViewmodel.isProjectOpen),
      Divider(),
      FutureBuilder(
          future: PackageInfo.fromPlatform(),
          builder: (BuildContext context, AsyncSnapshot<PackageInfo> info) {
            return AboutListTile(
              icon: Icon(Icons.info),
              applicationIcon: Image.asset(
                './assets/icons/mqttstudio.png',
                height: 64,
              ),
              applicationName: "MQTT Studio",
              applicationVersion: (info.data != null ? "v${info.data?.version}" : ""),
              applicationLegalese: 'copyright_text'.tr(),
              aboutBoxChildren: [
                SizedBox(height: 16),
                Text('aboutdialog.marketing_text'.tr(), style: Theme.of(context).textTheme.bodyMedium)
              ],
            );
          })
    ];
  }

  void _onProjectSettingsTap(BuildContext context) async {
    GetIt.I.get<SrxNavigationService>().pop();
    var projectGlobalViewmodel = context.read<ProjectGlobalViewmodel>();
    Project? project = await showDialog(context: context, builder: (context) => ProjectEditDialog());
    if (project == null) {
      return;
    }

    projectGlobalViewmodel.openProject(project);
  }

  _onOpenProjectTap(ProjectGlobalViewmodel projectGlobalViewmodel, BuildContext context) async {
    if (await projectGlobalViewmodel.closeProject()) {
      GetIt.I.get<SrxNavigationService>().pop();
      await showDialog(context: context, builder: (context) => OpenProjectDialog());
    }
  }

  _onCloseProjectTap(ProjectGlobalViewmodel projectGlobalViewmodel, BuildContext context) async {
    if (await projectGlobalViewmodel.closeProject()) {
      GetIt.I.get<SrxNavigationService>().pop();
    }
  }

  _onsaveProjectTap(ProjectGlobalViewmodel projectGlobalViewmodel, BuildContext context) {
    projectGlobalViewmodel.saveProject();
    GetIt.I.get<SrxNavigationService>().pop();
  }

  _onNewProjectTap(ProjectGlobalViewmodel projectGlobalViewmodel, BuildContext context) async {
    if (await projectGlobalViewmodel.closeProject()) {
      _onProjectSettingsTap(context);
    }
  }
}
