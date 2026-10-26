import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/payload_diff_view.dart';
import 'package:mqttstudio/mqtt/broker_stats_viewmodel.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/mqtt/sys_monitor.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';

// The broker's statistics from its $SYS topics: a summary of the well-known ones and all topics with their values,
// updated while the dialog is open
class BrokerStatsDialog extends StatefulWidget {
  // replaces the broker connection in tests
  final MqttAdapter Function()? connectionFactory;

  const BrokerStatsDialog({Key? key, this.connectionFactory}) : super(key: key);

  @override
  State<BrokerStatsDialog> createState() => _BrokerStatsDialogState();
}

class _BrokerStatsDialogState extends State<BrokerStatsDialog> {
  late final BrokerStatsViewmodel _viewmodel = BrokerStatsViewmodel(connectionFactory: widget.connectionFactory);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async => await _viewmodel.start());
  }

  @override
  void dispose() {
    _viewmodel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<BrokerStatsViewmodel>.value(
      value: _viewmodel,
      child: Consumer<BrokerStatsViewmodel>(builder: (context, vm, child) {
        return SimpleDialog(title: Text('brokerstatsdialog.title'.tr()), contentPadding: EdgeInsets.all(16), children: [
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: 720, maxWidth: 720),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildStatus(context, vm),
              if (vm.summary.isNotEmpty) ...[
                SizedBox(height: 12),
                _buildSummary(context, vm),
              ],
              SizedBox(height: 24),
              _buildTopicsHeader(context, vm),
              SizedBox(height: 8),
              SizedBox(height: 280, child: _buildTopics(context, vm)),
              SizedBox(height: 16),
              SrxFormRow(alignment: CrossAxisAlignment.center, children: [
                Spacer(flex: 3),
                Expanded(
                    child: ElevatedButton(
                        autofocus: true,
                        onPressed: () => GetIt.I.get<SrxNavigationService>().pop(),
                        child: Text('srx.common.ok'.tr()))),
              ]),
            ]),
          )
        ]);
      }),
    );
  }

  Widget _buildStatus(BuildContext context, BrokerStatsViewmodel vm) {
    var style = Theme.of(context).textTheme.bodyMedium;
    switch (vm.state) {
      case BrokerStatsState.connecting:
        return Text('brokerstatsdialog.connecting'.tr(), style: style);
      case BrokerStatsState.waiting:
        return Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('brokerstatsdialog.waiting'.tr(), style: style),
        ]);
      case BrokerStatsState.receiving:
        return Text('brokerstatsdialog.receiving'.tr(), style: style);
      case BrokerStatsState.noData:
        return Text('brokerstatsdialog.nodata'.tr(), style: style);
      case BrokerStatsState.failed:
        return Text('brokerstatsdialog.failed'.tr(args: [vm.error ?? '']),
            style: style!.copyWith(color: Theme.of(context).colorScheme.error));
    }
  }

  Widget _buildSummary(BuildContext context, BrokerStatsViewmodel vm) {
    return Table(
      columnWidths: {0: FixedColumnWidth(260), 1: FlexColumnWidth()},
      children: [
        for (var (item, value) in vm.summary)
          TableRow(children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 12),
              child: Text('brokerstatsdialog.${item.key}.label'.tr(), style: Theme.of(context).textTheme.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(_format(item, value), style: Theme.of(context).textTheme.bodyMedium),
            ),
          ]),
      ],
    );
  }

  static String _format(SysSummaryItem item, String value) {
    if (!item.perMinute) {
      return value;
    }
    var number = num.tryParse(value.trim());
    var shown = number == null ? value : NumberFormat('#,##0.#').format(number);
    return 'brokerstatsdialog.perminute'.tr(args: [shown]);
  }

  Widget _buildTopicsHeader(BuildContext context, BrokerStatsViewmodel vm) {
    return Row(children: [
      Text('brokerstatsdialog.topics.label'.tr(args: ['${vm.topicCount}']), style: Theme.of(context).textTheme.titleMedium),
      Spacer(),
      SizedBox(
        width: 280,
        child: TextField(
          decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'brokerstatsdialog.filter.label'.tr(),
              isDense: true,
              prefixIcon: Icon(Icons.filter_alt)),
          onChanged: (value) => vm.topicFilter = value,
        ),
      ),
    ]);
  }

  Widget _buildTopics(BuildContext context, BrokerStatsViewmodel vm) {
    var topics = vm.topics;
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor)),
      child: SelectionArea(
        child: ListView.builder(
          itemCount: topics.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 6, child: Text(topics[index].key, style: diffTextStyle)),
              SizedBox(width: 12),
              Expanded(flex: 4, child: Text(topics[index].value.value, style: diffTextStyle)),
            ]),
          ),
        ),
      ),
    );
  }
}
