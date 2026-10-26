import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/mqtt/broker_stats_dialog.dart';
import 'package:mqttstudio/mqtt/mqtt_connection_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';

// App bar button next to the BrokerInfoButton that shows the broker's $SYS statistics
class BrokerStatsButton extends StatelessWidget {
  const BrokerStatsButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<MqttConnectionViewmodel>(builder: (context, viewmodel, child) {
      return IconButton(
        tooltip: 'brokerstatsbutton.tooltip'.tr(),
        icon: Icon(Icons.monitor_heart_outlined),
        onPressed: viewmodel.isConnected()
            ? () => showDialog(
                context: context, builder: (_) => SrxTheme(data: CustomTheme.srxTheme, child: BrokerStatsDialog()))
            : null,
      );
    });
  }
}
