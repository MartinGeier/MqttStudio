import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/documentation/documentation_viewmodel.dart';
import 'package:mqttstudio/documentation/engine/doc_path.dart';
import 'package:mqttstudio/documentation/engine/doc_tree.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/widgets/doc_format.dart';
import 'package:mqttstudio/documentation/widgets/documentation_dialogs.dart';
import 'package:provider/provider.dart';

// The documented topics on the left of the DOCUMENTATION tab: the documentation itself on top, then the path tree
class DocTree extends StatelessWidget {
  static const double width = 320;
  static const double rowHeight = 32;
  static const double indent = 20;

  const DocTree({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<DocumentationViewmodel>();
    var theme = Theme.of(context);
    return Container(
        width: width,
        decoration: BoxDecoration(border: Border(right: BorderSide(color: theme.dividerColor))),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_buildHead(context, vm), Expanded(child: _buildRows(context, vm))]));
  }

  Widget _buildHead(BuildContext context, DocumentationViewmodel vm) {
    var theme = Theme.of(context);
    return Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        child: Row(children: [
          Expanded(
              child: Text('doctree.title'.tr(), style: theme.textTheme.titleMedium!.copyWith(color: Colors.black87))),
          if (vm.isProjectOpen)
            Text('doctree.counts'.tr(args: ['${vm.topicCount}', '${vm.undocumentedCount}']),
                style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor))
        ]));
  }

  Widget _buildRows(BuildContext context, DocumentationViewmodel vm) {
    var theme = Theme.of(context);
    if (!vm.isProjectOpen) {
      return SizedBox.shrink();
    }
    var rows = vm.rows;
    if (vm.tree.children.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _buildRow(context, vm, rows.first),
        Expanded(
            child: Center(
                child: Text('doctree.watermark'.tr(),
                    style: theme.textTheme.headlineMedium!.copyWith(color: theme.dividerColor))))
      ]);
    }
    return ListView.builder(
        itemCount: rows.length,
        itemExtent: rowHeight,
        itemBuilder: (context, index) => _buildRow(context, vm, rows[index]));
  }

  Widget _buildRow(BuildContext context, DocumentationViewmodel vm, DocTreeRow row) {
    var theme = Theme.of(context);
    var entry = row.entry;
    var selected = entry.path == vm.selectedPath;
    return GestureDetector(
        onSecondaryTapDown: entry.isRoot
            ? null
            : (details) => DocumentationDialogs.showNodeMenu(context, vm, entry, details.globalPosition),
        child: Material(
            color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
            child: InkWell(
                onTap: () => vm.select(entry.path),
                child: Container(
                    decoration: selected
                        ? BoxDecoration(border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3)))
                        : null,
                    padding: EdgeInsets.only(left: (selected ? 5 : 8) + row.depth * indent, right: 8),
                    child: Row(children: [
                      _buildLeading(context, vm, entry),
                      SizedBox(width: 4),
                      Expanded(child: _buildName(context, vm, entry, selected)),
                      ..._buildTags(context, entry)
                    ])))));
  }

  Widget _buildLeading(BuildContext context, DocumentationViewmodel vm, DocTreeEntry entry) {
    if (entry.isRoot) {
      return Icon(Icons.menu_book, size: 20, color: Colors.black87);
    }
    if (entry.children.isNotEmpty && !vm.isFiltered) {
      return InkWell(
          onTap: () => vm.toggleExpanded(entry.path!),
          customBorder: CircleBorder(),
          child: Icon(vm.isExpanded(entry.path!) ? Icons.expand_more : Icons.chevron_right,
              size: 20, color: Colors.black87));
    }
    if (entry.isTopic) {
      return Container(
          width: 20,
          alignment: Alignment.center,
          child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: Theme.of(context).custom.topicGroup, shape: BoxShape.circle)));
    }
    return SizedBox(width: 20);
  }

  Widget _buildName(BuildContext context, DocumentationViewmodel vm, DocTreeEntry entry, bool selected) {
    var theme = Theme.of(context);
    var style = theme.textTheme.bodyMedium!.copyWith(fontWeight: selected ? FontWeight.w500 : null);
    if (entry.isRoot) {
      var title = vm.documentation?.title ?? '';
      return Text(title.isEmpty ? 'doctree.root.label'.tr() : title, style: style, overflow: TextOverflow.ellipsis);
    }
    var segment = DocPath.tryParse(entry.segment)?.segments.single;
    var spans = segment == null || !segment.isParameter
        ? [TextSpan(text: entry.segment.isEmpty ? ' ' : entry.segment)]
        : [
            TextSpan(text: segment.prefix),
            TextSpan(
                text: '{${segment.parameter}}',
                style: TextStyle(fontStyle: FontStyle.italic, color: theme.colorScheme.primary)),
            TextSpan(text: segment.suffix)
          ];
    return Text.rich(TextSpan(style: style, children: spans), overflow: TextOverflow.ellipsis, maxLines: 1);
  }

  List<Widget> _buildTags(BuildContext context, DocTreeEntry entry) {
    var node = entry.node;
    if (node == null) {
      return [];
    }
    var theme = Theme.of(context);
    return [
      if (node.isTopic && node.isUndocumented)
        Tooltip(
            message: 'doctree.undocumented.tooltip'.tr(),
            child: Icon(Icons.edit_note, size: 18, color: theme.hintColor)),
      if (node.review != DocReviewState.none)
        Container(
            margin: EdgeInsets.only(left: 4),
            padding: EdgeInsets.symmetric(horizontal: 8),
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(10)),
            child: Text('doctree.review.${node.review.name}'.tr(),
                style: theme.textTheme.bodySmall!.copyWith(color: Colors.black87))),
      if (node.isTopic || node.status == DocStatus.deprecated)
        Container(
            margin: EdgeInsets.only(left: 4),
            padding: EdgeInsets.symmetric(horizontal: 8),
            height: 20,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(10)),
            child:
                Text(DocFormat.status(node.status), style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor)))
    ];
  }
}
