import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/project/open_project_dialog.dart';
import 'package:mqttstudio/project/project_edit_dialog.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/project/project_viewmodel.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

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

  final ValueNotifier<bool> _isWebSiteHovering = ValueNotifier(false);
  final ValueNotifier<bool> _isEmailHovering = ValueNotifier(false);

  @override
  List<Widget> buildItems(BuildContext context) {
    var projectViewmodel = context.read<ProjectViewmodel>();
    return [
      Divider(),
      ListTile(
          onTap: () => _onNewProjectTap(projectViewmodel, context),
          leading: Icon(Icons.create_new_folder_outlined),
          title: Text('navigator.newproject_menuitem'.tr())),
      ListTile(
          onTap: () => _onOpenProjectTap(projectViewmodel, context),
          leading: Icon(Icons.folder_open),
          title: Text('navigator.openproject_menuitem'.tr())),
      ListTile(
          onTap: projectViewmodel.isProjectOpen ? () => _onsaveProjectTap(projectViewmodel, context) : null,
          leading: Icon(Icons.save),
          title: Text('navigator.saveproject_menuitem'.tr()),
          enabled: projectViewmodel.isProjectOpen),
      ListTile(
          onTap: projectViewmodel.isProjectOpen ? () => _onCloseProjectTap(projectViewmodel, context) : null,
          leading: Icon(Icons.close),
          title: Text('navigator.closeproject_menuitem'.tr()),
          enabled: projectViewmodel.isProjectOpen),
      Divider(),
      ListTile(
          onTap: () => _onProjectSettingsTap(context),
          leading: Icon(Icons.settings),
          title: Text('navigator.projectsettings_menuitem'.tr()),
          enabled: projectViewmodel.isProjectOpen),
      Divider(),
      FutureBuilder(
          future: PackageInfo.fromPlatform(),
          builder: (BuildContext context, AsyncSnapshot<PackageInfo> info) {
            return AboutListTile(
              icon: Icon(Icons.info),
              applicationIcon: Image.asset(
                './assets/icons/mqttstudio128.png',
                height: 64,
              ),
              applicationName: "MQTT Studio",
              applicationVersion: (info.data != null ? "v${info.data?.version}" : ""),
              applicationLegalese: 'copyright_text'.tr(),
              aboutBoxChildren: [
                SizedBox(height: 16),
                SizedBox(width: 600, child: Text('aboutdialog.marketing_text'.tr(), style: Theme.of(context).textTheme.bodyMedium)),
                SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.web, size: 20),
                    SizedBox(width: 6),
                    _buildWebSiteLink(),
                    SizedBox(width: 24),
                    Icon(Icons.email, size: 20),
                    SizedBox(width: 6),
                    _buildEmailLink(),
                  ],
                )
              ],
            );
          })
    ];
  }

  MouseRegion _buildWebSiteLink() {
    return MouseRegion(
      onEnter: (event) => _isWebSiteHovering.value = true,
      onExit: (event) => _isWebSiteHovering.value = false,
      child: ValueListenableBuilder(
        valueListenable: _isWebSiteHovering,
        builder: (context, isHovering, _) {
          return GestureDetector(
            onTap: _openWebSite,
            child: Text(
              'www.mqttstudio.com',
              style: isHovering as bool
                  ? Theme.of(context).textTheme.bodyMedium!.copyWith(decoration: TextDecoration.underline)
                  : Theme.of(context).textTheme.bodyMedium,
            ),
          );
        },
      ),
    );
  }

  MouseRegion _buildEmailLink() {
    return MouseRegion(
      onEnter: (event) => _isEmailHovering.value = true,
      onExit: (event) => _isEmailHovering.value = false,
      child: ValueListenableBuilder(
        valueListenable: _isEmailHovering,
        builder: (context, isHovering, _) {
          return GestureDetector(
            onTap: _openEmail,
            child: Text(
              'info@redpin.eu',
              style: isHovering as bool
                  ? Theme.of(context).textTheme.bodyMedium!.copyWith(decoration: TextDecoration.underline)
                  : Theme.of(context).textTheme.bodyMedium,
            ),
          );
        },
      ),
    );
  }

  void _onProjectSettingsTap(BuildContext context) async {
    GetIt.I.get<SrxNavigationService>().pop();
    var projectViewmodel = context.read<ProjectViewmodel>();
    Project? project = await showDialog(context: context, builder: (context) => ProjectEditDialog());
    if (project == null) {
      return;
    }

    projectViewmodel.openProject(project);
  }

  _onOpenProjectTap(ProjectViewmodel projectViewmodel, BuildContext context) async {
    if (await projectViewmodel.closeProject()) {
      GetIt.I.get<SrxNavigationService>().pop();
      await showDialog(context: context, builder: (context) => OpenProjectDialog());
    }
  }

  _onCloseProjectTap(ProjectViewmodel projectViewmodel, BuildContext context) async {
    if (await projectViewmodel.closeProject()) {
      GetIt.I.get<SrxNavigationService>().pop();
    }
  }

  _onsaveProjectTap(ProjectViewmodel projectViewmodel, BuildContext context) {
    projectViewmodel.saveProject();
    GetIt.I.get<SrxNavigationService>().pop();
  }

  _onNewProjectTap(ProjectViewmodel projectViewmodel, BuildContext context) async {
    if (await projectViewmodel.closeProject()) {
      _onProjectSettingsTap(context);
    }
  }

  void _openWebSite() {
    UrlLauncherPlatform.instance.launchUrl('https://www.mqttstudio.com', LaunchOptions());
  }

  void _openEmail() {
    UrlLauncherPlatform.instance.launchUrl('mailto://info@redpin.eu', LaunchOptions());
  }
}
