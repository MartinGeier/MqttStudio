import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/contoller/project_controller.dart';
import 'package:mqttstudio/dialogs/project_edit_dialog.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/viewmodel/mqtt_master_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:mqttstudio/theme.dart';

class HomePage extends StatelessWidget {
  const HomePage();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: GetIt.I.get<MqttMasterViewmodel>(),
      child: DefaultTabController(
        length: 1,
        child: ChangeNotifierProvider.value(
          value: GetIt.I.get<ProjectController>(),
          child: Consumer<ProjectController>(
            builder: (context, projectControler, child) {
              return Scaffold(
                appBar: AppBar(
                  title: Row(
                    children: [
                      ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 250), child: Text(projectControler.currentProject?.name ?? '<No project>')),
                      SizedBox(
                        width: 48,
                      ),
                      SizedBox(
                          width: 150,
                          child: TabBar(labelPadding: EdgeInsets.symmetric(vertical: 6), indicatorWeight: 3, tabs: [
                            Text('TOPICS'),
                          ]))
                    ],
                  ),
                  actions: [
                    Consumer<MqttMasterViewmodel>(builder: (context, viewmodel, child) {
                      return ElevatedButton(
                        onPressed: () => _onConnectionTap(viewmodel, context),
                        child: SizedBox(
                          width: 150,
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(viewmodel.isConnected() ? Icons.power : Icons.power_off),
                            SizedBox(
                              width: 4,
                            ),
                            viewmodel.isConnected() ? Text('DISCONNECT') : Text('CONNECT')
                          ]),
                        ),
                        style: ElevatedButton.styleFrom(
                            primary: viewmodel.isConnected() ? Theme.of(context).custom.connectedColor : Theme.of(context).accentColor),
                      );
                    })
                  ],
                ),
                body: Container(),
              );
            },
          ),
        ),
      ),
    );
  }

  _onConnectionTap(MqttMasterViewmodel viewmodel, BuildContext context) async {
    if (viewmodel.isConnected()) {
      viewmodel.disconnect();
    } else {
      var projectController = GetIt.I.get<ProjectController>();
      if (!projectController.isProjectOpen) {
        Project? project = await showDialog(context: context, builder: (context) => ProjectEditDialog());
        if (project == null) {
          return;
        }
        projectController.currentProject = project;
      }
      viewmodel.hostname = projectController.currentProject!.mqttHostname;
      viewmodel.clientId = projectController.currentProject!.clientId;
      viewmodel.connect();
    }
  }
}
