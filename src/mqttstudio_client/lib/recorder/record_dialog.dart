import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/mqtt_settings.dart';
import 'package:mqttstudio/recorder/model/recorder_config.dart';
import 'package:mqttstudio/recorder/record_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Starts a recording: name, topic filters and when to stop. Returns the RecorderConfig or null.
class RecordDialog extends StatelessWidget {
  final RecorderConfig config;
  final MqttSettings settings;
  // offered in the dropdown of each filter field: the subscribed topics and the last filters
  final List<String> suggestions;

  const RecordDialog({Key? key, required this.config, required this.settings, this.suggestions = const []})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RecordViewmodel>(
      create: (_) => RecordViewmodel(config, settings),
      child: Consumer<RecordViewmodel>(builder: (context, vm, _) {
        var theme = Theme.of(context);
        return SimpleDialog(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('recorddialog.title'.tr()),
            SizedBox(height: 4),
            Text('recorddialog.subtitle'.tr(args: [vm.broker, settings.protocolVersion.displayName]),
                style: theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor)),
          ]),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 720, maxWidth: 720),
              child: ReactiveForm(
                formGroup: vm.form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SrxFormRow(children: [Expanded(flex: 2, child: _buildNameField(vm)), SizedBox(width: 16), Expanded(child: _buildMode(vm))]),
                  _buildSectionLabel(context, 'recorddialog.filters.label'),
                  _buildFilters(context, vm),
                  _buildHints(context, vm),
                  if (!vm.isFlightRecorder) ...[
                    _buildSectionLabel(context, 'recorddialog.startstop.label'),
                    _buildTriggerFields(vm),
                    _buildStopFields(vm),
                  ],
                  if (vm.isFlightRecorder) ...[
                    _buildSectionLabel(context, 'recorddialog.flight.label'),
                    _buildFlightFields(context, vm),
                  ],
                  _buildSectionLabel(context, 'recorddialog.options.label'),
                  _buildOptions(vm),
                  SizedBox(height: 16),
                  _buildActions(context, vm),
                ]),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildSectionLabel(BuildContext context, String key) {
    var theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(key.tr(), style: theme.textTheme.titleMedium!.copyWith(color: Colors.black87)),
    );
  }

  Widget _buildNameField(RecordViewmodel vm) {
    return ReactiveTextField<String>(
      formControlName: RecordViewmodel.nameField,
      autofocus: true,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'recorddialog.name.label'.tr(), isDense: true),
      validationMessages: {
        ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
        ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr(),
      },
      onSubmitted: (_) => _onRecordPressed(vm),
    );
  }

  Widget _buildMode(RecordViewmodel vm) {
    return ReactiveDropdownField<RecorderMode>(
      formControlName: RecordViewmodel.modeField,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'recorddialog.mode.label'.tr(), isDense: true),
      onChanged: (control) => vm.setMode(control.value ?? RecorderMode.normal),
      items: [
        DropdownMenuItem(value: RecorderMode.normal, child: Text('recorddialog.mode.normal'.tr())),
        DropdownMenuItem(value: RecorderMode.flightRecorder, child: Text('recorddialog.mode.flight'.tr())),
      ],
    );
  }

  Widget _conditionField(RecordViewmodel vm, String name, String labelKey) {
    return ReactiveTextField<String>(
      formControlName: name,
      decoration: InputDecoration(
          border: OutlineInputBorder(),
          labelText: labelKey.tr(),
          helperText: 'recorddialog.condition.helper'.tr(),
          helperMaxLines: 2,
          isDense: true),
      validationMessages: {'condition': (_) => 'recorddialog.condition.error'.tr()},
      onSubmitted: (_) => _onRecordPressed(vm),
    );
  }

  Widget _durationField(RecordViewmodel vm, String name, String labelKey, String helperKey) {
    return ReactiveTextField<String>(
      formControlName: name,
      decoration: InputDecoration(
          border: OutlineInputBorder(), labelText: labelKey.tr(), helperText: helperKey.tr(), isDense: true),
      validationMessages: {
        ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
        'duration': (_) => 'recorddialog.duration.error'.tr(),
        'preroll': (_) => 'recorddialog.preroll.error'.tr(),
      },
      onSubmitted: (_) => _onRecordPressed(vm),
    );
  }

  Widget _buildTriggerFields(RecordViewmodel vm) {
    return Column(children: [
      SrxFormRow(children: [
        Expanded(flex: 3, child: _conditionField(vm, RecordViewmodel.startWhenField, 'recorddialog.startwhen.label')),
        SizedBox(width: 16),
        Expanded(child: _durationField(vm, RecordViewmodel.preRollField, 'recorddialog.preroll.label', 'recorddialog.preroll.helper')),
      ]),
      SrxFormRow(children: [
        Expanded(flex: 3, child: _conditionField(vm, RecordViewmodel.stopWhenField, 'recorddialog.stopwhen.label')),
        SizedBox(width: 16),
        Expanded(child: _durationField(vm, RecordViewmodel.postRollField, 'recorddialog.postroll.label', 'recorddialog.postroll.helper')),
      ]),
    ]);
  }

  Widget _buildFlightFields(BuildContext context, RecordViewmodel vm) {
    var theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('recorddialog.flight.hint'.tr(), style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black87)),
      ),
      SrxFormRow(children: [
        Expanded(child: _durationField(vm, RecordViewmodel.windowField, 'recorddialog.window.label', 'recorddialog.window.helper')),
        SizedBox(width: 16),
        Expanded(child: _intField(vm, RecordViewmodel.memoryField, 'recorddialog.memory.label', null)),
        SizedBox(width: 16),
        Expanded(
            child: _durationField(
                vm, RecordViewmodel.savePostRollField, 'recorddialog.savepostroll.label', 'recorddialog.savepostroll.helper')),
        SizedBox(width: 16),
        Expanded(child: _intField(vm, RecordViewmodel.maxSavesField, 'recorddialog.maxsaves.label', null)),
      ]),
      SrxFormRow(children: [Expanded(child: _conditionField(vm, RecordViewmodel.saveWhenField, 'recorddialog.savewhen.label'))]),
    ]);
  }

  Widget _buildFilters(BuildContext context, RecordViewmodel vm) {
    var theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < vm.filters.controls.length; i++) _buildFilterRow(vm, vm.filters.controls[i] as FormGroup, i),
      // the last filter row keeps room for a validation message; the button moves up into it
      Transform.translate(
        offset: Offset(0, -12),
        child: Row(children: [
          TextButton.icon(
              style: TextButton.styleFrom(minimumSize: Size(0, 36), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onPressed: vm.addFilter,
              icon: Icon(Icons.add),
              label: Text('recorddialog.addfilter.button'.tr())),
          if (vm.filters.hasErrors && vm.filters.errors.containsKey('noinclude'))
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text('recorddialog.noinclude.error'.tr(),
                  style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error)),
            ),
        ]),
      ),
    ]);
  }

  Widget _buildFilterRow(RecordViewmodel vm, FormGroup group, int index) {
    return SrxFormRow(children: [
      Expanded(
        flex: 6,
        child: ReactiveTextField<String>(
          formControl: group.control(RecordViewmodel.filterField) as FormControl<String>,
          decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'recorddialog.filter.label'.tr(),
              isDense: true,
              suffixIcon: _buildSuggestions(group.control(RecordViewmodel.filterField) as FormControl<String>)),
          validationMessages: {
            ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
            'filter.shared': (_) => 'recorddialog.filter.shared.error'.tr(),
            'filter.wildcardPosition': (_) => 'recorddialog.filter.wildcard.error'.tr(),
            'filter.hasNull': (_) => 'recorddialog.filter.wildcard.error'.tr(),
            'filter.empty': (_) => 'srx.common.fieldrequired'.tr(),
          },
          onSubmitted: (_) => _onRecordPressed(vm),
        ),
      ),
      SizedBox(width: 16),
      Expanded(
        flex: 3,
        child: ReactiveDropdownField<MqttQos>(
          formControl: group.control(RecordViewmodel.qosField) as FormControl<MqttQos>,
          decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'recorddialog.qos.label'.tr(), isDense: true),
          items: [
            for (var qos in [MqttQos.atMostOnce, MqttQos.atLeastOnce, MqttQos.exactlyOnce])
              DropdownMenuItem(value: qos, child: Text(qos.toString().tr()))
          ],
        ),
      ),
      SizedBox(width: 16),
      Expanded(
        flex: 3,
        child: ReactiveDropdownField<bool>(
          formControl: group.control(RecordViewmodel.excludeField) as FormControl<bool>,
          decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'recorddialog.type.label'.tr(), isDense: true),
          items: [
            DropdownMenuItem(value: false, child: Text('recorddialog.include.label'.tr())),
            DropdownMenuItem(value: true, child: Text('recorddialog.exclude.label'.tr())),
          ],
        ),
      ),
      IconButton(
          onPressed: vm.filters.controls.length > 1 ? () => vm.removeFilter(index) : null,
          tooltip: 'recorddialog.removefilter.tooltip'.tr(),
          icon: Icon(Icons.close)),
    ]);
  }

  Widget? _buildSuggestions(FormControl<String> control) {
    if (suggestions.isEmpty) {
      return null;
    }
    return PopupMenuButton<String>(
      icon: Icon(Icons.arrow_drop_down),
      tooltip: 'recorddialog.suggestions.tooltip'.tr(),
      onSelected: (filter) => control.value = filter,
      itemBuilder: (_) => [for (var filter in suggestions) PopupMenuItem(value: filter, child: Text(filter))],
    );
  }

  Widget _buildHints(BuildContext context, RecordViewmodel vm) {
    var hints = [
      for (var covered in vm.coveredFilters)
        'recorddialog.covered.hint'.tr(args: [covered.filter.filter, covered.coveredBy.filter]),
      if (vm.hasRootWildcard) 'recorddialog.systopics.hint'.tr(),
    ];
    if (hints.isEmpty) {
      return SizedBox.shrink();
    }
    var theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var hint in hints)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 20, color: theme.unselectedWidgetColor),
              SizedBox(width: 8),
              Expanded(child: Text(hint, style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black87))),
            ]),
          ),
      ]),
    );
  }

  Widget _buildStopFields(RecordViewmodel vm) {
    return SrxFormRow(children: [
      Expanded(
        child: ReactiveTextField<String>(
          formControlName: RecordViewmodel.durationField,
          decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'recorddialog.duration.label'.tr(),
              helperText: 'recorddialog.duration.helper'.tr(),
              isDense: true),
          validationMessages: {'duration': (_) => 'recorddialog.duration.error'.tr()},
          onSubmitted: (_) => _onRecordPressed(vm),
        ),
      ),
      SizedBox(width: 16),
      Expanded(child: _intField(vm, RecordViewmodel.maxMessagesField, 'recorddialog.maxmessages.label', null)),
      SizedBox(width: 16),
      Expanded(child: _intField(vm, RecordViewmodel.maxSizeField, 'recorddialog.maxsize.label', null)),
    ]);
  }

  // top aligned: centred, the field's helper line would be cut at the bottom of the row
  Widget _buildOptions(RecordViewmodel vm) {
    return SrxFormRow(children: [
      Expanded(
          child: _intField(
              vm, RecordViewmodel.maxPayloadField, 'recorddialog.maxpayload.label', 'recorddialog.maxpayload.helper')),
      SizedBox(width: 16),
      Expanded(
          flex: 2,
          child: CheckboxField(
              formControlName: RecordViewmodel.snapshotField, form: vm.form, label: 'recorddialog.snapshot.label'.tr())),
    ]);
  }

  Widget _intField(RecordViewmodel vm, String name, String labelKey, String? helperKey) {
    return ReactiveTextField<int>(
      formControlName: name,
      decoration: InputDecoration(
          border: OutlineInputBorder(), labelText: labelKey.tr(), helperText: helperKey?.tr(), isDense: true),
      validationMessages: {
        ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
        ValidationMessage.min: (_) => 'recorddialog.value.toosmall.error'.tr(),
        ValidationMessage.number: (_) => 'recorddialog.value.number.error'.tr(),
      },
      onSubmitted: (_) => _onRecordPressed(vm),
    );
  }

  Widget _buildActions(BuildContext context, RecordViewmodel vm) {
    return SrxFormRow(alignment: CrossAxisAlignment.center, children: [
      Spacer(flex: 1),
      Expanded(
          flex: 5,
          child: OutlinedButton(
              onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('srx.common.cancel'.tr()))),
      SizedBox(width: 16),
      Expanded(
          flex: 5,
          child: ElevatedButton(onPressed: () => _onRecordPressed(vm), child: Text('recorddialog.record.button'.tr()))),
    ]);
  }

  void _onRecordPressed(RecordViewmodel vm) {
    var config = vm.save();
    if (config != null) {
      GetIt.I.get<SrxNavigationService>().pop(config);
    }
  }
}
