import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/playback_options_viewmodel.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/widgets/recorder_format.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// The playback options of a recording: speed, range, gaps, topic remapping, retain and QoS. Returns the
// PlaybackOptions or null.
class PlaybackOptionsDialog extends StatelessWidget {
  final RecordingInfo recording;
  final PlaybackOptions options;
  final double maxRate;

  const PlaybackOptionsDialog({Key? key, required this.recording, required this.options, required this.maxRate})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PlaybackOptionsViewmodel>(
      create: (_) => PlaybackOptionsViewmodel(recording, options, maxRate: maxRate),
      child: Consumer<PlaybackOptionsViewmodel>(builder: (context, vm, _) {
        var theme = Theme.of(context);
        return SimpleDialog(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('playbackoptions.title'.tr()),
            SizedBox(height: 4),
            Text(recording.name, style: theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor)),
          ]),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 640, maxWidth: 640),
              child: ReactiveForm(
                formGroup: vm.form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _buildSpeedRow(vm),
                  _buildRangeRow(vm),
                  _buildSectionLabel(context, 'playbackoptions.remapping.label'),
                  _buildRemaps(context, vm),
                  _buildRetainRow(),
                  CheckboxField(
                      formControlName: PlaybackOptionsViewmodel.propertiesField,
                      form: vm.form,
                      label: 'playbackoptions.properties.label'.tr()),
                  _buildEstimate(context, vm),
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

  Widget _buildSectionLabel(BuildContext context, String key) {
    var theme = Theme.of(context);
    return Padding(
      // the 48 px button below brings its own space
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(key.tr(), style: theme.textTheme.titleMedium!.copyWith(color: Colors.black87)),
    );
  }

  Widget _buildSpeedRow(PlaybackOptionsViewmodel vm) {
    return SrxFormRow(alignment: CrossAxisAlignment.center, children: [
      Expanded(
        flex: 2,
        child: ReactiveDropdownField<double>(
          formControlName: PlaybackOptionsViewmodel.speedField,
          autofocus: true,
          decoration:
              InputDecoration(border: OutlineInputBorder(), labelText: 'playbackoptions.speed.label'.tr(), isDense: true),
          items: [
            for (var speed in PlaybackOptions.speeds) DropdownMenuItem(value: speed, child: Text(RecorderFormat.speed(speed)))
          ],
        ),
      ),
      SizedBox(width: 16),
      Expanded(
          flex: 3,
          child: CheckboxField(
              formControlName: PlaybackOptionsViewmodel.loopField, form: vm.form, label: 'playbackoptions.loop.label'.tr())),
    ]);
  }

  Widget _buildRangeRow(PlaybackOptionsViewmodel vm) {
    Widget field(String name, String labelKey, String? helperKey) => Expanded(
          child: ReactiveTextField<String>(
            formControlName: name,
            decoration: InputDecoration(
                border: OutlineInputBorder(), labelText: labelKey.tr(), helperText: helperKey?.tr(), isDense: true),
            validationMessages: {
              'duration': (_) => 'playbackoptions.duration.error'.tr(),
              'range': (_) => 'playbackoptions.range.error'.tr(),
            },
            onSubmitted: (_) => _onApplyPressed(vm),
          ),
        );
    return SrxFormRow(children: [
      field(PlaybackOptionsViewmodel.fromField, 'playbackoptions.from.label', 'playbackoptions.offset.helper'),
      SizedBox(width: 16),
      field(PlaybackOptionsViewmodel.toField, 'playbackoptions.to.label', 'playbackoptions.offset.helper'),
      SizedBox(width: 16),
      field(PlaybackOptionsViewmodel.gapsField, 'playbackoptions.gaps.label', 'playbackoptions.gaps.helper'),
    ]);
  }

  Widget _buildRemaps(BuildContext context, PlaybackOptionsViewmodel vm) {
    var theme = Theme.of(context);
    var preview = vm.remapPreview;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // room for the floating label of the first field
      if (vm.remaps.controls.isNotEmpty) SizedBox(height: 12),
      for (var i = 0; i < vm.remaps.controls.length; i++) _buildRemapRow(vm, vm.remaps.controls[i] as FormGroup, i),
      Row(children: [
        TextButton.icon(
            style: TextButton.styleFrom(minimumSize: Size(0, 48)),
            onPressed: vm.addRemap,
            icon: Icon(Icons.add),
            label: Text('playbackoptions.addremap.button'.tr())),
        SizedBox(width: 16),
        if (preview != null)
          Expanded(
            child: Text('${preview.$1} → ${preview.$2}',
                overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor)),
          ),
      ]),
      SizedBox(height: 16),
    ]);
  }

  Widget _buildRemapRow(PlaybackOptionsViewmodel vm, FormGroup group, int index) {
    Widget field(String name, String labelKey) => Expanded(
          child: ReactiveTextField<String>(
            formControl: group.control(name) as FormControl<String>,
            decoration: InputDecoration(border: OutlineInputBorder(), labelText: labelKey.tr(), isDense: true),
            validationMessages: {'wildcard': (_) => 'playbackoptions.remap.wildcard.error'.tr()},
          ),
        );
    return SrxFormRow(alignment: CrossAxisAlignment.center, children: [
      field(PlaybackOptionsViewmodel.remapFromField, 'playbackoptions.remapfrom.label'),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward)),
      field(PlaybackOptionsViewmodel.remapToField, 'playbackoptions.remapto.label'),
      IconButton(
          onPressed: () => vm.removeRemap(index),
          tooltip: 'playbackoptions.removeremap.tooltip'.tr(),
          icon: Icon(Icons.close)),
    ]);
  }

  Widget _buildRetainRow() {
    InputDecoration decoration(String key) =>
        InputDecoration(border: OutlineInputBorder(), labelText: key.tr(), isDense: true);
    return SrxFormRow(children: [
      Expanded(
        flex: 3,
        child: ReactiveDropdownField<RetainedSnapshotMode>(
          formControlName: PlaybackOptionsViewmodel.snapshotField,
          decoration: decoration('playbackoptions.snapshot.label'),
          items: [
            for (var mode in RetainedSnapshotMode.values)
              DropdownMenuItem(value: mode, child: Text('playbackoptions.snapshot.${mode.name}'.tr()))
          ],
        ),
      ),
      SizedBox(width: 16),
      Expanded(
        flex: 2,
        child: ReactiveDropdownField<RetainOverride>(
          formControlName: PlaybackOptionsViewmodel.retainField,
          decoration: decoration('playbackoptions.retain.label'),
          items: [
            for (var mode in RetainOverride.values)
              DropdownMenuItem(value: mode, child: Text('playbackoptions.retain.${mode.name}'.tr()))
          ],
        ),
      ),
      SizedBox(width: 16),
      Expanded(
        flex: 2,
        child: ReactiveDropdownField<int>(
          formControlName: PlaybackOptionsViewmodel.qosField,
          decoration: decoration('playbackoptions.qos.label'),
          items: [
            DropdownMenuItem(value: PlaybackOptionsViewmodel.qosAsRecorded, child: Text('playbackoptions.asrecorded'.tr())),
            for (var qos in [MqttQos.atMostOnce, MqttQos.atLeastOnce, MqttQos.exactlyOnce])
              DropdownMenuItem(value: qos.index, child: Text(qos.toString().tr())),
          ],
        ),
      ),
    ]);
  }

  Widget _buildEstimate(BuildContext context, PlaybackOptionsViewmodel vm) {
    var theme = Theme.of(context);
    var estimate = vm.estimate;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Icon(Icons.speed, size: 20, color: theme.unselectedWidgetColor),
        SizedBox(width: 8),
        Text('playbackoptions.estimate.label'.tr(args: [RecorderFormat.rate(estimate.rate), RecorderFormat.rate(estimate.peak)]),
            style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black87)),
      ]),
    );
  }

  Widget _buildActions(PlaybackOptionsViewmodel vm) {
    return SrxFormRow(alignment: CrossAxisAlignment.center, children: [
      Spacer(flex: 1),
      Expanded(
          flex: 5,
          child: OutlinedButton(
              onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('srx.common.cancel'.tr()))),
      SizedBox(width: 16),
      Expanded(
          flex: 5, child: ElevatedButton(onPressed: () => _onApplyPressed(vm), child: Text('playbackoptions.apply.button'.tr()))),
    ]);
  }

  void _onApplyPressed(PlaybackOptionsViewmodel vm) {
    var options = vm.save();
    if (options != null) {
      GetIt.I.get<SrxNavigationService>().pop(options);
    }
  }
}
