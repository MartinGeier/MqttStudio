import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/dialogs/project_edit_dialog.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/viewmodel/project_global_viewmodel.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:provider/provider.dart';

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
    return [
      Divider(),
      ListTile(onTap: () => _onProjectSettingsTap(context), leading: Icon(Icons.settings_ethernet), title: Text('Project Settings'))
    ];
  }

  void _onProjectSettingsTap(BuildContext context) async {
    GetIt.I.get<SrxNavigationService>().pop();
    var projectGlobalViewmodel = context.read<ProjectGlobalViewmodel>();
    Project? project = await showDialog(context: context, builder: (context) => ProjectEditDialog());
    if (project == null) {
      return;
    }

    projectGlobalViewmodel.currentProject = project;
  }
}
