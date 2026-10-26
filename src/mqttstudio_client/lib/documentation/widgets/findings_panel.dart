import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/documentation/documentation_viewmodel.dart';
import 'package:mqttstudio/documentation/engine/conformance_checker.dart';
import 'package:mqttstudio/documentation/widgets/doc_format.dart';
import 'package:mqttstudio/documentation/widgets/documentation_dialogs.dart';
import 'package:provider/provider.dart';

// The findings of the running or last check, docked under the editor (doc/documentation-design.md §12.6). A click on
// a finding selects its documented topic.
class FindingsPanel extends StatelessWidget {
  static const double height = 280;

  const FindingsPanel({Key? key}) : super(key: key);

  static IconData iconOf(FindingSeverity severity) =>
      severity == FindingSeverity.error ? Icons.error : Icons.warning_amber;

  static Color colorOf(BuildContext context, FindingSeverity severity) =>
      severity == FindingSeverity.error ? Theme.of(context).colorScheme.error : Theme.of(context).custom.warning;

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<DocumentationViewmodel>();
    var findings = vm.findings ?? [];
    var theme = Theme.of(context);
    return Container(
      height: height,
      decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerColor))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _buildHead(context, vm, findings),
        Expanded(
          child: findings.isEmpty
              ? Center(
                  child: Text((vm.isChecking ? 'docfindings.none.running' : 'docfindings.none').tr(),
                      style: theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor)))
              : ListView.builder(
                  itemCount: findings.length + 1,
                  itemBuilder: (context, index) =>
                      index == 0 ? _buildHeader(context) : _buildRow(context, vm, findings[index - 1])),
        ),
      ]),
    );
  }

  Widget _buildHead(BuildContext context, DocumentationViewmodel vm, List<Finding> findings) {
    var theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      child: Row(children: [
        Text('docfindings.title'.tr(), style: theme.textTheme.titleMedium!.copyWith(color: Colors.black87)),
        SizedBox(width: 16),
        for (var severity in FindingSeverity.values) ...[
          Icon(iconOf(severity), size: 18, color: colorOf(context, severity)),
          SizedBox(width: 4),
          Text('${vm.findingCount(severity)}', style: theme.textTheme.bodyMedium),
          SizedBox(width: 12),
        ],
        Expanded(
          child: Text('docfindings.filters'.tr(args: [vm.checkFilters.join(', ')]),
              style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor), overflow: TextOverflow.ellipsis),
        ),
        TextButton.icon(
            style: TextButton.styleFrom(minimumSize: Size(0, 36)),
            onPressed: findings.isEmpty ? null : () => DocumentationDialogs.exportFindings(context, vm),
            icon: Icon(Icons.file_download),
            label: Text('docfindings.export.button'.tr())),
        IconButton(
            onPressed: vm.isChecking ? null : vm.clearFindings,
            icon: Icon(Icons.close),
            tooltip: 'docfindings.close.tooltip'.tr()),
      ]),
    );
  }

  static const Map<int, TableColumnWidth> _columns = {
    0: FixedColumnWidth(36),
    1: FlexColumnWidth(4),
    2: FlexColumnWidth(2),
    3: FixedColumnWidth(72),
    4: FixedColumnWidth(84),
    5: FlexColumnWidth(6),
  };

  Widget _buildHeader(BuildContext context) {
    var style = Theme.of(context).textTheme.labelLarge!.copyWith(color: Colors.black87);
    return _row(context, [
      SizedBox.shrink(),
      for (var key in [
        'docfindings.topic',
        'docfindings.rule',
        'docfindings.count',
        'docfindings.last',
        'docfindings.detail'
      ])
        Text(key.tr(), style: style),
    ]);
  }

  Widget _buildRow(BuildContext context, DocumentationViewmodel vm, Finding finding) {
    var node = finding.node;
    var time = DateFormat('HH:mm:ss').format(finding.last.toLocal());
    return InkWell(
      onTap: node == null ? null : () => vm.select(node.path),
      child: Tooltip(
        message: finding.examplePayload ?? '',
        child: _row(context, [
          Icon(iconOf(finding.severity), size: 18, color: colorOf(context, finding.severity)),
          Text(finding.topic, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Consolas', fontSize: 13)),
          Text(DocFormat.findingRule(finding), overflow: TextOverflow.ellipsis),
          Text(DocFormat.count(finding.count)),
          Text(time),
          Text(finding.detail, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, List<Widget> cells) {
    var theme = Theme.of(context);
    return Table(columnWidths: _columns, defaultVerticalAlignment: TableCellVerticalAlignment.middle, children: [
      TableRow(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
        children: [
          for (var cell in cells) Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: cell),
        ],
      ),
    ]);
  }
}
