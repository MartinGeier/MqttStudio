import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/documentation/doc_node_editor_model.dart';
import 'package:mqttstudio/documentation/engine/schema_paths.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/documentation/widgets/doc_format.dart';
import 'package:mqttstudio/documentation/widgets/documentation_dialogs.dart';

// The fields of a JSON payload, one row per field path. A click on a row edits the field.
class SchemaTable extends StatelessWidget {
  final DocNodeEditorModel editor;

  const SchemaTable({Key? key, required this.editor}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var rows = SchemaPaths.flatten(editor.schema);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('schematable.title'.tr(), style: theme.textTheme.titleSmall)),
        TextButton.icon(
            onPressed: () => DocumentationDialogs.editSchemaField(context, editor),
            icon: Icon(Icons.add),
            label: Text('schematable.addfield.button'.tr()))
      ]),
      if (rows.isEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('schematable.empty.label'.tr(),
                style: theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor)))
      else
        Table(
            columnWidths: {
              0: FlexColumnWidth(3),
              1: IntrinsicColumnWidth(),
              2: IntrinsicColumnWidth(),
              3: FlexColumnWidth(3),
              4: FixedColumnWidth(48),
              5: FlexColumnWidth(4),
              6: FixedColumnWidth(48)
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [_buildHeader(context), for (var row in rows) _buildRow(context, row)])
    ]);
  }

  TableRow _buildHeader(BuildContext context) {
    var theme = Theme.of(context);
    var style = theme.textTheme.labelLarge!.copyWith(color: Colors.black87);
    return TableRow(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
        children: [
          for (var key in [
            'schematable.field',
            'schematable.type',
            'schematable.unit',
            'schematable.range',
            'schematable.required',
            'schematable.description'
          ])
            _cell(Text(key.tr(), style: style)),
          SizedBox.shrink()
        ]);
  }

  TableRow _buildRow(BuildContext context, SchemaRow row) {
    var theme = Theme.of(context);
    var node = row.node;
    void edit() => DocumentationDialogs.editSchemaField(context, editor, path: row.path, required: row.required);
    Widget tap(Widget child) => InkWell(onTap: edit, child: _cell(child));
    return TableRow(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
        children: [
          tap(Text(row.path, style: TextStyle(fontFamily: 'Consolas', fontSize: 13), overflow: TextOverflow.ellipsis)),
          tap(Text(_type(node))),
          tap(Text(node.unit ?? '')),
          tap(Text(DocFormat.range(node.minimum, node.maximum, node.enumValues), overflow: TextOverflow.ellipsis)),
          tap(row.required
              ? Icon(Icons.check, size: 18, semanticLabel: 'schematable.required'.tr())
              : SizedBox(height: 18)),
          tap(Text(node.description, overflow: TextOverflow.ellipsis)),
          IconButton(
              onPressed: () => editor.removeSchemaField(row.path),
              icon: Icon(Icons.remove_circle_outline, size: 20),
              tooltip: 'schematable.remove.tooltip'.tr())
        ]);
  }

  static String _type(SchemaNode node) =>
      node.format == null ? DocFormat.schemaType(node.type) : '${DocFormat.schemaType(node.type)} (${node.format})';

  static Widget _cell(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9), child: child);
}
