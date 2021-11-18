import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/project/open_project_dialog.dart';
import 'package:mqttstudio/project/project_edit_dialog.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:provider/provider.dart';

import '../localstore.dart';

class NavigationDrawer extends SrxNavigationDrawerWidget {
  NavigationDrawer()
      : super(
            showLogout: false,
            copyrightText: 'Copyright (c) by Redpin',
            developedByText: 'www.redpin.eu',
            developedByUrl: 'http://www.redpin.eu',
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
          title: Text('New Project')),
      ListTile(
          onTap: () => _onOpenProjectTap(projectGlobalViewmodel, context), leading: Icon(Icons.folder_open), title: Text('Open Project')),
      ListTile(
          onTap: projectGlobalViewmodel.isProjectOpen ? () => _onsaveProjectTap(projectGlobalViewmodel, context) : null,
          leading: Icon(Icons.save),
          title: Text('Save Project'),
          enabled: projectGlobalViewmodel.isProjectOpen),
      ListTile(
          onTap: projectGlobalViewmodel.isProjectOpen ? () => _onCloseProjectTap(projectGlobalViewmodel, context) : null,
          leading: Icon(Icons.close),
          title: Text('Close Project'),
          enabled: projectGlobalViewmodel.isProjectOpen),
      Divider(),
      ListTile(
          onTap: () => _onProjectSettingsTap(context),
          leading: Icon(Icons.settings),
          title: Text('Project Settings'),
          enabled: projectGlobalViewmodel.isProjectOpen),
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
    GetIt.I.get<SrxNavigationService>().pop();
    await showDialog(context: context, builder: (context) => OpenProjectDialog());
  }

  _onCloseProjectTap(ProjectGlobalViewmodel projectGlobalViewmodel, BuildContext context) async {
    if (projectGlobalViewmodel.currentProject?.lastUsed == null) {
      if (!(await showDialog<bool>(
              context: context, builder: (context) => SrxDialogs.srxConfirmDialog('Project has not been saved! Continue?', context)) ??
          false)) {
        GetIt.I.get<SrxNavigationService>().pop();
        return;
      }
    }

    GetIt.I.get<SrxNavigationService>().pop();
    projectGlobalViewmodel.closeProject();
  }

  _onsaveProjectTap(ProjectGlobalViewmodel projectGlobalViewmodel, BuildContext context) {
    LocalStore().saveProject(projectGlobalViewmodel.currentProject!);
    GetIt.I.get<SrxNavigationService>().pop();
  }

  _onNewProjectTap(ProjectGlobalViewmodel projectGlobalViewmodel, BuildContext context) {
    projectGlobalViewmodel.closeProject();
    _onProjectSettingsTap(context);
  }
}
