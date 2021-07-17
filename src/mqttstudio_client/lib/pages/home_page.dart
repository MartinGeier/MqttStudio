import 'package:flutter/material.dart';
import 'package:mqttstudio/viewmodel/project_global_viewmodel.dart';
import 'package:mqttstudio/dialogs/project_edit_dialog.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/viewmodel/mqtt_global_viewmodel.dart';
import 'package:mqttstudio/widgets/navigation_drawer.dart';
import 'package:provider/provider.dart';
import 'package:mqttstudio/theme.dart';
import 'package:srx_flutter/srx_flutter.dart';

class HomePage extends StatelessWidget {
  const HomePage();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1,
      child: Consumer<ProjectGlobalViewmodel>(
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
                Consumer<MqttGlobalViewmodel>(builder: (context, viewmodel, child) {
                  return _buildConnectButton(context);
                })
              ],
            ),
            drawer: NavigationDrawer(),
            body: Container(),
          );
        },
      ),
    );
  }

  ElevatedButton _buildConnectButton(BuildContext context) {
    var mqttGlobalViewmodel = context.read<MqttGlobalViewmodel>();
    return ElevatedButton(
      onPressed: () => _onConnectionTap(context),
      child: SizedBox(
        width: 150,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          mqttGlobalViewmodel.isBusy
              ? Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: SrxLoadingIndicatorWidget(color: Colors.white),
                  ),
                )
              : Icon(mqttGlobalViewmodel.isConnected() ? Icons.power : Icons.power_off),
          SizedBox(
            width: 4,
          ),
          mqttGlobalViewmodel.isConnected() ? Text('DISCONNECT') : Text('CONNECT')
        ]),
      ),
      style: ElevatedButton.styleFrom(
          primary: mqttGlobalViewmodel.isConnected() ? Theme.of(context).custom.connectedColor : Theme.of(context).accentColor),
    );
  }

  _onConnectionTap(BuildContext context) async {
    var mqttGlobalViewmodel = context.read<MqttGlobalViewmodel>();
    if (mqttGlobalViewmodel.isConnected()) {
      mqttGlobalViewmodel.disconnect();
    } else {
      var projectGlobalViewmodel = context.read<ProjectGlobalViewmodel>();
      if (!projectGlobalViewmodel.isProjectOpen) {
        Project? project = await showDialog(context: context, builder: (context) => ProjectEditDialog());
        if (project == null) {
          return;
        }
        projectGlobalViewmodel.currentProject = project;
      }

      mqttGlobalViewmodel.connect(projectGlobalViewmodel.currentProject!.mqttHostname, projectGlobalViewmodel.currentProject!.clientId);
    }
  }
}
