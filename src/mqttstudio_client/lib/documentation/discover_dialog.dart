import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/documentation/discover_viewmodel.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/widgets/doc_format.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

typedef V = DiscoverViewmodel;

// Starts a discovery: where the messages come from, which topics, when it stops (doc/documentation-design.md §12.5).
// Returns a DiscoverRequest or null.
class DiscoverDialog extends StatefulWidget {
  final DiscoverySource source;
  final String? recordingId;

  const DiscoverDialog({Key? key, this.source = DiscoverySource.live, this.recordingId}) : super(key: key);

  @override
  State<DiscoverDialog> createState() => _DiscoverDialogState();
}

class _DiscoverDialogState extends State<DiscoverDialog> {
  late final DiscoverViewmodel _viewmodel;

  @override
  void initState() {
    super.initState();
    _viewmodel = DiscoverViewmodel(source: widget.source, recordingId: widget.recordingId);
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
      child: Consumer<DiscoverViewmodel>(builder: (context, vm, _) {
        return SimpleDialog(
          title: Text('discoverdialog.title'.tr()),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 640, maxWidth: 640),
              child: ReactiveForm(
                formGroup: vm.form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _buildSources(vm),
                  SizedBox(height: 16),
                  _buildSource(context, vm),
                  SizedBox(height: 16),
                  _buildLabel(context, 'discoverdialog.filters.label'),
                  SizedBox(height: 8),
                  _buildFilters(context, vm),
                  SizedBox(height: 8),
                  _buildStop(vm),
                  SizedBox(height: 8),
                  _buildOptions(vm),
                  SizedBox(height: 8),
                  _buildNote(context, vm),
                  SizedBox(height: 16),
                  _buildActions(vm),
                ]),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildLabel(BuildContext context, String key) =>
      Text(key.tr(), style: Theme.of(context).textTheme.bodySmall!.copyWith(color: Theme.of(context).hintColor));

  Widget _buildSources(DiscoverViewmodel vm) {
    var sources = DiscoverySource.values;
    var icons = {
      DiscoverySource.live: Icons.dns,
      DiscoverySource.recording: Icons.history,
      DiscoverySource.buffer: Icons.view_agenda
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: ToggleButtons(
        borderRadius: BorderRadius.circular(4),
        constraints: BoxConstraints(minHeight: 40),
        isSelected: [for (var source in sources) vm.source == source],
        onPressed: (index) => vm.form.control(V.sourceField).value = sources[index],
        children: [
          for (var source in sources)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Icon(icons[source], size: 20),
                SizedBox(width: 8),
                Text('discoverdialog.source.${source.name}'.tr()),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _buildSource(BuildContext context, DiscoverViewmodel vm) {
    switch (vm.source) {
      case DiscoverySource.live:
        return InputDecorator(
            decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'discoverdialog.broker.label'.tr(),
                isDense: true,
                enabled: false),
            child: Text(vm.broker));
      case DiscoverySource.recording:
        return ReactiveDropdownField<String>(
          formControlName: V.recordingField,
          isExpanded: true,
          decoration: InputDecoration(
              border: OutlineInputBorder(), labelText: 'discoverdialog.recording.label'.tr(), isDense: true),
          validationMessages: {ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr()},
          items: [
            for (var info in vm.recordings)
              DropdownMenuItem(
                  value: info.id,
                  child: Text(
                      '${info.name} · ${DateFormat('dd.MM.yyyy HH:mm').format(info.header.startedAt.toLocal())}',
                      overflow: TextOverflow.ellipsis)),
          ],
        );
      case DiscoverySource.buffer:
        // a read-only field like the broker's, so the dialog keeps its height
        return InputDecorator(
            decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'discoverdialog.buffer.label'.tr(),
                isDense: true,
                enabled: false),
            child: Text('discoverdialog.buffer.value'.tr(args: [DocFormat.count(vm.bufferedMessages)])));
    }
  }

  Widget _buildFilters(BuildContext context, DiscoverViewmodel vm) {
    var theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < vm.filters.controls.length; i++) ...[
        _buildFilterRow(vm, vm.filters.controls[i] as FormGroup, i),
        SizedBox(height: 12),
      ],
      Row(children: [
        TextButton.icon(
            style: TextButton.styleFrom(minimumSize: Size(0, 36)),
            onPressed: vm.addFilter,
            icon: Icon(Icons.playlist_add),
            label: Text('recorddialog.addfilter.button'.tr())),
        if (vm.filters.hasErrors && vm.filters.errors.containsKey('noinclude'))
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text('recorddialog.noinclude.error'.tr(),
                style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error)),
          ),
      ]),
    ]);
  }

  Widget _buildFilterRow(DiscoverViewmodel vm, FormGroup group, int index) {
    return SrxFormRow(children: [
      Expanded(
        flex: 3,
        child: ReactiveDropdownField<bool>(
          formControl: group.control(V.excludeField) as FormControl<bool>,
          decoration:
              InputDecoration(border: OutlineInputBorder(), labelText: 'recorddialog.type.label'.tr(), isDense: true),
          items: [
            DropdownMenuItem(value: false, child: Text('recorddialog.include.label'.tr())),
            DropdownMenuItem(value: true, child: Text('recorddialog.exclude.label'.tr())),
          ],
        ),
      ),
      SizedBox(width: 16),
      Expanded(
        flex: 8,
        child: ReactiveTextField<String>(
          formControl: group.control(V.filterField) as FormControl<String>,
          autofocus: index == 0,
          decoration:
              InputDecoration(border: OutlineInputBorder(), labelText: 'recorddialog.filter.label'.tr(), isDense: true),
          validationMessages: {
            ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
            'filter.shared': (_) => 'recorddialog.filter.shared.error'.tr(),
            'filter.wildcardPosition': (_) => 'recorddialog.filter.wildcard.error'.tr(),
            'filter.hasNull': (_) => 'recorddialog.filter.wildcard.error'.tr(),
            'filter.empty': (_) => 'srx.common.fieldrequired'.tr(),
          },
          onSubmitted: (_) => _onDiscover(vm),
        ),
      ),
      IconButton(
          onPressed: vm.filters.controls.length > 1 ? () => vm.removeFilter(index) : null,
          tooltip: 'recorddialog.removefilter.tooltip'.tr(),
          icon: Icon(Icons.remove_circle_outline)),
    ]);
  }

  Widget _buildStop(DiscoverViewmodel vm) {
    return SrxFormRow(children: [
      Expanded(
        flex: 3,
        child: ReactiveDropdownField<DiscoveryStop>(
          formControlName: V.stopField,
          decoration:
              InputDecoration(border: OutlineInputBorder(), labelText: 'discoverdialog.stop.label'.tr(), isDense: true),
          items: [
            for (var stop in DiscoveryStop.values)
              DropdownMenuItem(value: stop, child: Text('discoverdialog.stop.${stop.name}'.tr())),
          ],
        ),
      ),
      SizedBox(width: 16),
      Expanded(
        flex: 2,
        child: switch (vm.stop) {
          DiscoveryStop.duration => _intField(V.durationField, 'discoverdialog.duration.label'),
          DiscoveryStop.messages => _intField(V.maxMessagesField, 'discoverdialog.maxmessages.label'),
          DiscoveryStop.manual => SizedBox.shrink(),
        },
      ),
      Spacer(flex: 3),
    ]);
  }

  Widget _intField(String name, String labelKey) {
    return ReactiveTextField<int>(
      formControlName: name,
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: labelKey.tr(), isDense: true),
      validationMessages: {
        ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
        ValidationMessage.min: (_) => 'discoverdialog.number.error'.tr(),
        ValidationMessage.max: (_) => 'discoverdialog.number.error'.tr(),
        ValidationMessage.number: (_) => 'discoverdialog.number.error'.tr(),
      },
      onSubmitted: (_) => _onDiscover(_viewmodel),
    );
  }

  Widget _buildOptions(DiscoverViewmodel vm) {
    Widget option(String name, String key) =>
        Expanded(child: CheckboxField(formControlName: name, form: vm.form, label: key.tr()));
    return Column(children: [
      Row(children: [
        option(V.detectTemplatesField, 'discoverdialog.detecttemplates.label'),
        option(V.inferSchemasField, 'discoverdialog.inferschemas.label'),
      ]),
      Row(children: [
        option(V.keepExamplesField, 'discoverdialog.keepexamples.label'),
        option(V.ignoreSysField, 'discoverdialog.ignoresys.label'),
      ]),
    ]);
  }

  Widget _buildNote(BuildContext context, DiscoverViewmodel vm) {
    var theme = Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.info_outline, size: 18, color: theme.hintColor),
      SizedBox(width: 8),
      Expanded(
          child: Text((vm.isLive ? 'discoverdialog.live.note' : 'discoverdialog.offline.note').tr(),
              style: theme.textTheme.bodySmall)),
    ]);
  }

  Widget _buildActions(DiscoverViewmodel vm) {
    return SrxFormRow(alignment: CrossAxisAlignment.center, children: [
      Spacer(flex: 1),
      Expanded(
          flex: 5,
          child: OutlinedButton(
              onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('srx.common.cancel'.tr()))),
      SizedBox(width: 16),
      Expanded(
          flex: 5,
          child: ElevatedButton(onPressed: () => _onDiscover(vm), child: Text('discoverdialog.discover.button'.tr()))),
    ]);
  }

  void _onDiscover(DiscoverViewmodel vm) {
    var request = vm.save();
    if (request != null) {
      GetIt.I.get<SrxNavigationService>().pop(request);
    }
  }
}
