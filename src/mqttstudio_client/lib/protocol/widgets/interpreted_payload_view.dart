import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/protocol/protocol_profile.dart';

// Colors and icons of what a device reports (doc/vda5050-design.md V11): the theme's error color and the custom
// warning color, no new tokens
class InterpretationStyle {
  static Color? colorOf(BuildContext context, InterpretationLevel level) => switch (level) {
        InterpretationLevel.error => Theme.of(context).colorScheme.error,
        InterpretationLevel.warning => Theme.of(context).custom.warning,
        InterpretationLevel.none => null,
      };

  static IconData? iconOf(InterpretationLevel level) => switch (level) {
        InterpretationLevel.error => Icons.error,
        InterpretationLevel.warning => Icons.warning_amber,
        InterpretationLevel.none => null,
      };
}

// The sections of an interpreted message in the detail view (doc/vda5050-design.md §7): collapsible, key-value
// pairs, dense tables and the fields the profile doesn't know as JSON
class InterpretedPayloadView extends StatelessWidget {
  final Interpretation interpretation;
  final bool Function(String key) isCollapsed;
  final void Function(String key) onToggle;
  final ScrollController? controller;
  // the widget for an InterpretedValue's action, e.g. a button; null shows nothing
  final Widget? Function(String action)? actionBuilder;

  const InterpretedPayloadView(
      {Key? key,
      required this.interpretation,
      required this.isCollapsed,
      required this.onToggle,
      this.controller,
      this.actionBuilder})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var section in interpretation.sections) _buildSection(context, section),
      ]),
    );
  }

  Widget _buildSection(BuildContext context, InterpretedSection section) {
    var theme = Theme.of(context);
    var collapsed = isCollapsed(section.key);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: () => onToggle(section.key),
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(children: [
            Icon(collapsed ? Icons.chevron_right : Icons.expand_more, size: 20),
            SizedBox(width: 4),
            Text(section.title, style: theme.textTheme.titleMedium),
          ]),
        ),
      ),
      if (!collapsed)
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: switch (section) {
            KeyValueSection values => _buildValues(context, values),
            TableSection table => _buildTable(context, table),
            RawSection raw => SelectableText(const JsonEncoder.withIndent('  ').convert(raw.json),
                style: theme.textTheme.bodyMedium!.copyWith(fontFamily: 'monospace')),
          },
        ),
    ]);
  }

  Widget _buildValues(BuildContext context, KeyValueSection section) {
    var theme = Theme.of(context);
    return Table(
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (var value in section.values)
          TableRow(children: [
            Padding(
              padding: const EdgeInsets.only(right: 16, top: 2, bottom: 2),
              child: Text(value.label, style: theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor)),
            ),
            Row(children: [
              if (InterpretationStyle.iconOf(value.level) != null) ...[
                Icon(InterpretationStyle.iconOf(value.level), size: 16, color: InterpretationStyle.colorOf(context, value.level)),
                SizedBox(width: 4),
              ],
              Expanded(
                  child: SelectableText(value.value,
                      style: theme.textTheme.bodyLarge!.copyWith(color: InterpretationStyle.colorOf(context, value.level)))),
              if (value.action != null && actionBuilder?.call(value.action!) != null) ...[
                SizedBox(width: 8),
                actionBuilder!(value.action!)!,
              ],
            ]),
          ]),
      ],
    );
  }

  Widget _buildTable(BuildContext context, TableSection section) {
    var theme = Theme.of(context);
    var header = theme.textTheme.labelLarge!.copyWith(color: theme.hintColor);
    var cell = theme.textTheme.bodyMedium!;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 28,
        dataRowMinHeight: 24,
        dataRowMaxHeight: 32,
        horizontalMargin: 0,
        columnSpacing: 16,
        columns: [for (var column in section.columns) DataColumn(label: Text(column, style: header))],
        rows: [
          for (var row in section.rows)
            DataRow(cells: [
              for (var i = 0; i < section.columns.length; i++)
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  if (i == 0 && InterpretationStyle.iconOf(row.level) != null) ...[
                    Icon(InterpretationStyle.iconOf(row.level), size: 16, color: InterpretationStyle.colorOf(context, row.level)),
                    SizedBox(width: 4),
                  ],
                  Text(i < row.cells.length ? row.cells[i] : '',
                      style: cell.copyWith(
                          color: row.muted ? theme.hintColor : InterpretationStyle.colorOf(context, row.level))),
                ])),
            ]),
        ],
      ),
    );
  }
}
