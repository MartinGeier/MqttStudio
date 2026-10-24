import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/common/widgets/error_snackbar.dart';
import 'package:mqttstudio/documentation/discover_dialog.dart';
import 'package:mqttstudio/documentation/discover_viewmodel.dart';
import 'package:mqttstudio/documentation/doc_node_editor_model.dart';
import 'package:mqttstudio/documentation/doc_path_dialog.dart';
import 'package:mqttstudio/documentation/doc_path_viewmodel.dart';
import 'package:mqttstudio/documentation/documentation_viewmodel.dart';
import 'package:mqttstudio/documentation/engine/discovery_merger.dart';
import 'package:mqttstudio/documentation/engine/doc_tree.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/review_dialog.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/schema_field_dialog.dart';
import 'package:mqttstudio/documentation/schema_field_viewmodel.dart';
import 'package:srx_flutter/srx_flutter.dart';

enum _NodeAction { addTopic, addNamespace, move, duplicate, toTopic, toNamespace, delete }

// Opens the dialogs and menus of the documentation tab and applies their result
class DocumentationDialogs {
  static Future<T?> _show<T>(BuildContext context, Widget dialog) =>
      showDialog<T>(context: context, builder: (_) => SrxTheme(data: CustomTheme.srxTheme, child: dialog));

  static Future discover(BuildContext context, DocumentationViewmodel vm,
      {DiscoverySource source = DiscoverySource.live, String? recordingId}) async {
    var request = await _show<DiscoverRequest>(context, DiscoverDialog(source: source, recordingId: recordingId));
    if (request == null || !context.mounted) {
      return;
    }
    try {
      await vm.startDiscovery(request);
    } catch (exc) {
      if (context.mounted) {
        await _show(context, SrxDialog.error(title: 'discoverdialog.cannotstart.title'.tr(), bodyText: exc.toString()));
      }
    }
  }

  static Future review(BuildContext context, DocumentationViewmodel vm, DiscoveryResult result) async {
    var apply = await _show<bool>(context, ReviewDialog(result: result));
    if (apply == true) {
      vm.applyDiscovery(result);
    }
  }

  static void discoveryError(BuildContext context, String message) =>
      ScaffoldMessenger.of(context).showSnackBar(errorSnackBar('discovery.error'.tr(args: [message]), context));

  static Future addNode(
      BuildContext context, DocumentationViewmodel vm, DocPathDialogMode mode, String? basePath) async {
    var node = await _show<DocNode>(context, DocPathDialog(mode: mode, basePath: basePath, onAdd: vm.addNode));
    if (node != null) {
      vm.addNode(node);
    }
  }

  static Future move(BuildContext context, DocumentationViewmodel vm, String path) async {
    var target = await _show<String>(context, DocPathDialog(mode: DocPathDialogMode.move, basePath: path));
    if (target != null && target != path) {
      vm.movePath(path, target);
    }
  }

  static Future delete(BuildContext context, DocumentationViewmodel vm, String path) async {
    var count = vm.countAtOrBelow(path);
    var confirmed = await _show<bool>(
        context, SrxDialog.yesNo(bodyText: 'documentation.delete.confirm'.plural(count, namedArgs: {'path': path})));
    if (confirmed == true) {
      vm.deletePath(path);
    }
  }

  static Future editSchemaField(BuildContext context, DocNodeEditorModel editor,
      {String? path, bool required = false}) async {
    var result = await _show<SchemaFieldResult>(
        context, SchemaFieldDialog(schema: editor.schema, path: path, required: required));
    if (result != null) {
      editor.putSchemaField(path, result.path, result.field, required: result.required);
    }
  }

  static Future showNodeMenu(
      BuildContext context, DocumentationViewmodel vm, DocTreeEntry entry, Offset position) async {
    var path = entry.path!;
    var node = entry.node;
    var overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    PopupMenuItem<_NodeAction> item(_NodeAction action, IconData icon, String key) =>
        PopupMenuItem(value: action, child: ListTile(leading: Icon(icon), title: Text(key.tr()), dense: true));
    var action = await showMenu<_NodeAction>(
        context: context,
        position: RelativeRect.fromRect(position & Size(1, 1), Offset.zero & overlay.size),
        items: [
          item(_NodeAction.addTopic, Icons.add, 'documentation.menu.addtopic'),
          item(_NodeAction.addNamespace, Icons.create_new_folder, 'documentation.menu.addnamespace'),
          item(_NodeAction.move, Icons.drive_file_rename_outline, 'documentation.menu.move'),
          if (node != null) item(_NodeAction.duplicate, Icons.content_copy, 'documentation.menu.duplicate'),
          if (node != null && !node.isTopic) item(_NodeAction.toTopic, Icons.topic, 'documentation.menu.totopic'),
          if (node != null && node.isTopic)
            item(_NodeAction.toNamespace, Icons.folder, 'documentation.menu.tonamespace'),
          item(_NodeAction.delete, Icons.delete, 'documentation.menu.delete')
        ]);
    if (!context.mounted || action == null) {
      return;
    }
    switch (action) {
      case _NodeAction.addTopic:
        await addNode(context, vm, DocPathDialogMode.addTopic, path);
      case _NodeAction.addNamespace:
        await addNode(context, vm, DocPathDialogMode.addNamespace, path);
      case _NodeAction.move:
        await move(context, vm, path);
      case _NodeAction.duplicate:
        vm.duplicate(node!);
      case _NodeAction.toTopic:
        vm.setTopic(node!, true);
      case _NodeAction.toNamespace:
        await _confirmToNamespace(context, vm, node!);
      case _NodeAction.delete:
        await delete(context, vm, path);
    }
  }

  // the topic details are lost
  static Future _confirmToNamespace(BuildContext context, DocumentationViewmodel vm, DocNode node) async {
    var confirmed = await _show<bool>(
        context, SrxDialog.yesNo(bodyText: 'documentation.tonamespace.confirm'.tr(args: [node.path])));
    if (confirmed == true) {
      vm.setTopic(node, false);
    }
  }
}
