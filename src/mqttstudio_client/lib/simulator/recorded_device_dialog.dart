import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/recorder/model/playback_options.dart';
import 'package:mqttstudio/recorder/playback_options_dialog.dart';
import 'package:mqttstudio/recorder/widgets/recorder_format.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/recorded_device_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Adds or edits a recorded device: the recording, its instances, the topics it plays and how. Returns the
// SimulatedDevice or null.
class RecordedDeviceDialog extends StatelessWidget {
  final SimulatedDevice? device;
  final Simulation simulation;

  const RecordedDeviceDialog({Key? key, this.device, required this.simulation}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RecordedDeviceViewmodel>(
      create: (_) => RecordedDeviceViewmodel(device, simulation),
      child: Consumer<RecordedDeviceViewmodel>(builder: (context, vm, _) {
        return SimpleDialog(
          title: Text((vm.isNew ? 'recordeddevice.add.title' : 'recordeddevice.edit.title').tr()),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 640, maxWidth: 640),
              child: ReactiveForm(
                formGroup: vm.form,
                child: vm.loading
                    ? Padding(padding: const EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                    : vm.recordings.isEmpty
                        ? _buildNoRecordings(context)
                        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            SrxFormRow(children: [Expanded(child: _buildRecordingField(vm))]),
                            SrxFormRow(children: [Expanded(child: _buildNameField(vm))]),
                            _buildInstancesRow(vm),
                            _buildTopics(context, vm),
                            _buildPlayback(context, vm),
                            _buildIssues(context, vm),
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

  Widget _buildNoRecordings(BuildContext context) {
    var theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('recordeddevice.norecordings.label'.tr(), style: theme.textTheme.bodyMedium),
      SizedBox(height: 24),
      Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
            onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('srx.common.cancel'.tr())),
      ),
    ]);
  }

  Widget _buildRecordingField(RecordedDeviceViewmodel vm) {
    return ReactiveDropdownField<String>(
      formControlName: RecordedDeviceViewmodel.recordingField,
      autofocus: true,
      decoration:
          InputDecoration(border: OutlineInputBorder(), labelText: 'recordeddevice.recording.label'.tr(), isDense: true),
      items: [
        for (var info in vm.recordings)
          DropdownMenuItem(
              value: info.id,
              child: Text(
                  '${info.name} · ${RecorderFormat.date(info.header.startedAt)} · ${RecorderFormat.duration(info.footer.duration)}',
                  overflow: TextOverflow.ellipsis)),
      ],
      validationMessages: {ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr()},
    );
  }

  Widget _buildNameField(RecordedDeviceViewmodel vm) {
    return ReactiveTextField<String>(
      formControlName: RecordedDeviceViewmodel.nameField,
      decoration:
          InputDecoration(border: OutlineInputBorder(), labelText: 'simulator.devicedialog.name.label'.tr(), isDense: true),
      validationMessages: {
        ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
        ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr(),
        'duplicate': (_) => 'simulator.issue.deviceNameDuplicate'.tr(),
      },
      onSubmitted: (_) => _onSavePressed(vm),
    );
  }

  Widget _buildInstancesRow(RecordedDeviceViewmodel vm) {
    Widget intField(String name, String labelKey) => ReactiveTextField<int>(
          formControlName: name,
          decoration: InputDecoration(border: OutlineInputBorder(), labelText: labelKey.tr(), isDense: true),
          validationMessages: {
            ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
            ValidationMessage.min: (_) => 'simulator.value.toosmall.error'.tr(),
            ValidationMessage.max: (_) => 'simulator.value.toolarge.error'.tr(),
            ValidationMessage.number: (_) => 'simulator.value.number.error'.tr(),
          },
          onSubmitted: (_) => _onSavePressed(vm),
        );
    return SrxFormRow(children: [
      Expanded(flex: 2, child: intField(RecordedDeviceViewmodel.instanceCountField, 'simulator.devicedialog.instances.label')),
      SizedBox(width: 16),
      Expanded(
          flex: 2, child: intField(RecordedDeviceViewmodel.firstInstanceField, 'simulator.devicedialog.firstinstance.label')),
      SizedBox(width: 16),
      Expanded(
        flex: 3,
        child: ReactiveDropdownField<InstanceStart>(
          formControlName: RecordedDeviceViewmodel.instanceStartField,
          decoration: InputDecoration(
              border: OutlineInputBorder(), labelText: 'recordeddevice.instancestart.label'.tr(), isDense: true),
          items: [
            for (var start in InstanceStart.values)
              DropdownMenuItem(value: start, child: Text('recordeddevice.instancestart.${start.name}'.tr()))
          ],
        ),
      ),
    ]);
  }

  Widget _buildTopics(BuildContext context, RecordedDeviceViewmodel vm) {
    var theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('recordeddevice.topics.label'.tr(), style: theme.textTheme.titleMedium!.copyWith(color: Colors.black87)),
      SizedBox(height: 4),
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: 200),
        child: SingleChildScrollView(
          child: Column(children: [
            for (var topic in vm.topics)
              SizedBox(
                height: 36,
                child: Row(children: [
                  Checkbox(value: vm.isTopicPlayed(topic), onChanged: (played) => vm.setTopicPlayed(topic, played ?? false)),
                  Expanded(child: Text(topic, overflow: TextOverflow.ellipsis)),
                ]),
              ),
          ]),
        ),
      ),
      if (!vm.hasPlayedTopics)
        Text('recordeddevice.notopics.error'.tr(),
            style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error)),
      SizedBox(height: 12),
    ]);
  }

  Widget _buildPlayback(BuildContext context, RecordedDeviceViewmodel vm) {
    var theme = Theme.of(context);
    var playback = vm.playback;
    var summary = [
      RecorderFormat.speed(playback.speed),
      if (playback.loop) 'simulator.recorded.loop'.tr(),
      for (var remap in playback.remaps) '${remap.from} → ${remap.to}',
    ].join(' · ');
    return Row(children: [
      TextButton.icon(
          style: TextButton.styleFrom(minimumSize: Size(0, 48)),
          onPressed: vm.recording == null ? null : () => _editPlayback(context, vm),
          icon: Icon(Icons.tune),
          label: Text('recordeddevice.playback.button'.tr())),
      SizedBox(width: 16),
      Expanded(
          child: Text(summary,
              overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor))),
    ]);
  }

  Widget _buildIssues(BuildContext context, RecordedDeviceViewmodel vm) {
    var theme = Theme.of(context);
    var issues = vm.issues;
    if (issues.isEmpty) {
      return SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var issue in issues)
          Text('simulator.issue.${issue.kind.name}'.tr(args: [issue.detail]),
              style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error)),
      ]),
    );
  }

  Widget _buildActions(RecordedDeviceViewmodel vm) {
    return SrxFormRow(alignment: CrossAxisAlignment.center, children: [
      Spacer(flex: 1),
      Expanded(
          flex: 5,
          child: OutlinedButton(
              onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('srx.common.cancel'.tr()))),
      SizedBox(width: 16),
      Expanded(flex: 5, child: ElevatedButton(onPressed: () => _onSavePressed(vm), child: Text('simulator.save.button'.tr()))),
    ]);
  }

  Future<void> _editPlayback(BuildContext context, RecordedDeviceViewmodel vm) async {
    var options = await showDialog<PlaybackOptions>(
        context: context,
        builder: (_) => SrxTheme(
            data: CustomTheme.srxTheme,
            child: PlaybackOptionsDialog(
                recording: vm.recording!,
                options: vm.playback,
                maxRate: 1000,
                allowMaxSpeed: false,
                hint: 'recordeddevice.remap.hint'.tr())));
    if (options != null) {
      vm.setPlayback(options);
    }
  }

  void _onSavePressed(RecordedDeviceViewmodel vm) {
    var device = vm.save();
    if (device != null) {
      GetIt.I.get<SrxNavigationService>().pop(device);
    }
  }
}
