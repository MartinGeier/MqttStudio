import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/common/utils/number_value_accessor.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/common/widgets/mqtt5_section.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/documentation/doc_node_editor_model.dart';
import 'package:mqttstudio/documentation/documentation_viewmodel.dart';
import 'package:mqttstudio/documentation/engine/doc_tree.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/documentation/widgets/doc_format.dart';
import 'package:mqttstudio/documentation/widgets/doc_widgets.dart';
import 'package:mqttstudio/documentation/widgets/documentation_dialogs.dart';
import 'package:mqttstudio/documentation/widgets/schema_table.dart';
import 'package:mqttstudio/documentation/widgets/tag_field.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';

typedef E = DocNodeEditorModel;

// Edits a documented topic or namespace (doc/documentation-design.md §12.4). Every change goes to the node at once.
class TopicDocEditor extends StatelessWidget {
  const TopicDocEditor({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<DocumentationViewmodel>();
    var editor = vm.editor!;
    var entry = vm.selectedEntry!;
    return ChangeNotifierProvider.value(
        value: editor,
        child: Consumer<DocNodeEditorModel>(
            builder: (context, editor, _) => ReactiveForm(
                formGroup: editor.form,
                child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 12, 24, 24),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _buildHeader(context, vm, entry),
                      SizedBox(height: 24),
                      ..._buildGeneral(context, editor),
                      if (editor.parameterNames.isNotEmpty) ...[
                        SizedBox(height: 24),
                        ..._buildParameters(context, editor)
                      ],
                      if (editor.isTopic) ...[
                        SizedBox(height: 24),
                        ..._buildPayload(context, editor),
                        SizedBox(height: 24),
                        ..._buildDelivery(context, editor),
                        SizedBox(height: 24),
                        _buildMqtt5(context, editor),
                        SizedBox(height: 24),
                        ..._buildAccess(context)
                      ],
                      if (entry.children.isNotEmpty) ...[
                        SizedBox(height: 24),
                        DocWidgets.sectionTitle(context, 'doceditor.topics.section'),
                        SizedBox(height: 8),
                        DocWidgets.topicsTable(context, vm, entry)
                      ]
                    ])))));
  }

  Widget _buildHeader(BuildContext context, DocumentationViewmodel vm, DocTreeEntry entry) {
    var theme = Theme.of(context);
    var color = theme.custom.topicGroup;
    var textColor = theme.getTextColor(color);
    return Row(children: [
      Expanded(
          child: Material(
              color: color,
              elevation: 2,
              shape: StadiumBorder(),
              child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(children: [
                    Expanded(
                        child: SelectableText(entry.path!,
                            maxLines: 1, style: theme.textTheme.titleSmall!.copyWith(color: textColor))),
                    IconButton(
                        onPressed: () => Clipboard.setData(ClipboardData(text: entry.path!)),
                        icon: Icon(Icons.content_copy, size: 20, color: textColor),
                        tooltip: 'doceditor.copypath.tooltip'.tr())
                  ])))),
      SizedBox(width: 8),
      if (entry.node?.observed != null && !vm.isObservedPanelOpen)
        IconButton(
            onPressed: vm.toggleObservedPanel,
            icon: Icon(Icons.insights),
            tooltip: 'doceditor.showobserved.tooltip'.tr()),
      Builder(
          builder: (buttonContext) => IconButton(
              onPressed: () {
                var box = buttonContext.findRenderObject() as RenderBox;
                DocumentationDialogs.showNodeMenu(
                    buttonContext, vm, entry, box.localToGlobal(box.size.bottomLeft(Offset.zero)));
              },
              icon: Icon(Icons.more_vert),
              tooltip: 'doceditor.actions.tooltip'.tr()))
    ]);
  }

  List<Widget> _buildGeneral(BuildContext context, DocNodeEditorModel editor) {
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 5, child: DocWidgets.textField(E.title, 'doceditor.title.label')),
        SizedBox(width: 16),
        Expanded(
            flex: 2,
            child:
                DocWidgets.dropdown<DocStatus>(E.status, 'doceditor.status.label', DocStatus.values, DocFormat.status)),
        SizedBox(width: 16),
        Expanded(flex: 3, child: DocWidgets.textField(E.owner, 'doceditor.owner.label'))
      ]),
      if (editor.isDeprecated) ...[
        SizedBox(height: 16),
        DocWidgets.textField(E.replacedBy, 'doceditor.replacedby.label')
      ],
      SizedBox(height: 16),
      ReactiveTagField(formControlName: E.tags, labelText: 'doceditor.tags.label'.tr()),
      SizedBox(height: 16),
      DocWidgets.textField(E.description, 'doceditor.description.label', minLines: 3, maxLines: 12),
      SizedBox(height: 8),
      for (var i = 0; i < editor.array(E.links).controls.length; i++) ...[
        _buildLinkRow(editor, i),
        SizedBox(height: 12)
      ],
      DocWidgets.addButton('doceditor.addlink.button', editor.addLink)
    ];
  }

  Widget _buildLinkRow(DocNodeEditorModel editor, int index) {
    var group = editor.array(E.links).controls[index] as FormGroup;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
          flex: 2,
          child: DocWidgets.textField('', 'doceditor.linklabel.label',
              control: group.control(E.linkLabel) as FormControl<String>)),
      SizedBox(width: 16),
      Expanded(
          flex: 5,
          child: DocWidgets.textField('', 'doceditor.linkurl.label',
              control: group.control(E.linkUrl) as FormControl<String>)),
      _removeButton(() => editor.removeAt(E.links, index))
    ]);
  }

  List<Widget> _buildParameters(BuildContext context, DocNodeEditorModel editor) {
    var names = editor.parameterNames;
    var groups = editor.array(E.parameters).controls;
    return [
      DocWidgets.sectionTitle(context, 'doceditor.parameters.section'),
      SizedBox(height: 16),
      for (var i = 0; i < names.length && i < groups.length; i++) ...[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 140,
              child: InputDecorator(
                  decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'doceditor.parametername.label'.tr(),
                      isDense: true,
                      enabled: false),
                  child: Text(names[i], overflow: TextOverflow.ellipsis))),
          SizedBox(width: 16),
          Expanded(
              flex: 2,
              child: DocWidgets.textField('', 'doceditor.pattern.label',
                  control: (groups[i] as FormGroup).control(E.parameterPattern) as FormControl<String>)),
          SizedBox(width: 16),
          Expanded(
              flex: 5,
              child: DocWidgets.textField('', 'doceditor.fielddescription.label',
                  control: (groups[i] as FormGroup).control(E.parameterDescription) as FormControl<String>))
        ]),
        SizedBox(height: 12)
      ]
    ];
  }

  List<Widget> _buildPayload(BuildContext context, DocNodeEditorModel editor) {
    var format = editor.form.control(E.payloadFormat).value as PayloadFormat;
    var isNumber = format == PayloadFormat.number;
    return [
      DocWidgets.sectionTitle(context, 'doceditor.payload.section'),
      SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: DocWidgets.dropdown<PayloadFormat>(
                E.payloadFormat, 'doceditor.format.label', PayloadFormat.values, DocFormat.format,
                helperText: editor.observedHint(E.payloadFormat))),
        SizedBox(width: 16),
        Expanded(child: DocWidgets.textField(E.encoding, 'doceditor.encoding.label')),
        if (isNumber) ...[
          SizedBox(width: 16),
          Expanded(child: DocWidgets.textField(E.unit, 'doceditor.unit.label')),
          SizedBox(width: 16),
          Expanded(child: _numberField(E.min, 'doceditor.min.label', helperText: editor.observedHint(E.min))),
          SizedBox(width: 16),
          Expanded(child: _numberField(E.max, 'doceditor.max.label'))
        ]
      ]),
      if (isNumber || format == PayloadFormat.string) ...[
        SizedBox(height: 16),
        ReactiveTagField(formControlName: E.allowedValues, labelText: 'doceditor.allowedvalues.label'.tr())
      ],
      if (editor.isJson) ...[SizedBox(height: 16), SchemaTable(editor: editor)],
      SizedBox(height: 16),
      Text('doceditor.examples.label'.tr(), style: Theme.of(context).textTheme.titleSmall),
      SizedBox(height: 8),
      for (var i = 0; i < editor.array(E.examples).controls.length; i++) ...[
        _buildExampleRow(editor, i),
        SizedBox(height: 12)
      ],
      DocWidgets.addButton('doceditor.addexample.button', editor.addExample)
    ];
  }

  Widget _numberField(String name, String labelKey, {String? helperText}) {
    return ReactiveTextField<double>(
        formControlName: name,
        valueAccessor: NumberValueAccessor(),
        maxLines: 1,
        decoration: InputDecoration(
            border: OutlineInputBorder(), labelText: labelKey.tr(), helperText: helperText, isDense: true),
        validationMessages: {'range': (_) => 'doceditor.range.error'.tr()});
  }

  Widget _buildExampleRow(DocNodeEditorModel editor, int index) {
    var group = editor.array(E.examples).controls[index] as FormGroup;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
          flex: 5,
          child: DocWidgets.textField('', 'doceditor.examplepayload.label',
              minLines: 1,
              maxLines: 8,
              style: TextStyle(fontFamily: 'Consolas', fontSize: 13),
              control: group.control(E.examplePayload) as FormControl<String>)),
      SizedBox(width: 16),
      Expanded(
          flex: 2,
          child: DocWidgets.textField('', 'doceditor.examplenote.label',
              control: group.control(E.exampleNote) as FormControl<String>)),
      _removeButton(() => editor.removeAt(E.examples, index))
    ]);
  }

  List<Widget> _buildDelivery(BuildContext context, DocNodeEditorModel editor) {
    return [
      DocWidgets.sectionTitle(context, 'doceditor.delivery.section'),
      SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: DocWidgets.dropdown<MqttQos?>(E.qos, 'doceditor.qos.label',
                [null, MqttQos.atMostOnce, MqttQos.atLeastOnce, MqttQos.exactlyOnce], DocFormat.qos,
                helperText: editor.observedHint(E.qos))),
        SizedBox(width: 16),
        Expanded(
            child: DocWidgets.dropdown<RetainMode>(
                E.retain, 'doceditor.retain.label', RetainMode.values, DocFormat.retain,
                helperText: editor.observedHint(E.retain)))
      ]),
      SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            flex: 4,
            child: DocWidgets.dropdown<IntervalKind>(
                E.intervalKind, 'doceditor.interval.label', IntervalKind.values, DocFormat.interval)),
        SizedBox(width: 16),
        Expanded(
            flex: 3,
            child: DocWidgets.textField(E.nominalInterval, 'doceditor.nominal.label',
                helperText: editor.observedHint(E.nominalInterval) ?? 'doceditor.duration.helper'.tr())),
        SizedBox(width: 16),
        Expanded(flex: 3, child: DocWidgets.textField(E.staleAfter, 'doceditor.staleafter.label'))
      ]),
      CheckboxField(formControlName: E.lastWill, form: editor.form, label: 'doceditor.lastwill.label'.tr())
    ];
  }

  Widget _buildMqtt5(BuildContext context, DocNodeEditorModel editor) {
    var enabled = editor.isMqtt5;
    return Mqtt5Section(title: 'doceditor.mqtt5.section'.tr(), enabled: enabled, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: DocWidgets.textField(E.contentType, 'doceditor.contenttype.label')),
        SizedBox(width: 16),
        Expanded(
            flex: 2,
            child: ReactiveTextField<int>(
                formControlName: E.messageExpiry,
                maxLines: 1,
                decoration: InputDecoration(
                    border: OutlineInputBorder(), labelText: 'doceditor.messageexpiry.label'.tr(), isDense: true),
                validationMessages: {
                  ValidationMessage.min: (_) => 'doceditor.messageexpiry.error'.tr(),
                  ValidationMessage.number: (_) => 'doceditor.messageexpiry.error'.tr()
                }))
      ]),
      CheckboxField(formControlName: E.utf8Payload, form: editor.form, label: 'doceditor.utf8payload.label'.tr()),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: DocWidgets.textField(E.responseTopic, 'doceditor.responsetopic.label')),
        SizedBox(width: 16),
        Expanded(child: DocWidgets.textField(E.correlationData, 'doceditor.correlationdata.label'))
      ]),
      SizedBox(height: 8),
      for (var i = 0; i < editor.array(E.userProperties).controls.length; i++) ...[
        _buildUserPropertyRow(editor, i),
        SizedBox(height: 12)
      ],
      DocWidgets.addButton('doceditor.adduserproperty.button', enabled ? editor.addUserProperty : null)
    ]);
  }

  Widget _buildUserPropertyRow(DocNodeEditorModel editor, int index) {
    var group = editor.array(E.userProperties).controls[index] as FormGroup;
    FormControl<String> control(String name) => group.control(name) as FormControl<String>;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
          flex: 2,
          child: DocWidgets.textField('', 'doceditor.userpropertykey.label', control: control(E.userPropertyKey))),
      SizedBox(width: 16),
      Expanded(
          flex: 4,
          child: DocWidgets.textField('', 'doceditor.fielddescription.label',
              control: control(E.userPropertyDescription))),
      SizedBox(width: 16),
      Expanded(
          flex: 2,
          child:
              DocWidgets.textField('', 'doceditor.userpropertyexample.label', control: control(E.userPropertyExample))),
      _removeButton(() => editor.removeAt(E.userProperties, index))
    ]);
  }

  List<Widget> _buildAccess(BuildContext context) {
    return [
      DocWidgets.sectionTitle(context, 'doceditor.access.section'),
      SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            flex: 3,
            child: ReactiveTagField(formControlName: E.producers, labelText: 'doceditor.producers.label'.tr())),
        SizedBox(width: 16),
        Expanded(
            flex: 3,
            child: ReactiveTagField(formControlName: E.consumers, labelText: 'doceditor.consumers.label'.tr())),
        SizedBox(width: 16),
        Expanded(
            flex: 2,
            child: DocWidgets.dropdown<Sensitivity>(
                E.sensitivity, 'doceditor.sensitivity.label', Sensitivity.values, DocFormat.sensitivity))
      ]),
      SizedBox(height: 16),
      DocWidgets.textField(E.accessNotes, 'doceditor.accessnotes.label', minLines: 2, maxLines: 8)
    ];
  }

  Widget _removeButton(VoidCallback onPressed) => IconButton(
      onPressed: onPressed, icon: Icon(Icons.remove_circle_outline), tooltip: 'doceditor.remove.tooltip'.tr());
}
