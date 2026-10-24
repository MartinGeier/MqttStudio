import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/documentation/doc_root_editor_model.dart';
import 'package:mqttstudio/documentation/documentation_viewmodel.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/widgets/doc_widgets.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// The documentation as a whole, shown when the root of the tree is selected: its title and description, what it
// contains and the topics in it
class DocOverview extends StatelessWidget {
  const DocOverview({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<DocumentationViewmodel>();
    var editor = vm.rootEditor!;
    var theme = Theme.of(context);
    return ReactiveForm(
        formGroup: editor.form,
        child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(Icons.menu_book, color: Colors.black87),
                SizedBox(width: 12),
                Expanded(child: Text('docoverview.title'.tr(), style: theme.textTheme.titleLarge)),
                Text('docoverview.revision'.tr(args: ['${editor.documentation.revision}']),
                    style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor))
              ]),
              SizedBox(height: 24),
              SrxFormRow(children: [
                Expanded(flex: 3, child: DocWidgets.textField(DocRootEditorModel.title, 'doceditor.title.label')),
                SizedBox(width: 16),
                Expanded(flex: 2, child: DocWidgets.textField(DocRootEditorModel.owner, 'doceditor.owner.label'))
              ]),
              SizedBox(height: 16),
              DocWidgets.textField(DocRootEditorModel.description, 'doceditor.description.label',
                  minLines: 3, maxLines: 12),
              SizedBox(height: 24),
              DocWidgets.sectionTitle(context, 'docoverview.contents.section'),
              SizedBox(height: 16),
              _buildCounts(context, vm.documentation!),
              SizedBox(height: 24),
              DocWidgets.sectionTitle(context, 'doceditor.topics.section'),
              SizedBox(height: 8),
              DocWidgets.topicsTable(context, vm, vm.tree)
            ])));
  }

  Widget _buildCounts(BuildContext context, TopicDocumentation documentation) {
    var theme = Theme.of(context);
    var topics = documentation.topics.toList();
    Widget count(String key, int value) => Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(key.tr(), style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor)),
          Text('$value', style: theme.textTheme.titleLarge)
        ]));
    return Row(children: [
      count('docoverview.topics.label', topics.length),
      count('docoverview.templates.label', topics.where((node) => node.parameters.isNotEmpty).length),
      count('docoverview.undocumented.label', topics.where((node) => node.isUndocumented).length),
      count('docoverview.deprecated.label', topics.where((node) => node.status == DocStatus.deprecated).length)
    ]);
  }
}
