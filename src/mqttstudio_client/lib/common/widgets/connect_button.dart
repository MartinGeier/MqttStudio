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

// The app bar button that connects to and disconnects from the broker. Its color and icon show the state (red and
// power_off while disconnected, green and power while connected), its label names what a click does.
class ConnectButton extends StatelessWidget {
  const ConnectButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<MqttConnectionViewmodel>(builder: (context, mqttConnectionViewmodel, child) {
      mqttConnectionViewmodel.onError = (message) => _onMqttConnectionError(message, context);
      mqttConnectionViewmodel.onBrokerDisconnected = (reason) => _showError('mqtt.brokerdisconnected.error'.tr(args: [reason]), context);
      mqttConnectionViewmodel.onSubscribeFailed = (topic, reason) => _showError(
          reason == null
              ? 'mqtt.subscribefailed.error'.tr(args: [topic])
              : 'mqtt.subscribefailedreason.error'.tr(args: [topic, reason]),
          context);
      return _buildConnectButton(context);
    });
  }

  Widget _buildConnectButton(BuildContext context) {
    var mqttConnectionViewmodel = context.read<MqttConnectionViewmodel>();
    var colors = Theme.of(context).custom;
    return Tooltip(
      message: _tooltip(context, mqttConnectionViewmodel),
      child: ElevatedButton(
        // nothing can be done while a connection attempt runs, but the button keeps its look
        onPressed: mqttConnectionViewmodel.isBusy ? null : () => _onConnectionTap(context),
        style: ElevatedButton.styleFrom(
            backgroundColor: mqttConnectionViewmodel.isConnected() ? colors.connectedColor : colors.disconnectedColor,
            disabledBackgroundColor: colors.disconnectedColor,
            disabledForegroundColor: Theme.of(context).colorScheme.onPrimary),
        child: SizedBox(
          width: 150,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _buildIcon(mqttConnectionViewmodel),
            SizedBox(width: 4),
            Text(_label(mqttConnectionViewmodel)),
          ]),
        ),
      ),
    );
  }

  Widget _buildIcon(MqttConnectionViewmodel mqttConnectionViewmodel) {
    if (mqttConnectionViewmodel.isBusy) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: SizedBox(width: 28, height: 28, child: SrxLoadingIndicatorWidget(color: Colors.white)),
      );
    }
    return Icon(mqttConnectionViewmodel.isConnected() ? Icons.power : Icons.power_off);
  }

  String _label(MqttConnectionViewmodel mqttConnectionViewmodel) {
    if (mqttConnectionViewmodel.isBusy) {
      return 'connectbutton.connecting.label'.tr();
    }
    return mqttConnectionViewmodel.isConnected() ? 'connectbutton.disconnect.label'.tr() : 'connectbutton.connect.label'.tr();
  }

  String _tooltip(BuildContext context, MqttConnectionViewmodel mqttConnectionViewmodel) {
    var mqttSettings = context.watch<ProjectViewmodel>().currentProject?.mqttSettings;
    if (mqttSettings == null) {
      return 'connectbutton.newproject.tooltip'.tr();
    }
    var broker = '${mqttSettings.hostname}:${mqttSettings.port}';
    if (mqttConnectionViewmodel.isBusy) {
      return 'connectbutton.connecting.tooltip'.tr(args: [broker]);
    }
    return mqttConnectionViewmodel.isConnected()
        ? 'connectbutton.disconnect.tooltip'.tr(args: [broker])
        : 'connectbutton.connect.tooltip'.tr(args: [broker]);
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
        if (!await projectViewmodel.openProject(project)) {
          return;
        }
      }

      mqttConnectionViewmodel.connect(projectViewmodel.currentProject!.mqttSettings);
    }
  }

  _onMqttConnectionError(String message, BuildContext context) {
    _showError('mqtt.connecting.error'.tr() + ' ' + message, context);
  }

  _showError(String message, BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(message, context));
  }
}
