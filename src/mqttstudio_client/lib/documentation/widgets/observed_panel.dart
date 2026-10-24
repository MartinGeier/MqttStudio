import 'dart:math';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/documentation/documentation_viewmodel.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/widgets/doc_format.dart';
import 'package:provider/provider.dart';

// What the last discovery saw of the selected topic, on the right of the editor (doc/documentation-design.md §12.2).
// Read only: discovery replaces it, the user never edits it.
class ObservedPanel extends StatelessWidget {
  static const double width = 360;

  final ObservedTopic observed;

  const ObservedPanel({Key? key, required this.observed}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var vm = context.read<DocumentationViewmodel>();
    var theme = Theme.of(context);
    return Container(
      width: width,
      decoration: BoxDecoration(border: Border(left: BorderSide(color: theme.dividerColor))),
      child: ListView(padding: EdgeInsets.fromLTRB(12, 6, 12, 12), children: [
        Row(children: [
          Expanded(
              child:
                  Text('docobserved.title'.tr(), style: theme.textTheme.titleMedium!.copyWith(color: Colors.black87))),
          IconButton(
              onPressed: vm.toggleObservedPanel, icon: Icon(Icons.close), tooltip: 'docobserved.close.tooltip'.tr()),
        ]),
        Text(_source(), style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor)),
        SizedBox(height: 16),
        _buildFacts(context),
        if (observed.interval.medianMs != null) ...[SizedBox(height: 24), _buildIntervals(context)],
        if (observed.parameterValues.isNotEmpty) ...[SizedBox(height: 24), _buildParameters(context)],
        if (observed.userPropertyKeys.isNotEmpty) ...[
          SizedBox(height: 24),
          _title(context, 'docobserved.userproperties.label'),
          SizedBox(height: 8),
          _tags(context, [
            for (var entry in observed.userPropertyKeys.entries)
              '${entry.key} ${observed.messages == 0 ? 0 : entry.value * 100 ~/ observed.messages} %'
          ]),
        ],
        if (observed.lastPayload != null) ...[SizedBox(height: 24), _buildLastPayload(context)],
      ]),
    );
  }

  String _source() {
    var format = DateFormat('dd.MM.yyyy HH:mm');
    var source = switch (observed.source) {
      DiscoverySource.live => 'docobserved.source.live'.tr(),
      DiscoverySource.recording => 'docobserved.source.recording'.tr(args: [observed.sourceName ?? '']),
      DiscoverySource.buffer => 'docobserved.source.buffer'.tr(),
    };
    var duration = DocFormat.duration(observed.to.difference(observed.from).inMilliseconds);
    return '$source · ${format.format(observed.from.toLocal())} · $duration';
  }

  Widget _buildFacts(BuildContext context) {
    var interval = observed.interval;
    var qos = observed.mainQos;
    var qosShare = qos == null || observed.messages == 0 ? 0 : observed.qosCounts[qos]! * 100 ~/ observed.messages;
    var facts = [
      ('docobserved.messages.label', DocFormat.count(observed.messages), null),
      ('docobserved.instances.label', DocFormat.count(observed.instanceCount), null),
      (
        'docobserved.rate.label',
        'docobserved.rate.value'.tr(args: [interval.rate.toStringAsFixed(interval.rate < 10 ? 2 : 0)]),
        null
      ),
      (
        'docobserved.interval.label',
        interval.medianMs == null ? '–' : DocFormat.duration(interval.medianMs),
        interval.p10Ms == null ? null : '${DocFormat.duration(interval.p10Ms)} – ${DocFormat.duration(interval.p90Ms)}'
      ),
      ('docobserved.size.label', '${observed.sizeMin} – ${observed.sizeMax} B', 'Ø ${observed.sizeAverage.round()} B'),
      ('doceditor.qos.label', qos == null ? '–' : '$qos', qos == null ? null : '$qosShare %'),
      ('doceditor.retain.label', DocFormat.observedRetain(observed), null),
      ('doceditor.format.label', DocFormat.format(observed.mainFormat), DocFormat.interval(interval.kind)),
      if (observed.numericMin != null)
        (
          'docobserved.range.label',
          '${DocFormat.number(observed.numericMin)} – ${DocFormat.number(observed.numericMax)}',
          null
        ),
    ];
    var theme = Theme.of(context);
    return Wrap(runSpacing: 12, children: [
      for (var (key, value, sub) in facts)
        SizedBox(
          width: (width - 24) / 2,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(key.tr(), style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor)),
            Text(value, style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w500)),
            if (sub != null) Text(sub, style: theme.textTheme.bodySmall),
          ]),
        ),
    ]);
  }

  // min, the spread between p10 and p90, and max of the interval on a log scale
  Widget _buildIntervals(BuildContext context) {
    var theme = Theme.of(context);
    var interval = observed.interval;
    double scale(int? ms) => ms == null || ms <= 0 ? 0 : log(ms) / log(max(2, interval.maxMs ?? 2) * 1.2);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(context, 'docobserved.spread.label'),
      SizedBox(height: 8),
      LayoutBuilder(builder: (context, constraints) {
        var w = constraints.maxWidth;
        return SizedBox(
          height: 24,
          child: Stack(children: [
            Positioned(left: 0, right: 0, top: 11, child: Container(height: 2, color: theme.dividerColor)),
            Positioned(
              left: w * scale(interval.p10Ms),
              width: max(4, w * (scale(interval.p90Ms) - scale(interval.p10Ms))),
              top: 4,
              child: Container(height: 16, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
            ),
            Positioned(
                left: w * scale(interval.medianMs) - 1,
                top: 0,
                child: Container(width: 2, height: 24, color: theme.colorScheme.primary)),
          ]),
        );
      }),
      SizedBox(height: 2),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(DocFormat.duration(interval.minMs), style: theme.textTheme.bodySmall),
        Text(DocFormat.duration(interval.maxMs), style: theme.textTheme.bodySmall),
      ]),
    ]);
  }

  Widget _buildParameters(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title(context, 'docobserved.instances.label'),
      SizedBox(height: 8),
      for (var entry in observed.parameterValues.entries) ...[
        Text(entry.key, style: Theme.of(context).textTheme.bodySmall),
        SizedBox(height: 4),
        _tags(context, entry.value),
        SizedBox(height: 8),
      ],
    ]);
  }

  Widget _buildLastPayload(BuildContext context) {
    var theme = Theme.of(context);
    var at = observed.lastPayloadAt;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _title(context, 'docobserved.lastpayload.label')),
        if (at != null)
          Text('${observed.lastTopic ?? ''} · ${DateFormat('HH:mm:ss').format(at.toLocal())}',
              style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor)),
      ]),
      SizedBox(height: 6),
      Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration:
            BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(4)),
        child:
            SelectableText(observed.lastPayload!, maxLines: 10, style: TextStyle(fontFamily: 'Consolas', fontSize: 13)),
      ),
    ]);
  }

  Widget _title(BuildContext context, String key) => Text(key.tr(), style: Theme.of(context).textTheme.titleSmall);

  Widget _tags(BuildContext context, List<String> values) {
    var theme = Theme.of(context);
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (var value in values)
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(10)),
          child: Text(value, style: theme.textTheme.bodySmall),
        ),
    ]);
  }
}
