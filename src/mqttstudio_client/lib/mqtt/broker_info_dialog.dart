import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/broker_info.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Shows what the broker reported when it accepted the connection
class BrokerInfoDialog extends StatelessWidget {
  final BrokerInfo brokerInfo;

  const BrokerInfoDialog({Key? key, required this.brokerInfo}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(title: Text('brokerinfodialog.title'.tr()), contentPadding: EdgeInsets.all(16), children: [
      ConstrainedBox(
        constraints: BoxConstraints(minWidth: 480, maxWidth: 480),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Table(
              columnWidths: {0: FixedColumnWidth(220), 1: FlexColumnWidth()},
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: _buildRows(context)),
          SizedBox(height: 16),
          SrxFormRow(alignment: CrossAxisAlignment.center, children: [
            Spacer(flex: 2),
            Expanded(
                child: ElevatedButton(
                    autofocus: true,
                    onPressed: () => GetIt.I.get<SrxNavigationService>().pop(),
                    child: Text('srx.common.ok'.tr()))),
          ]),
        ]),
      )
    ]);
  }

  List<TableRow> _buildRows(BuildContext context) {
    var info = brokerInfo;
    return [
      _buildRow(context, 'brokerinfodialog.protocol.label', info.protocolVersion.displayName),
      if (info.reasonCode != null) _buildRow(context, 'brokerinfodialog.reasoncode.label', info.reasonCode!),
      if (_hasText(info.reasonString)) _buildRow(context, 'brokerinfodialog.reasonstring.label', info.reasonString!),
      if (info.sessionPresent != null)
        _buildRow(context, 'brokerinfodialog.sessionpresent.label', _yesNo(info.sessionPresent!)),
      if (info.sessionExpiryInterval != null && info.sessionExpiryInterval! > 0)
        _buildRow(context, 'brokerinfodialog.sessionexpiry.label', '${info.sessionExpiryInterval} s'),
      if (_hasText(info.assignedClientIdentifier))
        _buildRow(context, 'brokerinfodialog.assignedclientid.label', info.assignedClientIdentifier!),
      if (info.maximumQos != null && info.maximumQos! < 3)
        _buildRow(context, 'brokerinfodialog.maximumqos.label', MqttQos.values[info.maximumQos!].toString().tr()),
      if (info.retainAvailable != null)
        _buildRow(context, 'brokerinfodialog.retainavailable.label', _yesNo(info.retainAvailable!)),
      if (info.maximumPacketSize != null && info.maximumPacketSize! > 0)
        _buildRow(context, 'brokerinfodialog.maximumpacketsize.label', '${info.maximumPacketSize} B'),
      if (info.receiveMaximum != null)
        _buildRow(context, 'brokerinfodialog.receivemaximum.label', info.receiveMaximum.toString()),
      if (info.topicAliasMaximum != null)
        _buildRow(context, 'brokerinfodialog.topicaliasmaximum.label', info.topicAliasMaximum.toString()),
      if (info.serverKeepAlive != null && info.serverKeepAlive! > 0)
        _buildRow(context, 'brokerinfodialog.serverkeepalive.label', '${info.serverKeepAlive} s'),
      if (info.wildcardSubscriptionsAvailable != null)
        _buildRow(context, 'brokerinfodialog.wildcardsubscriptions.label', _yesNo(info.wildcardSubscriptionsAvailable!)),
      if (info.subscriptionIdentifiersAvailable != null)
        _buildRow(
            context, 'brokerinfodialog.subscriptionidentifiers.label', _yesNo(info.subscriptionIdentifiersAvailable!)),
      if (info.sharedSubscriptionsAvailable != null)
        _buildRow(context, 'brokerinfodialog.sharedsubscriptions.label', _yesNo(info.sharedSubscriptionsAvailable!)),
      if (_hasText(info.responseInformation))
        _buildRow(context, 'brokerinfodialog.responseinformation.label', info.responseInformation!),
      if (_hasText(info.serverReference))
        _buildRow(context, 'brokerinfodialog.serverreference.label', info.serverReference!),
      for (var userProperty in info.userProperties) _buildRow(context, null, userProperty.value, name: userProperty.key),
    ];
  }

  TableRow _buildRow(BuildContext context, String? labelKey, String value, {String? name}) {
    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6, right: 12),
        child: Text(name ?? labelKey!.tr(), style: Theme.of(context).textTheme.titleSmall),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: SelectableText(value, style: Theme.of(context).textTheme.bodyMedium),
      ),
    ]);
  }

  static bool _hasText(String? value) => value != null && value.isNotEmpty;

  static String _yesNo(bool value) => value ? 'brokerinfodialog.yes'.tr() : 'brokerinfodialog.no'.tr();
}
