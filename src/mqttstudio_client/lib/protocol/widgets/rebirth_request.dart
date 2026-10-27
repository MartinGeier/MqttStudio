import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_commands.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Asks before sending rebirth requests to edge nodes, unless the user turned that off for the session (R1), then
// sends them and says so (doc/sparkplug-design.md §12.4)
class RebirthRequest {
  static const String _dontAskField = 'dontAsk';

  static Future<void> confirmAndSend(
    BuildContext context,
    MessageViewerViewmodel viewmodel,
    List<SparkplugEdgeNode> nodes,
  ) async {
    if (nodes.isEmpty || !viewmodel.canRequestRebirth) {
      return;
    }
    if (viewmodel.confirmRebirth) {
      var form = FormGroup({_dontAskField: FormControl<bool>(value: false)});
      var confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => SrxTheme(
          data: CustomTheme.srxTheme,
          child: SrxDialog.yesNo(content: _buildContent(form, nodes)),
        ),
      );
      if (confirmed != true || !context.mounted) {
        return;
      }
      if (form.control(_dontAskField).value == true) {
        viewmodel.confirmRebirth = false;
      }
    }
    viewmodel.requestRebirth(nodes);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nodes.length == 1
              ? 'sparkplug.rebirth.sent.one'.tr(args: [nodes.single.edgeNode])
              : 'sparkplug.rebirth.sent.other'.tr(args: ['${nodes.length}']),
        ),
      ),
    );
  }

  static Widget _buildContent(FormGroup form, List<SparkplugEdgeNode> nodes) {
    var groups = nodes.map((node) => node.group).toSet().join(', ');
    var text = nodes.length == 1
        ? 'sparkplug.rebirth.confirm.one'.tr(namedArgs: {'node': nodes.single.edgeNode, 'group': groups})
        : 'sparkplug.rebirth.confirm.other'.tr(namedArgs: {'count': '${nodes.length}', 'group': groups});
    return ReactiveForm(
      formGroup: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          SizedBox(height: 12),
          CheckboxField(formControlName: _dontAskField, form: form, label: 'sparkplug.rebirth.dontask.label'.tr()),
        ],
      ),
    );
  }
}
