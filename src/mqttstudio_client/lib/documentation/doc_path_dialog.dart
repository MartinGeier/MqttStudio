import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/documentation/doc_path_viewmodel.dart';
import 'package:mqttstudio/documentation/engine/doc_path.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/widgets/doc_format.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

typedef P = DocPathViewmodel;

// Adds a topic or a namespace (ADD pops with the node; ADD & NEW hands it to onAdd and stays open), or asks for the
// new path of a move (pops with the path)
class DocPathDialog extends StatefulWidget {
  final DocPathDialogMode mode;
  final String? basePath;
  final void Function(DocNode node)? onAdd;

  const DocPathDialog({Key? key, required this.mode, this.basePath, this.onAdd}) : super(key: key);

  @override
  State<DocPathDialog> createState() => _DocPathDialogState();
}

class _DocPathDialogState extends State<DocPathDialog> {
  late final DocPathViewmodel _viewmodel;
  final _pathFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _viewmodel = DocPathViewmodel(widget.mode, basePath: widget.basePath);
  }

  @override
  void dispose() {
    _pathFocus.dispose();
    _viewmodel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: _viewmodel,
        child: Consumer<DocPathViewmodel>(builder: (context, vm, _) {
          return SimpleDialog(title: Text(_titleKey.tr()), contentPadding: EdgeInsets.all(16), children: [
            ConstrainedBox(
                constraints: BoxConstraints(minWidth: 480, maxWidth: 480),
                child: ReactiveForm(
                    formGroup: vm.form,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _buildPathField(vm),
                      if (!vm.isMove) ...[SizedBox(height: 16), _buildTitleField()],
                      if (widget.mode == DocPathDialogMode.addTopic && vm.copySources.isNotEmpty) ...[
                        SizedBox(height: 16),
                        _buildCopyFromField(vm)
                      ],
                      SizedBox(height: 24),
                      _buildActions(vm)
                    ])))
          ]);
        }));
  }

  String get _titleKey => switch (widget.mode) {
        DocPathDialogMode.addTopic => 'docpathdialog.addtopic.title',
        DocPathDialogMode.addNamespace => 'docpathdialog.addnamespace.title',
        DocPathDialogMode.move => 'docpathdialog.move.title'
      };

  Widget _buildPathField(DocPathViewmodel vm) {
    return ReactiveTextField<String>(
        formControlName: P.pathField,
        focusNode: _pathFocus,
        autofocus: true,
        maxLines: 1,
        decoration: InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'docpathdialog.path.label'.tr(),
            helperText:
                vm.isMove ? 'docpathdialog.move.helper'.plural(vm.movedCount) : 'docpathdialog.path.helper'.tr(),
            isDense: true),
        validationMessages: {
          ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
          'path': (error) => DocFormat.pathError(error as DocPathError),
          'taken': (_) => 'docpathdialog.path.taken.error'.tr(),
          'sameShape': (_) => 'docpathdialog.path.sameshape.error'.tr()
        },
        onSubmitted: (_) => _submit(vm, again: false));
  }

  Widget _buildTitleField() {
    return ReactiveTextField<String>(
        formControlName: P.titleField,
        maxLines: 1,
        decoration:
            InputDecoration(border: OutlineInputBorder(), labelText: 'doceditor.title.label'.tr(), isDense: true),
        validationMessages: {ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr()},
        onSubmitted: (_) => _submit(_viewmodel, again: false));
  }

  Widget _buildCopyFromField(DocPathViewmodel vm) {
    return ReactiveDropdownField<String>(
        formControlName: P.copyFromField,
        isExpanded: true,
        decoration: InputDecoration(
            border: OutlineInputBorder(), labelText: 'docpathdialog.copyfrom.label'.tr(), isDense: true),
        items: [
          DropdownMenuItem<String>(value: null, child: Text('docpathdialog.copyfrom.none'.tr())),
          for (var path in vm.copySources)
            DropdownMenuItem(value: path, child: Text(path, overflow: TextOverflow.ellipsis))
        ]);
  }

  Widget _buildActions(DocPathViewmodel vm) {
    var canAddAgain = widget.mode != DocPathDialogMode.move && widget.onAdd != null;
    return SrxFormRow(alignment: CrossAxisAlignment.center, children: [
      Spacer(flex: 1),
      Expanded(
          flex: 5,
          child: OutlinedButton(
              onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('srx.common.cancel'.tr()))),
      SizedBox(width: 16),
      Expanded(
          flex: 5,
          child: ElevatedButton(
              onPressed: () => _submit(vm, again: false),
              child: Text((vm.isMove ? 'docpathdialog.move.button' : 'docpathdialog.add.button').tr()))),
      if (canAddAgain) ...[
        SizedBox(width: 16),
        Expanded(
            flex: 5,
            child: ElevatedButton(
                onPressed: () => _submit(vm, again: true), child: Text('docpathdialog.addnew.button'.tr())))
      ]
    ]);
  }

  void _submit(DocPathViewmodel vm, {required bool again}) {
    if (vm.isMove) {
      if (vm.form.valid) {
        GetIt.I.get<SrxNavigationService>().pop(vm.path);
      } else {
        vm.form.markAllAsTouched();
      }
      return;
    }
    var node = vm.createNode();
    if (node == null) {
      return;
    }
    if (again) {
      widget.onAdd!(node);
      vm.reset();
      _pathFocus.requestFocus();
    } else {
      GetIt.I.get<SrxNavigationService>().pop(node);
    }
  }
}
