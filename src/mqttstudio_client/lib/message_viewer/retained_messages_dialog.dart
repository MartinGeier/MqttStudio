import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/utils/payload_decoder.dart';
import 'package:mqttstudio/common/widgets/payload_diff_view.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/message_viewer/retained_messages_viewmodel.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

Future<void> showRetainedMessagesDialog(BuildContext context, {String filter = '#'}) => showDialog(
    context: context,
    builder: (_) => SrxTheme(data: CustomTheme.srxTheme, child: RetainedMessagesDialog(filter: filter)));

// Lists the retained messages below a topic filter, scanned when the dialog opens, and clears the selected ones
class RetainedMessagesDialog extends StatefulWidget {
  final String filter;
  // replaces the broker connection in tests
  final MqttAdapter Function()? connectionFactory;

  const RetainedMessagesDialog({Key? key, this.filter = '#', this.connectionFactory}) : super(key: key);

  @override
  State<RetainedMessagesDialog> createState() => _RetainedMessagesDialogState();
}

class _RetainedMessagesDialogState extends State<RetainedMessagesDialog> {
  static const int _previewLength = 120;

  late final RetainedMessagesViewmodel _viewmodel =
      RetainedMessagesViewmodel(filter: widget.filter, connectionFactory: widget.connectionFactory);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async => await _viewmodel.scan());
  }

  @override
  void dispose() {
    _viewmodel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RetainedMessagesViewmodel>.value(
      value: _viewmodel,
      child: Consumer<RetainedMessagesViewmodel>(builder: (context, vm, child) {
        return SimpleDialog(title: Text('retaineddialog.title'.tr()), contentPadding: EdgeInsets.all(16), children: [
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: 760, maxWidth: 760),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildFilterRow(vm),
              SizedBox(height: 8),
              _buildStatus(context, vm),
              SizedBox(height: 8),
              SizedBox(height: 360, child: _buildList(context, vm)),
              SizedBox(height: 16),
              _buildActions(context, vm),
            ]),
          )
        ]);
      }),
    );
  }

  Widget _buildFilterRow(RetainedMessagesViewmodel vm) {
    return ReactiveForm(
      formGroup: vm.form,
      child: SrxFormRow(children: [
        Expanded(
          flex: 8,
          child: ReactiveTextField<String>(
            formControlName: RetainedMessagesViewmodel.filterField,
            autofocus: true,
            decoration:
                InputDecoration(border: OutlineInputBorder(), labelText: 'retaineddialog.filter.label'.tr(), isDense: true),
            validationMessages: {
              ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
              'filter.shared': (_) => 'retaineddialog.filter.shared.error'.tr(),
              'filter.wildcardPosition': (_) => 'recorddialog.filter.wildcard.error'.tr(),
              'filter.hasNull': (_) => 'recorddialog.filter.wildcard.error'.tr(),
              'filter.empty': (_) => 'srx.common.fieldrequired'.tr(),
            },
            onSubmitted: (_) => vm.scan(),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
            flex: 3,
            child: ElevatedButton(
                onPressed: vm.isBusy ? null : () => vm.scan(), child: Text('retaineddialog.scan.button'.tr()))),
      ]),
    );
  }

  Widget _buildStatus(BuildContext context, RetainedMessagesViewmodel vm) {
    var style = Theme.of(context).textTheme.bodyMedium;
    switch (vm.state) {
      case RetainedScanState.idle:
        return Text('', style: style);
      case RetainedScanState.connecting:
        return Text('retaineddialog.connecting'.tr(), style: style);
      case RetainedScanState.scanning:
        return Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('retaineddialog.scanning'.plural(vm.found), style: style),
        ]);
      case RetainedScanState.failed:
        return Text('retaineddialog.failed'.tr(args: [vm.error ?? '']),
            style: style!.copyWith(color: Theme.of(context).colorScheme.error));
      case RetainedScanState.done:
        var found = vm.messages.isEmpty
            ? 'retaineddialog.none'.tr(args: [vm.scannedFilter])
            : 'retaineddialog.found'.plural(vm.messages.length, namedArgs: {'filter': vm.scannedFilter});
        return Text(vm.cleared == 0 ? found : '$found ${'retaineddialog.cleared'.plural(vm.cleared)}', style: style);
    }
  }

  Widget _buildList(BuildContext context, RetainedMessagesViewmodel vm) {
    var header = Theme.of(context).textTheme.titleSmall;
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor)),
      child: Column(children: [
        Row(children: [
          Checkbox(
              value: vm.allSelected,
              onChanged: vm.messages.isEmpty || vm.isBusy ? null : (value) => vm.selectAll(value ?? false)),
          Expanded(flex: 5, child: Text('retaineddialog.topic.label'.tr(), style: header)),
          SizedBox(width: 12),
          Expanded(flex: 5, child: Text('retaineddialog.payload.label'.tr(), style: header)),
          SizedBox(width: 72, child: Text('retaineddialog.size.label'.tr(), style: header, textAlign: TextAlign.right)),
          SizedBox(width: 12),
        ]),
        Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: vm.messages.length,
            itemBuilder: (context, index) => _buildRow(context, vm, vm.messages[index]),
          ),
        ),
      ]),
    );
  }

  Widget _buildRow(BuildContext context, RetainedMessagesViewmodel vm, ReceivedMqttMessage message) {
    return InkWell(
      onTap: vm.isBusy ? null : () => vm.toggle(message.topicName),
      child: Row(children: [
        Checkbox(
            value: vm.isSelected(message.topicName),
            onChanged: vm.isBusy ? null : (_) => vm.toggle(message.topicName)),
        Expanded(
            flex: 5,
            child: Text(message.topicName, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium)),
        SizedBox(width: 12),
        Expanded(
            flex: 5,
            child: Text(_preview(message), maxLines: 1, overflow: TextOverflow.ellipsis, style: diffTextStyle)),
        SizedBox(width: 72, child: Text('${message.payload.length} B', textAlign: TextAlign.right)),
        SizedBox(width: 12),
      ]),
    );
  }

  static String _preview(ReceivedMqttMessage message) {
    var payload = message.payload;
    if (!PayloadDecoding.isUtf8(payload)) {
      return payload.take(24).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
    }
    var text = utf8.decode(payload).replaceAll(RegExp(r'\s+'), ' ');
    return text.length > _previewLength ? text.substring(0, _previewLength) : text;
  }

  Widget _buildActions(BuildContext context, RetainedMessagesViewmodel vm) {
    return SrxFormRow(alignment: CrossAxisAlignment.center, children: [
      Spacer(flex: 1),
      Expanded(
          flex: 5,
          child: OutlinedButton(
              onPressed: () => GetIt.I.get<SrxNavigationService>().pop(), child: Text('retaineddialog.close.button'.tr()))),
      SizedBox(width: 16),
      Expanded(
          flex: 5,
          child: ElevatedButton(
              onPressed: vm.selectedCount == 0 || vm.isBusy ? null : () => _clearSelected(context, vm),
              child: Text('retaineddialog.clear.button'.tr(args: ['${vm.selectedCount}'])))),
    ]);
  }

  Future<void> _clearSelected(BuildContext context, RetainedMessagesViewmodel vm) async {
    var confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => SrxTheme(
            data: CustomTheme.srxTheme,
            child: SrxDialog.yesNo(bodyText: 'retaineddialog.clear.confirm'.plural(vm.selectedCount))));
    if (confirmed == true) {
      vm.clearSelected();
    }
  }
}
