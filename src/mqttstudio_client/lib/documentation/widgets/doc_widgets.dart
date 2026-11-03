import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/documentation/documentation_viewmodel.dart';
import 'package:mqttstudio/documentation/engine/doc_tree.dart';
import 'package:mqttstudio/documentation/widgets/doc_format.dart';
import 'package:reactive_forms/reactive_forms.dart';

// Building blocks shared by the editors of the documentation tab
class DocWidgets {
  static Widget sectionTitle(BuildContext context, String key, {Widget? action}) {
    var theme = Theme.of(context);
    return Container(
        padding: EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
        child: Row(children: [
          Expanded(child: Text(key.tr(), style: theme.textTheme.titleSmall)),
          if (action != null) action
        ]));
  }

  static Widget textField(String name, String labelKey,
      {int minLines = 1,
      int maxLines = 1,
      bool readOnly = false,
      String? helperText,
      TextStyle? style,
      FormControl<String>? control}) {
    return ReactiveTextField<String>(
        formControlName: control == null ? name : null,
        formControl: control,
        minLines: minLines,
        maxLines: maxLines,
        readOnly: readOnly,
        style: style,
        decoration: InputDecoration(
            border: OutlineInputBorder(),
            labelText: labelKey.tr(),
            helperText: helperText,
            isDense: true,
            alignLabelWithHint: maxLines > 1),
        validationMessages: {
          ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr(),
          'pattern': (_) => 'doceditor.pattern.error'.tr(),
          'duration': (_) => 'doceditor.duration.error'.tr()
        });
  }

  static Widget dropdown<V>(String name, String labelKey, List<V> values, String Function(V value) label,
      {String? helperText}) {
    return ReactiveDropdownField<V>(
        formControlName: name,
        isExpanded: true,
        decoration: InputDecoration(
            border: OutlineInputBorder(), labelText: labelKey.tr(), helperText: helperText, isDense: true),
        items: [
          for (var value in values)
            DropdownMenuItem(value: value, child: Text(label(value), overflow: TextOverflow.ellipsis))
        ]);
  }

  static Widget addButton(String key, VoidCallback? onPressed) => Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
          style: TextButton.styleFrom(minimumSize: Size(0, 36)),
          onPressed: onPressed,
          icon: Icon(Icons.playlist_add),
          label: Text(key.tr())));

  // the topics below a namespace, or below the root; a click selects one
  static Widget topicsTable(BuildContext context, DocumentationViewmodel vm, DocTreeEntry entry) {
    var theme = Theme.of(context);
    var topics = entry.descendants.where((child) => child.isTopic).toList();
    if (topics.isEmpty) {
      return Text('doceditor.notopics.label'.tr(), style: theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor));
    }
    var prefix = entry.isRoot ? '' : '${entry.path}/';
    TableRow header(List<String> keys) =>
        TableRow(decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))), children: [
          for (var key in keys)
            _cell(Text(key.tr(), style: theme.textTheme.labelLarge!.copyWith(color: Colors.black87)))
        ]);
    return Table(
        columnWidths: {
          0: FlexColumnWidth(3),
          1: FlexColumnWidth(3),
          2: IntrinsicColumnWidth(),
          3: IntrinsicColumnWidth(),
          4: IntrinsicColumnWidth()
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          header([
            'doceditor.topics.path',
            'doceditor.title.label',
            'doceditor.format.label',
            'doceditor.interval.label',
            'doceditor.status.label'
          ]),
          for (var topic in topics)
            TableRow(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
                children: [
                  _cell(InkWell(
                      onTap: () => vm.select(topic.path),
                      child: Text(topic.path!.substring(prefix.length),
                          style: theme.textTheme.bodyMedium!
                              .copyWith(color: theme.colorScheme.primary, decoration: TextDecoration.underline)))),
                  _cell(Text(topic.node!.title, overflow: TextOverflow.ellipsis)),
                  _cell(Text(DocFormat.format(topic.node!.topic!.payload.format))),
                  _cell(Text(_interval(topic))),
                  _cell(Text(DocFormat.status(topic.node!.status)))
                ])
        ]);
  }

  static String _interval(DocTreeEntry entry) {
    var interval = entry.node!.topic!.interval;
    var nominal = DocFormat.duration(interval.nominalMs);
    return nominal.isEmpty ? DocFormat.interval(interval.kind) : '${DocFormat.interval(interval.kind)} · $nominal';
  }

  static Widget _cell(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9), child: child);
}
