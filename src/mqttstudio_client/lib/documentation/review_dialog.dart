import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/documentation/engine/discovery_merger.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/review_viewmodel.dart';
import 'package:mqttstudio/documentation/widgets/doc_format.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Shows what a discovery found, in tabs: proposed templates, new topics, changed and not seen documented topics
// (doc/documentation-design.md §5.6, §12.5). Returns true when the result is to be applied.
class ReviewDialog extends StatefulWidget {
  final DiscoveryResult result;

  const ReviewDialog({Key? key, required this.result}) : super(key: key);

  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  static const double listWidth = 380;
  late final ReviewViewmodel _viewmodel;

  @override
  void initState() {
    super.initState();
    _viewmodel = ReviewViewmodel(widget.result);
  }

  @override
  void dispose() {
    _viewmodel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewmodel,
      child: Consumer<ReviewViewmodel>(builder: (context, vm, _) {
        return SimpleDialog(
          title: Text('docreview.title'.tr()),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 960, maxWidth: 960),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _buildSummary(context, vm),
                SizedBox(height: 12),
                _buildTabs(context, vm),
                SizedBox(height: 12),
                SizedBox(height: 440, child: _buildBody(context, vm)),
                SizedBox(height: 16),
                _buildActions(vm),
              ]),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildSummary(BuildContext context, ReviewViewmodel vm) {
    var theme = Theme.of(context);
    var result = vm.result;
    var source = result.sourceName == null ? '' : '${result.sourceName} · ';
    var lines = [
      Text(
          '$source${'docreview.summary'.tr(args: [
                DocFormat.count(result.topicCount),
                DocFormat.duration(result.duration.inMilliseconds),
                DocFormat.count(result.messages)
              ])}',
          style: theme.textTheme.bodyMedium),
      if (result.skippedMessages > 0)
        Text('docreview.topiclimit.warning'.tr(args: [DocFormat.count(result.skippedMessages)]),
            style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error)),
      for (var error in result.errors)
        Text(error, style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error)),
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.travel_explore, size: 20, color: theme.hintColor),
      SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines)),
    ]);
  }

  Widget _buildTabs(BuildContext context, ReviewViewmodel vm) {
    var theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
      child: Row(children: [
        for (var tab in ReviewTab.values)
          InkWell(
            onTap: () => vm.selectTab(tab),
            child: Container(
              height: 48,
              padding: EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                  border: Border(
                      bottom:
                          BorderSide(color: vm.tab == tab ? theme.colorScheme.primary : Colors.transparent, width: 2))),
              child: Row(children: [
                Text('docreview.tab.${tab.name}'.tr(),
                    style: theme.textTheme.labelLarge!
                        .copyWith(color: vm.tab == tab ? theme.colorScheme.primary : theme.hintColor)),
                SizedBox(width: 8),
                _tag(context, '${vm.countOf(tab)}'),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _buildBody(BuildContext context, ReviewViewmodel vm) {
    var theme = Theme.of(context);
    if (vm.items.isEmpty) {
      return Center(
          child: Text('docreview.empty.${vm.tab.name}'.tr(),
              style: theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor)));
    }
    return Container(
      decoration: BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(4)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          width: listWidth,
          decoration: BoxDecoration(border: Border(right: BorderSide(color: theme.dividerColor))),
          child: ListView(children: [for (var item in vm.items) _buildItem(context, vm, item)]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: vm.selected == null ? SizedBox.shrink() : _buildDetail(context, vm, vm.selected!),
          ),
        ),
      ]),
    );
  }

  Widget _buildItem(BuildContext context, ReviewViewmodel vm, Object item) {
    var theme = Theme.of(context);
    var selected = identical(item, vm.selected);
    var (path, meta, checkbox) = switch (item) {
      NewItem newItem when vm.tab == ReviewTab.templates => (
          newItem.path,
          _templateMeta(newItem),
          Checkbox(value: newItem.asTemplate, onChanged: (value) => vm.setAsTemplate(newItem, value == true))
        ),
      NewItem newItem => (
          newItem.path,
          newItem.isTemplate ? _templateMeta(newItem) : DocFormat.observedSummary(newItem.observed),
          Checkbox(value: newItem.accept, onChanged: (value) => vm.setAccept(newItem, value == true))
        ),
      ChangedItem changed => (changed.node.path, 'docreview.differences.meta'.plural(changed.differences.length), null),
      DocNode node => (node.path, node.title, null),
      _ => ('', '', null),
    };
    return Material(
      color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: () => vm.select(item),
        child: Container(
          constraints: BoxConstraints(minHeight: 56),
          padding: EdgeInsets.only(left: checkbox == null ? 16 : 0, right: 12),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: theme.dividerColor),
                  left: BorderSide(color: selected ? theme.colorScheme.primary : Colors.transparent, width: 3))),
          child: Row(children: [
            if (checkbox != null) checkbox,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(path,
                    style: theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
                if (meta.isNotEmpty)
                  Text(meta,
                      style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor),
                      overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  String _templateMeta(NewItem item) {
    var topics = 'docreview.template.meta'.plural(item.detected.topics.length);
    return item.collapses.isEmpty ? topics : '$topics · ${'docreview.template.replaces'.plural(item.collapses.length)}';
  }

  Widget _buildDetail(BuildContext context, ReviewViewmodel vm, Object item) => switch (item) {
        NewItem newItem => _buildNewDetail(context, vm, newItem),
        ChangedItem changed => _buildChangedDetail(context, vm, changed),
        DocNode node => _buildNotSeenDetail(context, node),
        _ => SizedBox.shrink(),
      };

  Widget _buildNewDetail(BuildContext context, ReviewViewmodel vm, NewItem item) {
    var theme = Theme.of(context);
    var observed = item.observed;
    var instances = observed.instances.take(12).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(item.path, style: theme.textTheme.titleSmall),
      SizedBox(height: 12),
      if (vm.namesForm != null) ...[_buildNames(context, vm, item), SizedBox(height: 16)],
      _buildFacts(context, [
        ('docreview.messages.label', DocFormat.count(observed.messages)),
        ('docreview.instances.label', DocFormat.count(observed.instanceCount)),
        ('docreview.payload.label', DocFormat.observedSummary(observed)),
        ('doceditor.qos.label', observed.mainQos == null ? '–' : 'QoS ${observed.mainQos}'),
        ('doceditor.retain.label', DocFormat.observedRetain(observed)),
      ]),
      if (item.isTemplate) ...[
        SizedBox(height: 16),
        Text('docreview.topics.label'.tr(), style: theme.textTheme.titleSmall),
        SizedBox(height: 4),
        Text([...instances, if (observed.instanceCount > instances.length) '…'].join('\n'),
            style: theme.textTheme.bodySmall!.copyWith(fontFamily: 'Consolas')),
      ],
      if (item.collapses.isNotEmpty) ...[
        SizedBox(height: 16),
        Text('docreview.replaces.label'.tr(), style: theme.textTheme.titleSmall),
        SizedBox(height: 4),
        Text(item.collapses.map((node) => node.path).join('\n'), style: theme.textTheme.bodySmall),
      ],
      if (observed.lastPayload != null) ...[
        SizedBox(height: 16),
        Text('docreview.example.label'.tr(), style: theme.textTheme.titleSmall),
        SizedBox(height: 4),
        _code(context, observed.lastPayload!),
      ],
      if (!item.accept) ...[
        SizedBox(height: 8),
        Row(children: [
          Checkbox(value: item.ignore, onChanged: (value) => vm.setIgnore(item, value == true)),
          Expanded(
              child: Text('docreview.ignore.label'.tr(args: [DiscoveryMerger.ignoreFilterOf(item.path)]),
                  style: theme.textTheme.bodyMedium)),
        ]),
      ],
    ]);
  }

  Widget _buildNames(BuildContext context, ReviewViewmodel vm, NewItem item) {
    return ReactiveForm(
      formGroup: vm.namesForm!,
      child: Wrap(spacing: 16, runSpacing: 16, children: [
        for (var name in item.parameterNames)
          SizedBox(
            width: 200,
            child: ReactiveTextField<String>(
              formControlName: name,
              maxLines: 1,
              decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'docreview.parameter.label'.tr(args: [name]),
                  helperText: item.detected.patterns[name],
                  isDense: true),
              validationMessages: {
                ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
                ValidationMessage.pattern: (_) => 'docreview.parameter.error'.tr(),
                'unique': (_) => 'docreview.parameter.unique.error'.tr(),
              },
            ),
          ),
      ]),
    );
  }

  Widget _buildChangedDetail(BuildContext context, ReviewViewmodel vm, ChangedItem item) {
    var theme = Theme.of(context);
    var header = theme.textTheme.labelLarge!.copyWith(color: Colors.black87);
    TableRow row(List<Widget> cells) => TableRow(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))), children: cells);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(item.node.path, style: theme.textTheme.titleSmall),
      SizedBox(height: 12),
      Table(
        columnWidths: {0: FlexColumnWidth(3), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2), 3: FixedColumnWidth(64)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          row([
            _cell(Text('docreview.field.label'.tr(), style: header)),
            _cell(Text('docreview.documented.label'.tr(), style: header)),
            _cell(Text('docreview.observed.label'.tr(), style: header)),
            _cell(Text('docreview.adopt.label'.tr(), style: header)),
          ]),
          for (var difference in item.differences)
            row([
              _cell(Text(DocFormat.difference(difference.kind, difference.subject))),
              _cell(Text(DocFormat.differenceValue(difference.kind, difference.documented))),
              _cell(Text(DocFormat.differenceValue(difference.kind, difference.observed))),
              Checkbox(value: difference.adopt, onChanged: (value) => vm.setAdopt(difference, value == true)),
            ]),
        ],
      ),
      SizedBox(height: 16),
      _note(context, 'docreview.changed.note'.tr()),
    ]);
  }

  Widget _buildNotSeenDetail(BuildContext context, DocNode node) {
    var theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(node.path, style: theme.textTheme.titleSmall),
      SizedBox(height: 12),
      _note(context, 'docreview.notseen.note'.tr()),
    ]);
  }

  Widget _buildFacts(BuildContext context, List<(String, String)> facts) {
    var theme = Theme.of(context);
    return Wrap(spacing: 32, runSpacing: 12, children: [
      for (var (key, value) in facts)
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(key.tr(), style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor)),
          Text(value, style: theme.textTheme.bodyLarge),
        ]),
    ]);
  }

  Widget _note(BuildContext context, String text) {
    var theme = Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.info_outline, size: 18, color: theme.hintColor),
      SizedBox(width: 8),
      Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
    ]);
  }

  Widget _code(BuildContext context, String text) {
    var theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(4)),
      child: SelectableText(text, maxLines: 6, style: TextStyle(fontFamily: 'Consolas', fontSize: 13)),
    );
  }

  Widget _tag(BuildContext context, String text) {
    var theme = Theme.of(context);
    return Container(
      height: 18,
      padding: EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(9)),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }

  static Widget _cell(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9), child: child);

  Widget _buildActions(ReviewViewmodel vm) {
    return SrxFormRow(alignment: CrossAxisAlignment.center, children: [
      Spacer(flex: 1),
      Expanded(
          flex: 5,
          child: OutlinedButton(
              onPressed: () => GetIt.I.get<SrxNavigationService>().pop(false), child: Text('srx.common.cancel'.tr()))),
      SizedBox(width: 16),
      Expanded(
          flex: 5,
          child: ElevatedButton(
              onPressed: vm.canApply ? () => GetIt.I.get<SrxNavigationService>().pop(true) : null,
              child: Text('docreview.apply.button'.tr()))),
    ]);
  }
}
