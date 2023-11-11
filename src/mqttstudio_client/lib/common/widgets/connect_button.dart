import 'package:flutter/material.dart';
import 'package:mqttstudio/project/project_edit_dialog.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/mqtt/mqtt_global_viewmodel.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:mqttstudio/common/widgets/error_snackbar.dart';
import 'package:mqttstudio/custom_theme.dart';

class ConnectButton extends StatelessWidget {
  const ConnectButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<MqttGlobalViewmodel>(builder: (context, viewmodel, child) {
      viewmodel.onError = (message) => _onMqttConnectionError(message, context);
      return _buildConnectButton(context);
    });
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
          mqttGlobalViewmodel.isConnected() ? Text("connectbutton.connected.label".tr()) : Text('connectbutton.disconnected.label'.tr())
        ]),
      ),
      style: ElevatedButton.styleFrom(
          backgroundColor:
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
        await projectGlobalViewmodel.openProject(project);
      }

      mqttGlobalViewmodel.connect(projectGlobalViewmodel.currentProject!.mqttSettings);
    }
  }

  _onMqttConnectionError(String message, BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(errorSnackBar('mqtt.connecting.error'.tr() + ' ' + message, context));
  }
}
