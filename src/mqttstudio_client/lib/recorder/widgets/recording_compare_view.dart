import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/recorder/compare_viewmodel.dart';
import 'package:mqttstudio/recorder/model/compare_options.dart';
import 'package:mqttstudio/recorder/widgets/recorder_format.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// The COMPARE tab (doc/recorder-design.md §9): the options on the left, the result per topic on the right
class RecordingCompareView extends StatelessWidget {
  static const double optionsWidth = 360;

  const RecordingCompareView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<CompareViewmodel>();
    if (vm.info == null) {
      return Container();
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        width: optionsWidth,
        decoration: BoxDecoration(border: Border(right: BorderSide(color: Theme.of(context).dividerColor))),
        child: SingleChildScrollView(padding: EdgeInsets.all(12), child: _buildOptions(context, vm)),
      ),
      Expanded(child: _buildResult(context, vm)),
    ]);
  }

  Widget _buildOptions(BuildContext context, CompareViewmodel vm) {
    InputDecoration decoration(String labelKey, [String? helperKey]) => InputDecoration(
        border: OutlineInputBorder(), labelText: labelKey.tr(), helperText: helperKey?.tr(), helperMaxLines: 2, isDense: true);
    Widget number(String name, String labelKey) => ReactiveTextField<double>(
          formControlName: name,
          decoration: decoration(labelKey),
          validationMessages: {
            ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
            ValidationMessage.min: (_) => 'recorddialog.value.toosmall.error'.tr(),
            ValidationMessage.number: (_) => 'recorddialog.value.number.error'.tr(),
          },
        );
    return ReactiveForm(
      formGroup: vm.form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('compare.with.label'.tr(args: [vm.info!.name]), style: Theme.of(context).textTheme.titleSmall),
        SizedBox(height: 12),
        ReactiveDropdownField<String>(
          formControlName: CompareViewmodel.recordingField,
          isExpanded: true,
          decoration: decoration('compare.recording.label'),
          validationMessages: {ValidationMessage.required: (_) => 'compare.norecording.error'.tr()},
          items: [
            for (var other in vm.candidates)
              DropdownMenuItem(
                  value: other.id,
                  child: Text('${other.name} · ${RecorderFormat.date(other.header.startedAt)}', overflow: TextOverflow.ellipsis))
          ],
        ),
        SizedBox(height: 12),
        CheckboxField(formControlName: CompareViewmodel.countsField, form: vm.form, label: 'compare.counts.label'.tr()),
        number(CompareViewmodel.countToleranceField, 'compare.counttolerance.label'),
        CheckboxField(formControlName: CompareViewmodel.payloadsField, form: vm.form, label: 'compare.payloads.label'.tr()),
        ReactiveTextField<String>(
          formControlName: CompareViewmodel.ignoreField,
          decoration: decoration('compare.ignore.label', 'compare.ignore.helper'),
          validationMessages: {'jsonpath': (_) => 'recordingcharts.path.error'.tr()},
        ),
        SizedBox(height: 12),
        number(CompareViewmodel.numberToleranceField, 'compare.numbertolerance.label'),
        CheckboxField(formControlName: CompareViewmodel.timingField, form: vm.form, label: 'compare.timing.label'.tr()),
        number(CompareViewmodel.timingToleranceField, 'compare.timingtolerance.label'),
        SizedBox(height: 12),
        ReactiveTextField<String>(
          formControlName: CompareViewmodel.remapsField,
          decoration: decoration('compare.remaps.label', 'compare.remaps.helper'),
          validationMessages: {'remap': (_) => 'compare.remaps.error'.tr()},
        ),
        if (vm.hasRange)
          CheckboxField(formControlName: CompareViewmodel.rangeField, form: vm.form, label: 'compare.range.label'.tr()),
        SizedBox(height: 16),
        ElevatedButton.icon(
            onPressed: vm.isRunning ? null : vm.compare, icon: Icon(Icons.compare_arrows), label: Text('compare.compare.button'.tr())),
      ]),
    );
  }

  Widget _buildResult(BuildContext context, CompareViewmodel vm) {
    var theme = Theme.of(context);
    var hint = theme.textTheme.titleMedium!.copyWith(color: theme.hintColor);
    if (vm.isRunning) {
      return Center(child: SizedBox(width: 240, child: LinearProgressIndicator(value: vm.progress)));
    }
    if (vm.error != null) {
      return Center(child: Text('compare.error'.tr(args: [vm.error!]), style: hint.copyWith(color: theme.colorScheme.error)));
    }
    var result = vm.result;
    if (result == null) {
      return Center(child: Text('compare.noresult.label'.tr(), style: hint));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(
          result.isEqual
              ? 'compare.equal.label'.tr(args: [result.recordingA, result.recordingB])
              : 'compare.different.label'.tr(args: [
                  '${result.countOf(TopicCompareStatus.different)}',
                  '${result.countOf(TopicCompareStatus.onlyInA)}',
                  '${result.countOf(TopicCompareStatus.onlyInB)}',
                ]),
          style: theme.textTheme.titleMedium!
              .copyWith(color: result.isEqual ? theme.custom.connectedColor : theme.colorScheme.error),
        ),
      ),
      _buildHeader(context),
      Expanded(
        child: ListView(children: [for (var topic in result.topics) _buildRow(context, topic)]),
      ),
    ]);
  }

  Widget _buildHeader(BuildContext context) {
    var theme = Theme.of(context);
    var style = theme.textTheme.bodySmall!.copyWith(color: theme.hintColor);
    return Container(
      height: 36,
      padding: EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
      child: Row(children: [
        Expanded(flex: 4, child: Text('compare.column.topic'.tr(), style: style)),
        Expanded(flex: 2, child: Text('compare.column.status'.tr(), style: style)),
        Expanded(flex: 2, child: Text('compare.column.messages'.tr(), style: style)),
        Expanded(flex: 2, child: Text('compare.column.interval'.tr(), style: style)),
        Expanded(flex: 4, child: Text('compare.column.difference'.tr(), style: style)),
      ]),
    );
  }

  Widget _buildRow(BuildContext context, TopicComparison topic) {
    var theme = Theme.of(context);
    var differs = topic.status != TopicCompareStatus.equal;
    String interval(int? micros) => micros == null ? '–' : RecorderFormat.duration(Duration(microseconds: micros));
    Widget cell(int flex, String text, {bool marked = false}) => Expanded(
        flex: flex,
        child: Text(text,
            overflow: TextOverflow.ellipsis,
            style: marked ? TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w500) : null));
    var difference = topic.firstDifference;
    return InkWell(
      onTap: difference == null ? null : () => _showDifference(context, topic, difference),
      child: Container(
        height: 44,
        padding: EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
        child: Row(children: [
          cell(4, topic.topic),
          cell(2, 'compare.status.${topic.status.name}'.tr(), marked: differs),
          cell(2, '${RecorderFormat.count(topic.countA)} / ${RecorderFormat.count(topic.countB)}', marked: topic.countDiffers),
          cell(2, '${interval(topic.medianIntervalAMicros)} / ${interval(topic.medianIntervalBMicros)}',
              marked: topic.timingDiffers),
          cell(
              4,
              difference == null
                  ? ''
                  : difference.path == null
                      ? 'compare.firstdifference.payload'.tr(args: ['${difference.index + 1}'])
                      : 'compare.firstdifference.label'.tr(args: ['${difference.index + 1}', difference.path!]),
              marked: true),
        ]),
      ),
    );
  }

  Future<void> _showDifference(BuildContext context, TopicComparison topic, PayloadDifference difference) {
    var theme = Theme.of(context);
    Widget side(String title, String? payload, int offset) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleMedium),
            Text(offset < 0 ? '–' : RecorderFormat.clock(Duration(microseconds: offset)),
                style: TextStyle(color: theme.hintColor)),
            SizedBox(height: 8),
            SelectableText(payload ?? 'compare.missing.label'.tr(), style: theme.textTheme.bodyLarge!.copyWith(height: 1.7)),
          ]),
        );
    return showDialog(
      context: context,
      builder: (_) => SrxTheme(
        data: CustomTheme.srxTheme,
        child: SimpleDialog(
          title: Text('compare.difference.title'.tr(args: [topic.topic, '${difference.index + 1}'])),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 800, maxWidth: 800, maxHeight: 500),
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (difference.path != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('compare.difference.path'.tr(args: [difference.path!])),
                    ),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    side('A', difference.payloadA, difference.offsetAMicros),
                    SizedBox(width: 24),
                    side('B', difference.payloadB, difference.offsetBMicros),
                  ]),
                  SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                        onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('compare.close.button'.tr())),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
