import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/mqtt/broker_info_dialog.dart';
import 'package:mqttstudio/mqtt/mqtt_connection_viewmodel.dart';
import 'package:provider/provider.dart';

// App bar button next to the ConnectButton that shows what the connected broker reported
class BrokerInfoButton extends StatelessWidget {
  const BrokerInfoButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<MqttConnectionViewmodel>(builder: (context, viewmodel, child) {
      var brokerInfo = viewmodel.isConnected() ? viewmodel.brokerInfo : null;
      return IconButton(
        tooltip: 'brokerinfobutton.tooltip'.tr(),
        icon: Icon(Icons.dns),
        onPressed: brokerInfo == null
            ? null
            : () => showDialog(context: context, builder: (context) => BrokerInfoDialog(brokerInfo: brokerInfo)),
      );
    });
  }
}
