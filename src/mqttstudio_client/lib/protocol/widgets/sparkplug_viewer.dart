import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/message_viewer/topic_stats.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_commands.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_state.dart';
import 'package:mqttstudio/protocol/widgets/rebirth_request.dart';
import 'package:provider/provider.dart';

typedef _Entry = SparkplugEntryState<ReceivedMqttMessage>;
typedef _Metric = SparkplugMetricState<ReceivedMqttMessage>;

// The Sparkplug view mode of the topic viewer (doc/sparkplug-design.md §13): host applications, groups, edge nodes
// and devices on the left, the metrics of the selected one with their current values on the right.
class SparkplugViewer extends StatefulWidget {
  static const double treeWidth = 320;
  static const double rowHeight = 32;

  const SparkplugViewer({Key? key}) : super(key: key);

  @override
  State<SparkplugViewer> createState() => _SparkplugViewerState();
}

class _SparkplugViewerState extends State<SparkplugViewer> {
  late final TextEditingController _filter;

  @override
  void initState() {
    super.initState();
    _filter = TextEditingController(text: context.read<MessageViewerViewmodel>().metricFilter);
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var viewmodel = context.watch<MessageViewerViewmodel>();
    var state = viewmodel.sparkplug;
    var theme = Theme.of(context);
    if (state.isEmpty) {
      return Expanded(
        child: Center(
          child: Text('sparkplugview.empty'.tr(), style: theme.textTheme.titleMedium!.copyWith(color: theme.hintColor)),
        ),
      );
    }
    var entry = viewmodel.selectedSparkplugEntry;
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: SparkplugViewer.treeWidth, child: _buildTree(context, viewmodel, state, entry)),
          VerticalDivider(width: 1),
          Expanded(child: entry == null ? SizedBox.shrink() : _buildEntry(context, viewmodel, entry)),
        ],
      ),
    );
  }

  // ---------- the tree ----------

  Widget _buildTree(
    BuildContext context,
    MessageViewerViewmodel viewmodel,
    SparkplugState<ReceivedMqttMessage> state,
    _Entry? selected,
  ) {
    var hosts = state.hosts;
    var nodes = state.nodes;
    return ListView(
      children: [
        if (hosts.isNotEmpty) ...[
          _buildSection(context, 'sparkplugview.hosts.label'.tr()),
          for (var host in hosts)
            _buildRow(
              context,
              dot: host.online ? SparkplugStatus.online : SparkplugStatus.offline,
              name: host.hostId,
              detail: (host.online ? 'sparkplugview.online.label' : 'sparkplugview.offline.label').tr(),
            ),
        ],
        for (var group in state.groups) ...[
          _buildSection(context, group),
          for (var node in nodes.where((node) => node.group == group)) ...[
            _buildRow(
              context,
              dot: node.status,
              name: node.edgeNode,
              detail: _nodeDetail(node),
              warning: node.seqGaps == 0 ? null : 'sparkplugview.seqgaps.tooltip'.plural(node.seqGaps),
              selected: selected?.key == node.key,
              onTap: () => viewmodel.selectSparkplugEntry(node),
            ),
            for (var device in node.devices.values.toList()..sort((a, b) => a.name.compareTo(b.name)))
              _buildRow(
                context,
                indent: 24,
                dot: device.status,
                name: device.name,
                detail: device.status == SparkplugStatus.offline
                    ? 'sparkplugview.offline.label'.tr()
                    : 'sparkplugview.metrics.count'.plural(device.metrics.length),
                selected: selected?.key == device.key,
                onTap: () => viewmodel.selectSparkplugEntry(device),
              ),
          ],
        ],
      ],
    );
  }

  String _nodeDetail(SparkplugNodeState<ReceivedMqttMessage> node) {
    if (node.status == SparkplugStatus.unknown) {
      return 'sparkplugview.nobirth.label'.tr();
    }
    if (node.status == SparkplugStatus.offline) {
      return 'sparkplugview.offline.label'.tr();
    }
    return [if (node.bdSeq != null) 'bdSeq ${node.bdSeq}', if (node.lastSeq != null) 'seq ${node.lastSeq}'].join('  ');
  }

  Widget _buildSection(BuildContext context, String title) {
    var theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Text(title, style: theme.textTheme.labelLarge!.copyWith(color: theme.hintColor)),
    );
  }

  Widget _buildRow(
    BuildContext context, {
    required SparkplugStatus dot,
    required String name,
    required String detail,
    double indent = 0,
    String? warning,
    bool selected = false,
    VoidCallback? onTap,
  }) {
    var theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: SparkplugViewer.rowHeight,
          padding: EdgeInsets.only(left: 12 + indent, right: 12),
          child: Row(
            children: [
              _StatusDot(status: dot),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: indent == 0 ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium,
                ),
              ),
              if (warning != null)
                Tooltip(
                  message: warning,
                  child: Icon(Icons.warning_amber, size: 16, color: theme.custom.warning),
                ),
              SizedBox(width: 8),
              Text(detail, style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- the selected edge node or device ----------

  Widget _buildEntry(BuildContext context, MessageViewerViewmodel viewmodel, _Entry entry) {
    var metrics = viewmodel.metricsOf(entry);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, viewmodel, entry),
          if (entry.metrics.values.any((metric) => metric.unknown)) _buildNoBirth(context, viewmodel, entry),
          SizedBox(height: 8),
          Row(
            children: [
              SizedBox(width: 320, child: _buildFilter(viewmodel)),
              SizedBox(width: 12),
              Text(
                'sparkplugview.metrics.count'.plural(entry.metrics.length),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          SizedBox(height: 8),
          _buildColumns(context, viewmodel),
          Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: metrics.length,
              itemExtent: SparkplugViewer.rowHeight,
              itemBuilder: (context, index) => _buildMetric(context, viewmodel, metrics[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, MessageViewerViewmodel viewmodel, _Entry entry) {
    var theme = Theme.of(context);
    var place = entry.device == null
        ? 'sparkplugview.node.caption'.tr(args: [entry.group])
        : 'sparkplugview.device.caption'.tr(args: [entry.edgeNode, entry.group]);
    var since = entry.since == null ? '' : DateFormat.Hms().format(entry.since!);
    var status = switch (entry.status) {
      SparkplugStatus.online => 'sparkplugview.onlinesince.label'.tr(args: [since]),
      SparkplugStatus.offline => 'sparkplugview.offlinesince.label'.tr(args: [since]),
      SparkplugStatus.unknown => 'sparkplugview.nobirth.label'.tr(),
    };
    var node = SparkplugEdgeNode(entry.group, entry.edgeNode);
    return Row(
      children: [
        _StatusDot(status: entry.status),
        SizedBox(width: 8),
        Text(entry.name, style: theme.textTheme.titleLarge),
        SizedBox(width: 12),
        // takes all the free width, so the buttons sit at the right edge
        Expanded(
          child: Text(
            '$place · $status',
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor),
          ),
        ),
        if (viewmodel.isLive)
          IconButton(
            onPressed: viewmodel.canRequestRebirth
                ? () => RebirthRequest.confirmAndSend(context, viewmodel, [node])
                : null,
            icon: Icon(Icons.autorenew),
            tooltip: 'sparkplug.rebirth.tooltip'.tr(args: [entry.edgeNode]),
          ),
        IconButton(
          onPressed: entry.lastMessage == null ? null : () => viewmodel.selectedMessage = entry.lastMessage,
          icon: Icon(Icons.article_outlined),
          tooltip: 'sparkplugview.lastmessage.tooltip'.tr(),
        ),
      ],
    );
  }

  // data by alias without the birth that names it (§13.4)
  Widget _buildNoBirth(BuildContext context, MessageViewerViewmodel viewmodel, _Entry entry) {
    var theme = Theme.of(context);
    var node = SparkplugEdgeNode(entry.group, entry.edgeNode);
    var requested = viewmodel.rebirthRequestedAt(node);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 16, color: theme.custom.warning),
          SizedBox(width: 6),
          Text('sparkplugview.unknownmetrics.label'.tr(), style: theme.textTheme.bodyMedium),
          SizedBox(width: 8),
          if (requested != null)
            Text(
              'sparkplug.rebirth.requested.label'.tr(args: [DateFormat.Hms().format(requested)]),
              style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor),
            )
          else if (viewmodel.isLive)
            TextButton(
              onPressed: viewmodel.canRequestRebirth
                  ? () => RebirthRequest.confirmAndSend(context, viewmodel, [node])
                  : null,
              style: TextButton.styleFrom(minimumSize: Size(0, 32)),
              child: Text('sparkplug.rebirth.button'.tr()),
            ),
        ],
      ),
    );
  }

  Widget _buildFilter(MessageViewerViewmodel viewmodel) {
    return TextField(
      controller: _filter,
      onChanged: (value) => viewmodel.metricFilter = value,
      decoration: InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        prefixIcon: Icon(Icons.filter_list),
        hintText: 'sparkplugview.filter.hint'.tr(),
        suffixIcon: IconButton(
          onPressed: () {
            _filter.clear();
            viewmodel.metricFilter = '';
          },
          icon: Icon(Icons.clear),
          tooltip: 'sparkplugview.filter.clear.tooltip'.tr(),
        ),
      ),
    );
  }

  // ---------- the metric table ----------

  static const Map<SparkplugMetricColumn, int> _flex = {
    SparkplugMetricColumn.name: 5,
    SparkplugMetricColumn.value: 4,
    SparkplugMetricColumn.type: 2,
    SparkplugMetricColumn.updated: 2,
    SparkplugMetricColumn.changes: 2,
  };

  Widget _buildColumns(BuildContext context, MessageViewerViewmodel viewmodel) {
    var theme = Theme.of(context);
    var style = theme.textTheme.labelLarge!.copyWith(color: theme.hintColor);
    Widget column(SparkplugMetricColumn column) {
      var sorted = viewmodel.metricSortColumn == column;
      return Expanded(
        flex: _flex[column]!,
        child: InkWell(
          onTap: () => viewmodel.sortMetrics(column, sorted ? !viewmodel.metricSortAscending : true),
          child: Row(
            children: [
              Text('sparkplugview.column.${column.name}'.tr(), style: style),
              if (sorted) Icon(viewmodel.metricSortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 14),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          for (var value in SparkplugMetricColumn.values) column(value),
          Expanded(flex: 4, child: Text('sparkplugview.column.properties'.tr(), style: style)),
        ],
      ),
    );
  }

  Widget _buildMetric(BuildContext context, MessageViewerViewmodel viewmodel, _Metric metric) {
    var theme = Theme.of(context);
    var hint = TextStyle(color: theme.hintColor);
    var slash = metric.name.lastIndexOf('/');
    var age = metric.receivedAt == null
        ? ''
        : TopicStats.formatDuration(viewmodel.statsReference.difference(metric.receivedAt!));
    var selected = identical(viewmodel.selectedMetric, metric) && viewmodel.selectedMessage != null;
    return Material(
      color: selected ? theme.colorScheme.primary.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: metric.message == null ? null : () => viewmodel.selectMetric(metric),
        child: Row(
          children: [
            Expanded(
              flex: _flex[SparkplugMetricColumn.name]!,
              child: Text.rich(
                TextSpan(
                  children: [
                    // the folder part of names like Motor/Speed, muted (V2)
                    if (slash > 0) TextSpan(text: metric.name.substring(0, slash + 1), style: hint),
                    TextSpan(
                      text: metric.name.substring(slash + 1),
                      style: metric.unknown ? TextStyle(color: theme.custom.warning) : null,
                    ),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: _flex[SparkplugMetricColumn.value]!,
              child: Text(
                metric.unit == null ? metric.formattedValue : '${metric.formattedValue} ${metric.unit}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
            Expanded(
              flex: _flex[SparkplugMetricColumn.type]!,
              child: Text(metric.type?.label ?? '', style: hint),
            ),
            Expanded(
              flex: _flex[SparkplugMetricColumn.updated]!,
              child: Text(age, style: hint),
            ),
            Expanded(flex: _flex[SparkplugMetricColumn.changes]!, child: Text('${metric.changes}')),
            Expanded(
              flex: 4,
              child: Text(
                metric.properties.entries.map((entry) => '${entry.key}=${entry.value}').join(', '),
                overflow: TextOverflow.ellipsis,
                style: hint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// online green, offline red, unknown a grey outline (doc/vda5050-design.md V11)
class _StatusDot extends StatelessWidget {
  final SparkplugStatus status;

  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var color = switch (status) {
      SparkplugStatus.online => theme.custom.connectedColor,
      SparkplugStatus.offline => theme.custom.disconnectedColor,
      SparkplugStatus.unknown => theme.custom.watermark,
    };
    return Tooltip(
      message: 'sparkplugview.status.${status.name}'.tr(),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: theme.hintColor),
        ),
      ),
    );
  }
}
