import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_payload.dart';
import 'package:mqttstudio/simulator/model/sparkplug_source.dart';
import 'package:mqttstudio/simulator/sparkplug/metric_values.dart';
import 'package:mqttstudio/simulator/sparkplug_metric_viewmodel.dart';
import 'package:mqttstudio/simulator/widgets/generator_editor.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

typedef _V = SparkplugMetricViewmodel;

// Adds or edits one metric of a simulated edge node or device: name, Sparkplug data type, unit, deadband, writable,
// and the generator its values come from (doc/sparkplug-design.md §10.3). Returns the SparkplugMetricSpec or null.
class SparkplugMetricDialog extends StatefulWidget {
  final SparkplugMetricSpec? metric;
  final Set<String> otherNames;

  const SparkplugMetricDialog({Key? key, this.metric, required this.otherNames}) : super(key: key);

  @override
  State<SparkplugMetricDialog> createState() => _SparkplugMetricDialogState();
}

class _SparkplugMetricDialogState extends State<SparkplugMetricDialog> {
  late final SparkplugMetricViewmodel _viewmodel;

  @override
  void initState() {
    super.initState();
    _viewmodel = SparkplugMetricViewmodel(widget.metric, otherNames: widget.otherNames);
  }

  @override
  void dispose() {
    _viewmodel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SrxTheme(
      data: CustomTheme.srxTheme,
      child: ChangeNotifierProvider.value(
        value: _viewmodel,
        child: Consumer<SparkplugMetricViewmodel>(
          builder: (context, vm, _) => SimpleDialog(
            title: Text((vm.isNew ? 'sparkplugmetric.add.title' : 'sparkplugmetric.edit.title').tr()),
            contentPadding: EdgeInsets.all(16),
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(minWidth: 720, maxWidth: 720),
                child: ReactiveForm(
                  formGroup: vm.form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFields(context, vm),
                      SizedBox(height: 8),
                      GeneratorEditor(model: vm.generator),
                      _buildMismatch(context, vm),
                      SizedBox(height: 16),
                      _buildActions(vm),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFields(BuildContext context, SparkplugMetricViewmodel vm) {
    return SrxFormRow(
      alignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: ReactiveTextField<String>(
            formControlName: _V.nameField,
            autofocus: true,
            decoration: _decoration('sparkplugmetric.name.label', helperKey: 'sparkplugmetric.name.helper'),
            validationMessages: _messages,
            onSubmitted: (_) => _onSavePressed(vm),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: ReactiveDropdownField<SpbDataType>(
            formControlName: _V.typeField,
            decoration: _decoration('sparkplugmetric.type.label'),
            items: [
              for (var type in SparkplugValues.scalarTypes) DropdownMenuItem(value: type, child: Text(type.label)),
            ],
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ReactiveTextField<String>(
            formControlName: _V.unitField,
            decoration: _decoration('sparkplugmetric.unit.label'),
            validationMessages: _messages,
            onSubmitted: (_) => _onSavePressed(vm),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ReactiveTextField<double>(
            formControlName: _V.deadbandField,
            readOnly: !vm.isNumber,
            decoration: _decoration('sparkplugmetric.deadband.label'),
            validationMessages: _messages,
            onSubmitted: (_) => _onSavePressed(vm),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: Tooltip(
            message: 'sparkplugmetric.writable.tooltip'.tr(),
            child: CheckboxField(
              formControlName: _V.writableField,
              form: vm.form,
              label: 'sparkplugmetric.writable.label'.tr(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMismatch(BuildContext context, SparkplugMetricViewmodel vm) {
    if (!vm.generatorMismatch) {
      return SizedBox.shrink();
    }
    var theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'sparkplugmetric.mismatch.error'.tr(args: [vm.type.label]),
        style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error),
      ),
    );
  }

  Widget _buildActions(SparkplugMetricViewmodel vm) {
    return SrxFormRow(
      alignment: CrossAxisAlignment.center,
      children: [
        Spacer(flex: 1),
        Expanded(
          flex: 5,
          child: OutlinedButton(
            onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null),
            child: Text('srx.common.cancel'.tr()),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          flex: 5,
          child: ElevatedButton(onPressed: () => _onSavePressed(vm), child: Text('simulator.save.button'.tr())),
        ),
      ],
    );
  }

  InputDecoration _decoration(String labelKey, {String? helperKey}) => InputDecoration(
    border: OutlineInputBorder(),
    labelText: labelKey.tr(),
    helperText: helperKey?.tr(),
    isDense: true,
  );

  static Map<String, String Function(Object)> get _messages => {
    ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
    ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr(),
    ValidationMessage.min: (_) => 'simulator.value.toosmall.error'.tr(),
    ValidationMessage.number: (_) => 'simulator.value.number.error'.tr(),
    'reserved': (_) => 'sparkplugmetric.reserved.error'.tr(),
    'duplicate': (_) => 'sparkplugmetric.duplicate.error'.tr(),
  };

  void _onSavePressed(SparkplugMetricViewmodel vm) {
    var metric = vm.save();
    if (metric != null) {
      GetIt.I.get<SrxNavigationService>().pop(metric);
    }
  }
}
