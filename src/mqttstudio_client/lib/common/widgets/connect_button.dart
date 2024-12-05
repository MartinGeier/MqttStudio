import 'package:flutter/material.dart';
import 'package:mqttstudio/mqtt/mqtt_connection_viewmodel.dart';
import 'package:mqttstudio/project/project_edit_dialog.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/project/project_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:mqttstudio/common/widgets/error_snackbar.dart';
import 'package:mqttstudio/custom_theme.dart';

class ConnectButton extends StatelessWidget {
  const ConnectButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<MqttConnectionViewmodel>(builder: (context, mqttConnectionViewmodel, child) {
      mqttConnectionViewmodel.onError = (message) => _onMqttConnectionError(message, context);
      return _buildConnectButton(context);
    });
  }

  ElevatedButton _buildConnectButton(BuildContext context) {
    var mqttConnectionViewmodel = context.read<MqttConnectionViewmodel>();
    return ElevatedButton(
      onPressed: () => _onConnectionTap(context),
      child: SizedBox(
        width: 150,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          mqttConnectionViewmodel.isBusy
              ? Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: SrxLoadingIndicatorWidget(color: Colors.white),
                  ),
                )
              : Icon(mqttConnectionViewmodel.isConnected() ? Icons.power : Icons.power_off),
          SizedBox(
            width: 4,
          ),
          mqttConnectionViewmodel.isConnected() ? Text('CONNECTED') : Text('DISCONNECTED')
        ]),
      ),
      style: ElevatedButton.styleFrom(
          backgroundColor:
              mqttConnectionViewmodel.isConnected() ? Theme.of(context).custom.connectedColor : Theme.of(context).custom.disconnectedColor),
    );
  }

  _onConnectionTap(BuildContext context) async {
    var mqttConnectionViewmodel = context.read<MqttConnectionViewmodel>();
    if (mqttConnectionViewmodel.isConnected()) {
      mqttConnectionViewmodel.disconnect();
    } else {
      var projectViewmodel = context.read<ProjectViewmodel>();
      if (!projectViewmodel.isProjectOpen) {
        Project? project = await showDialog(context: context, builder: (context) => ProjectEditDialog());
        if (project == null) {
          return;
        }
        await projectViewmodel.openProject(project);
      }

      mqttConnectionViewmodel.connect(projectViewmodel.currentProject!.mqttSettings);
    }
  }

  _onMqttConnectionError(String message, BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(errorSnackBar('mqtt.connecting.error'.tr() + ' ' + message, context));
  }
}
