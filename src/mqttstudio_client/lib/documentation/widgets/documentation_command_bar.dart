import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/documentation/check_service.dart';
import 'package:mqttstudio/documentation/discovery_service.dart';
import 'package:mqttstudio/documentation/engine/conformance_checker.dart';
import 'package:mqttstudio/documentation/widgets/findings_panel.dart';
import 'package:mqttstudio/documentation/doc_path_viewmodel.dart';
import 'package:mqttstudio/documentation/documentation_viewmodel.dart';
import 'package:mqttstudio/documentation/widgets/doc_format.dart';
import 'package:mqttstudio/documentation/widgets/documentation_dialogs.dart';
import 'package:provider/provider.dart';

// The toolbar of the documentation tab, laid out like the command bar of the topic viewer
class DocumentationCommandBar extends StatefulWidget {
  const DocumentationCommandBar({Key? key}) : super(key: key);

  @override
  State<DocumentationCommandBar> createState() => _DocumentationCommandBarState();
}

class _DocumentationCommandBarState extends State<DocumentationCommandBar> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<DocumentationViewmodel>();
    return Column(children: [
      Divider(height: 4),
      Row(children: [
        _buildDiscovery(vm),
        SizedBox(height: 40, child: VerticalDivider()),
        _buildCheck(vm),
        SizedBox(height: 40, child: VerticalDivider()),
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Tooltip(
                message: 'documentation.addtopic.tooltip'.tr(),
                child: TextButton.icon(
                    onPressed: vm.isProjectOpen
                        ? () => DocumentationDialogs.addNode(context, vm, DocPathDialogMode.addTopic, _namespaceOf(vm))
                        : null,
                    icon: Icon(Icons.add),
                    label: Text('documentation.addtopic.button'.tr())))),
        SizedBox(height: 40, child: VerticalDivider()),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _buildSearchField(vm)),
        _buildFilter(vm),
        Spacer(),
        Tooltip(
          message: 'documentation.import.tooltip'.tr(),
          child: Builder(
            builder: (buttonContext) => TextButton.icon(
                onPressed: vm.isProjectOpen && !vm.isDiscovering ? () => _import(buttonContext, vm) : null,
                icon: Icon(Icons.file_upload),
                label: Text('documentation.import.button'.tr())),
          ),
        ),
        Tooltip(
          message: 'documentation.export.tooltip'.tr(),
          child: TextButton.icon(
              onPressed: vm.isProjectOpen ? () => DocumentationDialogs.exportDocumentation(context, vm) : null,
              icon: Icon(Icons.file_download),
              label: Text('documentation.export.button'.tr())),
        ),
        SizedBox(width: 8),
        if (vm.lastDiscoveryResult != null && !vm.isDiscovering)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Tooltip(
              message: 'documentation.review.tooltip'.tr(),
              child: TextButton.icon(
                  onPressed: () => DocumentationDialogs.review(context, vm, vm.lastDiscoveryResult!),
                  icon: Icon(Icons.fact_check),
                  label: Text('documentation.review.button'.tr())),
            ),
          ),
      ]),
      Divider(height: 4)
    ]);
  }

  // an AsyncAPI file or the VDA 5050 preset (doc/vda5050-design.md §9.1); the menu opens below the button
  Future<void> _import(BuildContext buttonContext, DocumentationViewmodel vm) async {
    var button = buttonContext.findRenderObject() as RenderBox;
    var overlay = Overlay.of(buttonContext).context.findRenderObject() as RenderBox;
    var position = RelativeRect.fromRect(
        Rect.fromPoints(button.localToGlobal(button.size.bottomLeft(Offset.zero), ancestor: overlay),
            button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay)),
        Offset.zero & overlay.size);
    var preset = await showMenu<bool>(context: buttonContext, position: position, items: [
      PopupMenuItem(
          value: false,
          child: ListTile(
              leading: Icon(Icons.description), title: Text('documentation.import.file'.tr()), dense: true)),
      PopupMenuItem(
          value: true,
          child: ListTile(
              leading: Icon(Icons.precision_manufacturing),
              title: Text('documentation.import.vda5050'.tr()),
              dense: true)),
    ]);
    if (!buttonContext.mounted || preset == null) {
      return;
    }
    if (preset) {
      await DocumentationDialogs.addPreset(buttonContext, vm);
    } else {
      await DocumentationDialogs.importDocumentation(buttonContext, vm);
    }
  }

  // a new topic goes into the selected namespace, or next to the selected topic
  String? _namespaceOf(DocumentationViewmodel vm) {
    var entry = vm.selectedEntry;
    if (entry == null || entry.isRoot) {
      return null;
    }
    if (entry.isTopic && entry.children.isEmpty) {
      var path = entry.path!;
      var index = path.lastIndexOf('/');
      return index < 0 ? null : path.substring(0, index);
    }
    return entry.path;
  }

  Widget _buildSearchField(DocumentationViewmodel vm) {
    return Row(children: [
      Icon(Icons.search, color: vm.isProjectOpen ? null : Theme.of(context).disabledColor),
      SizedBox(width: 6),
      SizedBox(
          width: 300,
          height: 40,
          child: TextField(
              controller: _searchController,
              enabled: vm.isProjectOpen,
              maxLines: 1,
              decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'documentation.search.hint'.tr(),
                  isDense: true,
                  suffixIcon: IconButton(
                      icon: Icon(Icons.clear),
                      tooltip: 'documentation.search.clear.tooltip'.tr(),
                      onPressed: vm.isProjectOpen
                          ? () {
                              _searchController.clear();
                              vm.setSearch('');
                            }
                          : null)),
              onChanged: (text) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () => vm.setSearch(text));
              }))
    ]);
  }

  Widget _buildFilter(DocumentationViewmodel vm) {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Tooltip(
            message: 'documentation.filter.tooltip'.tr(),
            child: DropdownButton<DocFilter>(
                value: vm.filter,
                onChanged: vm.isProjectOpen ? (filter) => vm.setFilter(filter!) : null,
                items: [
                  for (var filter in DocFilter.values)
                    DropdownMenuItem(value: filter, child: Text('documentation.filter.${filter.name}'.tr()))
                ])));
  }

  Widget _buildDiscovery(DocumentationViewmodel vm) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(children: [
        Tooltip(
          message: 'documentation.discover.tooltip'.tr(),
          child: TextButton.icon(
              onPressed: vm.canDiscover ? () => DocumentationDialogs.discover(context, vm) : null,
              icon: Icon(Icons.travel_explore),
              label: Text('documentation.discover.button'.tr())),
        ),
        IconButton(
            onPressed: vm.isDiscovering ? vm.stopDiscovery : null,
            icon: Icon(Icons.stop),
            tooltip: 'documentation.stopdiscovery.tooltip'.tr()),
        if (vm.isDiscovering) _buildDiscoveryStatus(vm),
      ]),
    );
  }

  Widget _buildCheck(DocumentationViewmodel vm) {
    return Row(children: [
      Tooltip(
        message: 'documentation.check.tooltip'.tr(),
        child: TextButton.icon(
            onPressed: vm.canCheck ? () => DocumentationDialogs.startCheck(context, vm) : null,
            icon: Icon(Icons.rule),
            label: Text('documentation.check.button'.tr())),
      ),
      IconButton(
          onPressed: vm.isChecking ? vm.stopCheck : null,
          icon: Icon(Icons.stop),
          tooltip: 'documentation.stopcheck.tooltip'.tr()),
      if (vm.isChecking) _buildCheckStatus(vm),
    ]);
  }

  Widget _buildCheckStatus(DocumentationViewmodel vm) {
    var theme = Theme.of(context);
    var elapsed = vm.checkElapsed;
    var clock =
        '${elapsed.inMinutes.toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    var label = switch (vm.checkState) {
      CheckState.connecting => 'documentation.discovery.connecting'.tr(),
      CheckState.reconnecting => 'documentation.discovery.reconnecting'.tr(args: ['${vm.checkReconnectAttempt}']),
      _ => 'documentation.check.running'.tr(args: [clock, DocFormat.count(vm.checkMessages)]),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        Text(label, style: theme.textTheme.bodyMedium!.copyWith(fontFeatures: [FontFeature.tabularFigures()])),
        for (var severity in FindingSeverity.values) ...[
          SizedBox(width: 12),
          Icon(FindingsPanel.iconOf(severity), size: 18, color: FindingsPanel.colorOf(context, severity)),
          SizedBox(width: 4),
          Text('${vm.findingCount(severity)}', style: theme.textTheme.bodyMedium),
        ],
      ]),
    );
  }

  Widget _buildDiscoveryStatus(DocumentationViewmodel vm) {
    var theme = Theme.of(context);
    var elapsed = vm.discoveryElapsed;
    var clock =
        '${elapsed.inMinutes.toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    var label = switch (vm.discoveryState) {
      DiscoveryState.connecting => 'documentation.discovery.connecting'.tr(),
      DiscoveryState.reconnecting =>
        'documentation.discovery.reconnecting'.tr(args: ['${vm.discoveryReconnectAttempt}']),
      _ => 'documentation.discovery.running'.tr(args: [
          clock,
          DocFormat.count(vm.discoveryMessages),
          DocFormat.count(vm.discoveryTopics),
          DocFormat.count(vm.discoveryNewTopics)
        ]),
    };
    var progress = vm.discoveryProgress;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        Text(label, style: theme.textTheme.bodyMedium!.copyWith(fontFeatures: [FontFeature.tabularFigures()])),
        if (progress != null) ...[
          SizedBox(width: 12),
          SizedBox(width: 80, child: LinearProgressIndicator(value: progress)),
        ],
      ]),
    );
  }
}
