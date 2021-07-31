import 'package:flutter/material.dart';
import 'package:mqttstudio/viewmodel/project_global_viewmodel.dart';
import 'package:mqttstudio/dialogs/project_edit_dialog.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/viewmodel/mqtt_global_viewmodel.dart';
import 'package:mqttstudio/widgets/error_snackbar.dart';
import 'package:mqttstudio/widgets/navigation_drawer.dart';
import 'package:provider/provider.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

class HomePage extends StatelessWidget {
  const HomePage();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1,
      child: Consumer<ProjectGlobalViewmodel>(
        builder: (context, projectController, child) {
          return Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 250), child: Text(projectController.currentProject?.name ?? '<No project>')),
                  SizedBox(
                    width: 48,
                  ),
                  SizedBox(
                      width: 150,
                      child: TabBar(
                          labelPadding: EdgeInsets.symmetric(vertical: 6),
                          indicatorWeight: 3,
                          indicatorColor: Theme.of(context).primaryColorLight,
                          tabs: [
                            Text('TOPICS'),
                          ]))
                ],
              ),
              actions: [
                Consumer<MqttGlobalViewmodel>(builder: (context, viewmodel, child) {
                  viewmodel.onError = (message) => _onMqttConnectionError(message, context);
                  return _buildConnectButton(context);
                })
              ],
            ),
            drawer: NavigationDrawer(),
            body: Container(
              child: Center(
                  child: Column(
                children: [
                  Text(
                    'headline1',
                    style: Theme.of(context).textTheme.headline1,
                  ),
                  Text(
                    'headline2',
                    style: Theme.of(context).textTheme.headline2,
                  ),
                  Text(
                    'headline3',
                    style: Theme.of(context).textTheme.headline3,
                  ),
                  Text(
                    'headline4',
                    style: Theme.of(context).textTheme.headline4,
                  ),
                  Text(
                    'headline5',
                    style: Theme.of(context).textTheme.headline5,
                  ),
                  Text(
                    'headline6',
                    style: Theme.of(context).textTheme.headline6,
                  ),
                  Text(
                    'bodyText1',
                    style: Theme.of(context).textTheme.bodyText1,
                  ),
                  Text(
                    'bodyText2',
                    style: Theme.of(context).textTheme.bodyText2,
                  ),
                  Text(
                    'subtitle1',
                    style: Theme.of(context).textTheme.subtitle1,
                  ),
                  Text(
                    'subtitle2',
                    style: Theme.of(context).textTheme.subtitle2,
                  ),
                  Text(
                    'overline',
                    style: Theme.of(context).textTheme.overline,
                  ),
                ],
              )),
            ),
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
          primary:
              mqttGlobalViewmodel.isConnected() ? Theme.of(context).custom.connectedColor : Theme.of(context).custom.disconnectedColor),
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
        projectGlobalViewmodel.openProject(project);
      }

      mqttGlobalViewmodel.connect(projectGlobalViewmodel.currentProject!.mqttSettings);
    }
  }

  _onMqttConnectionError(String message, BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(errorSnackBar('mqtt.connecting.error'.tr() + ' ' + message, context));
  }
}
