import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/mqtt/mqtt_connection_viewmodel.dart';
import 'package:mqttstudio/project/open_project_dialog.dart';
import 'package:mqttstudio/project/project_edit_dialog.dart';
import 'package:mqttstudio/project/project_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';

// The project commands of the navigation drawer and the menu bar. They show their dialogs on the navigator's context,
// which stays mounted while the drawer that started a command closes.
BuildContext get _context => GetIt.I.get<SrxNavigationService>().navigatorKey.currentContext!;

ProjectViewmodel get _projectViewmodel => _context.read<ProjectViewmodel>();

Future newProject() async {
  if (await _projectViewmodel.closeProject()) {
    await editProjectSettings();
  }
}

Future openProject() async {
  if (await _projectViewmodel.closeProject()) {
    await showDialog(context: _context, builder: (context) => OpenProjectDialog());
  }
}

Future saveProject() async {
  await _projectViewmodel.saveProject();
}

Future closeProject() async {
  await _projectViewmodel.closeProject();
}

// edits the open project, or creates one when none is open
Future editProjectSettings() async {
  var mqttConnectionViewmodel = _context.read<MqttConnectionViewmodel>();
  // reopening the project closes the connection, so reconnect with the new settings if it was connected
  var wasConnected = mqttConnectionViewmodel.isConnected();
  var project = await editAndOpenProject(_context);
  if (project != null && wasConnected) {
    await mqttConnectionViewmodel.connect(project.mqttSettings);
  }
}
