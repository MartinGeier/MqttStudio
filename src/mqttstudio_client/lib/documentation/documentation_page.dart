import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/documentation/documentation_viewmodel.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/widgets/doc_overview.dart';
import 'package:mqttstudio/documentation/widgets/doc_tree.dart';
import 'package:mqttstudio/documentation/widgets/documentation_command_bar.dart';
import 'package:mqttstudio/documentation/widgets/documentation_dialogs.dart';
import 'package:mqttstudio/documentation/widgets/findings_panel.dart';
import 'package:mqttstudio/documentation/widgets/observed_panel.dart';
import 'package:mqttstudio/documentation/widgets/topic_doc_editor.dart';
import 'package:provider/provider.dart';

// The DOCUMENTATION tab: documents the topics of the project's broker (doc/documentation-design.md)
class DocumentationPage extends StatefulWidget {
  const DocumentationPage({Key? key}) : super(key: key);

  @override
  State<DocumentationPage> createState() => _DocumentationPageState();
}

class _DocumentationPageState extends State<DocumentationPage> {
  late final DocumentationViewmodel _viewmodel;

  @override
  void initState() {
    super.initState();
    _viewmodel = DocumentationViewmodel()
      ..onDiscoveryResult = (result) {
        if (mounted) {
          DocumentationDialogs.review(context, _viewmodel, result);
        }
      }
      ..onDiscoveryError = (message) {
        if (mounted) {
          DocumentationDialogs.discoveryError(context, message);
        }
      }
      ..onCheckError = (message) {
        if (mounted) {
          DocumentationDialogs.discoveryError(context, message);
        }
      }
      ..onDiscoverRequested = (recordingId) {
        if (mounted && _viewmodel.canDiscover) {
          DocumentationDialogs.discover(context, _viewmodel,
              source: DiscoverySource.recording, recordingId: recordingId);
        }
      };
  }

  @override
  void dispose() {
    _viewmodel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: _viewmodel,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DocumentationCommandBar(),
          Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DocTree(),
            Expanded(
              child: Consumer<DocumentationViewmodel>(
                builder: (context, vm, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: _buildEditor(context, vm)),
                      _buildObserved(vm),
                    ]),
                  ),
                  // the findings of the running or last check, under the editor
                  if (vm.isProjectOpen && vm.findings != null) FindingsPanel(),
                ]),
              ),
            )
          ]))
        ]));
  }

  Widget _buildEditor(BuildContext context, DocumentationViewmodel vm) {
    if (!vm.isProjectOpen) {
      var theme = Theme.of(context);
      return Center(
          child: Text('documentation.noproject.watermark'.tr(),
              style: theme.textTheme.headlineMedium!.copyWith(color: theme.dividerColor)));
    }
    // a new editor gets new form fields
    if (vm.editor != null) {
      return KeyedSubtree(key: ObjectKey(vm.editor), child: TopicDocEditor());
    }
    return KeyedSubtree(key: ObjectKey(vm.rootEditor), child: DocOverview());
  }

  Widget _buildObserved(DocumentationViewmodel vm) {
    var observed = vm.selectedEntry?.node?.observed;
    if (!vm.isProjectOpen || observed == null || !vm.isObservedPanelOpen) {
      return SizedBox.shrink();
    }
    return ObservedPanel(observed: observed);
  }
}
