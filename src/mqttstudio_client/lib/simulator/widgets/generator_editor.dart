import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/simulator/generator_editor_model.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/widgets/simulator_format.dart';
import 'package:mqttstudio/simulator/widgets/template_field_dialog.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

typedef M = GeneratorEditorModel;

// The parameters of the selected generator type, each type with its own form. Used by the topic dialog and, without
// templates and images, by the template field dialog.
class GeneratorEditor extends StatelessWidget {
  final GeneratorEditorModel model;
  final int previewInstance;
  final String deviceName;
  final Duration previewInterval;

  const GeneratorEditor(
      {Key? key,
      required this.model,
      this.previewInstance = 1,
      this.deviceName = '',
      this.previewInterval = const Duration(seconds: 1)})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: model,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InputDecorator(
          decoration: InputDecoration(
              border: OutlineInputBorder(), labelText: SimulatorFormat.generatorName(model.type), isDense: true),
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ReactiveForm(
              // a new form per type, the key makes sure the fields bind to it
              key: ValueKey(model.type),
              formGroup: model.form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _buildFields(context)),
            ),
          ),
        ),
        SizedBox(height: 8),
        _buildPreview(context),
      ]),
    );
  }

  List<Widget> _buildFields(BuildContext context) {
    switch (model.type) {
      case GeneratorType.randomString:
        return [
          _row([_int(M.minLength, 'minlength'), _int(M.maxLength, 'maxlength'), _text(M.prefix, 'prefix'), _text(M.postfix, 'postfix')]),
          _row([_text(M.charSet, 'charset')]),
        ];
      case GeneratorType.randomNumber:
        return [
          _row([_double(M.min, 'min'), _double(M.max, 'max'), _int(M.decimals, 'decimals')]),
          _row([_text(M.prefix, 'prefix'), _text(M.postfix, 'postfix'), Spacer()]),
        ];
      case GeneratorType.counter:
        return [
          _row([_double(M.start, 'start'), _double(M.step, 'step'), _int(M.decimals, 'decimals'), _int(M.resetAfter, 'resetafter', hint: 'simulator.field.never.hint')]),
          _row([_text(M.prefix, 'prefix'), _text(M.postfix, 'postfix'), Spacer(), Spacer()]),
        ];
      case GeneratorType.boolean:
        return [
          _row([_double(M.trueProbability, 'trueprobability'), _text(M.trueText, 'truetext'), _text(M.falseText, 'falsetext')]),
        ];
      case GeneratorType.valueList:
        return [
          SrxFormRow(multipleLineHeight: 2, children: [
            Expanded(flex: 3, child: _multiline(M.values, 'values', 3, helper: 'simulator.field.values.helper')),
            SizedBox(width: 16),
            Expanded(flex: 1, child: _dropdown<PickOrder>(M.order, 'order', PickOrder.values, (o) => 'simulator.pickorder.${o.name}')),
          ]),
        ];
      case GeneratorType.randomWalk:
        return [
          _row([_double(M.start, 'start'), _double(M.min, 'min'), _double(M.max, 'max'), _double(M.volatility, 'volatility', helper: 'simulator.field.volatility.helper')]),
          _row([_int(M.decimals, 'decimals'), _text(M.prefix, 'prefix'), _text(M.postfix, 'postfix'), Spacer()]),
        ];
      case GeneratorType.wave:
        return [
          _row([
            _dropdown<WaveShape>(M.shape, 'shape', WaveShape.values, (s) => 'simulator.waveshape.${s.name}'),
            _double(M.offset, 'offset'),
            _double(M.amplitude, 'amplitude'),
            _double(M.periodSeconds, 'period'),
          ]),
          _row([_double(M.phaseDegrees, 'phase'), _double(M.noise, 'noise'), _int(M.decimals, 'decimals'), _text(M.prefix, 'prefix'), _text(M.postfix, 'postfix')]),
        ];
      case GeneratorType.timestamp:
        return [
          _row([
            _dropdown<TimestampFormat>(M.format, 'format', TimestampFormat.values, (f) => 'simulator.timestampformat.${f.name}'),
            _text(M.pattern, 'pattern', helper: 'simulator.field.pattern.helper'),
            _checkbox(M.utc, 'utc'),
          ]),
        ];
      case GeneratorType.gpsTrack:
        return [
          _row([
            _dropdown<GpsMode>(M.mode, 'mode', GpsMode.values, (m) => 'simulator.gpsmode.${m.name}'),
            _double(M.centerLat, 'centerlat'),
            _double(M.centerLon, 'centerlon'),
            _double(M.radiusMeters, 'radius'),
          ]),
          _row([
            _double(M.turnRate, 'turnrate'),
            _double(M.speedMps, 'speed'),
            _int(M.decimals, 'decimals'),
            _dropdown<GpsFormat>(M.gpsFormat, 'gpsformat', GpsFormat.values, (f) => 'simulator.gpsformat.${f.name}'),
          ]),
          SrxFormRow(multipleLineHeight: 2, children: [
            Expanded(child: _multiline(M.waypoints, 'waypoints', 3, helper: 'simulator.field.waypoints.helper')),
          ]),
        ];
      case GeneratorType.randomImage:
        return [
          _row([
            Expanded(flex: 3, child: _folderField(context)),
            SizedBox(width: 16),
            Expanded(flex: 2, child: _textField(M.extensions, 'extensions')),
            SizedBox(width: 16),
            Expanded(flex: 1, child: _dropdown<PickOrder>(M.order, 'order', PickOrder.values, (o) => 'simulator.pickorder.${o.name}')),
          ], expand: false),
        ];
      case GeneratorType.template:
        return [_TemplateFields(model: model)];
    }
  }

  // a row of fields with the same width
  Widget _row(List<Widget> fields, {bool expand = true}) {
    if (!expand) {
      return SrxFormRow(children: fields);
    }
    var children = <Widget>[];
    for (var field in fields) {
      if (children.isNotEmpty) {
        children.add(SizedBox(width: 16));
      }
      children.add(field is Spacer ? field : Expanded(child: field));
    }
    return SrxFormRow(children: children);
  }

  static InputDecoration _decoration(String label, {String? helper, String? hint}) => InputDecoration(
      border: OutlineInputBorder(),
      labelText: 'simulator.field.$label.label'.tr(),
      helperText: helper?.tr(),
      hintText: hint?.tr(),
      isDense: true);

  Widget _double(String name, String label, {String? helper}) => ReactiveTextField<double>(
        formControlName: name,
        valueAccessor: _NumberValueAccessor(),
        decoration: _decoration(label, helper: helper),
        validationMessages: M.validationMessages,
      );

  Widget _int(String name, String label, {String? helper, String? hint}) => ReactiveTextField<int>(
        formControlName: name,
        decoration: _decoration(label, helper: helper, hint: hint),
        validationMessages: M.validationMessages,
      );

  Widget _text(String name, String label, {String? helper}) => _textField(name, label, helper: helper);

  Widget _textField(String name, String label, {String? helper}) => ReactiveTextField<String>(
        formControlName: name,
        decoration: _decoration(label, helper: helper),
        validationMessages: M.validationMessages,
      );

  Widget _multiline(String name, String label, int lines, {String? helper}) => ReactiveTextField<String>(
        formControlName: name,
        minLines: lines,
        maxLines: lines,
        decoration: _decoration(label, helper: helper),
        validationMessages: M.validationMessages,
      );

  Widget _dropdown<T>(String name, String label, List<T> values, String Function(T) labelKey) => ReactiveDropdownField<T>(
        formControlName: name,
        decoration: _decoration(label),
        items: [for (var value in values) DropdownMenuItem(value: value, child: Text(labelKey(value).tr()))],
      );

  Widget _checkbox(String name, String label) =>
      CheckboxField(formControlName: name, form: model.form, label: 'simulator.field.$label.label'.tr());

  Widget _folderField(BuildContext context) => ReactiveTextField<String>(
        formControlName: M.folderPath,
        decoration: _decoration('folder').copyWith(
            suffixIcon: kIsWeb
                ? null
                : IconButton(
                    onPressed: () async {
                      var path = await FilePicker.getDirectoryPath();
                      if (path != null) {
                        model.form.control(M.folderPath).value = path;
                      }
                    },
                    tooltip: 'simulator.field.folder.tooltip'.tr(),
                    icon: Icon(Icons.folder_open))),
        validationMessages: M.validationMessages,
      );

  Widget _buildPreview(BuildContext context) {
    var theme = Theme.of(context);
    var preview = model.preview;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('simulator.preview.label'.tr(), style: theme.textTheme.titleMedium),
        SizedBox(width: 12),
        Expanded(
            child: Text('simulator.preview.caption'.tr(args: ['$previewInstance']), style: theme.textTheme.bodySmall)),
        if (preview != null && model.type == GeneratorType.template) _buildJsonCheck(context, preview),
        Tooltip(
          message: 'simulator.preview.tooltip'.tr(),
          child: TextButton.icon(
              onPressed: () => model.generatePreview(
                  instance: previewInstance, deviceName: deviceName, interval: previewInterval),
              icon: Icon(Icons.refresh),
              label: Text('simulator.preview.button'.tr())),
        ),
      ]),
      if (preview != null) _buildSamples(context, preview),
    ]);
  }

  Widget _buildJsonCheck(BuildContext context, GeneratorPreview preview) {
    var theme = Theme.of(context);
    var generator = model.form.control(M.validateJson).value == true;
    if (!generator || preview.error != null) {
      return SizedBox();
    }
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(children: [
        Icon(preview.invalidJson ? Icons.error : Icons.check_circle,
            size: 18, color: preview.invalidJson ? theme.colorScheme.error : theme.custom.running),
        SizedBox(width: 4),
        Text((preview.invalidJson ? 'simulator.preview.invalidjson' : 'simulator.preview.validjson').tr(),
            style: theme.textTheme.bodySmall),
      ]),
    );
  }

  Widget _buildSamples(BuildContext context, GeneratorPreview preview) {
    var theme = Theme.of(context);
    if (preview.error != null) {
      return Text(preview.error!, style: TextStyle(color: theme.colorScheme.error));
    }
    var textStyle = theme.textTheme.bodyLarge!.copyWith(height: 1.7);
    if (model.type == GeneratorType.template) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(4)),
        child: SelectableText(preview.samples.first, style: textStyle, maxLines: 8),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (preview.numbers != null && preview.numbers!.length > 1)
        SizedBox(height: 90, child: CustomPaint(painter: _PreviewChartPainter(preview.numbers!, theme))),
      SelectableText(preview.samples.join(' · '), style: textStyle, maxLines: 3),
    ]);
  }
}

// Shows 20 instead of 20.00 as DoubleValueAccessor does, and takes a comma as decimal separator
class _NumberValueAccessor extends ControlValueAccessor<double, String> {
  @override
  String modelToViewValue(double? modelValue) {
    if (modelValue == null) {
      return '';
    }
    return modelValue == modelValue.roundToDouble() && modelValue.abs() < 1e15
        ? modelValue.toInt().toString()
        : modelValue.toString();
  }

  @override
  double? viewToModelValue(String? viewValue) =>
      viewValue == null || viewValue.trim().isEmpty ? null : double.tryParse(viewValue.trim().replaceAll(',', '.'));
}

class _PreviewChartPainter extends CustomPainter {
  final List<double> values;
  final ThemeData theme;

  _PreviewChartPainter(this.values, this.theme);

  @override
  void paint(Canvas canvas, Size size) {
    var low = values.reduce((a, b) => a < b ? a : b);
    var high = values.reduce((a, b) => a > b ? a : b);
    var range = high - low == 0 ? 1 : high - low;
    var grid = Paint()
      ..color = theme.dividerColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1), grid);
    var path = Path();
    for (var i = 0; i < values.length; i++) {
      var x = size.width * i / (values.length - 1);
      var y = 4 + (size.height - 8) * (1 - (values[i] - low) / range);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = theme.colorScheme.primary
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _PreviewChartPainter oldDelegate) => oldDelegate.values != values;
}

// The template text and its fields
class _TemplateFields extends StatelessWidget {
  final GeneratorEditorModel model;

  const _TemplateFields({required this.model});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ReactiveTextField<String>(
            formControlName: M.template,
            minLines: 8,
            maxLines: 8,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'simulator.field.template.label'.tr(),
                helperText: 'simulator.field.template.helper'.tr(),
                helperMaxLines: 2,
                isDense: true),
            validationMessages: M.validationMessages,
          ),
          CheckboxField(
              formControlName: M.validateJson, form: model.form, label: 'simulator.field.validatejson.label'.tr()),
        ]),
      ),
      SizedBox(width: 16),
      Expanded(child: _buildFieldTable(context)),
    ]);
  }

  Widget _buildFieldTable(BuildContext context) {
    var theme = Theme.of(context);
    var caption = theme.textTheme.bodySmall;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 32,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
        child: Row(children: [
          SizedBox(width: 80, child: Text('simulator.templatefield.name.column'.tr(), style: caption)),
          Expanded(child: Text('simulator.templatefield.generator.column'.tr(), style: caption)),
        ]),
      ),
      for (var i = 0; i < model.templateFields.length; i++) _buildFieldRow(context, i),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
            onPressed: () => _editField(context, null),
            icon: Icon(Icons.add),
            label: Text('simulator.templatefield.add.button'.tr())),
      ),
    ]);
  }

  Widget _buildFieldRow(BuildContext context, int index) {
    var field = model.templateFields[index];
    var theme = Theme.of(context);
    return Container(
      height: 48,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
      child: Row(children: [
        SizedBox(width: 80, child: Text(field.name, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
        Expanded(child: Text(SimulatorFormat.generatorName(field.generator.type), overflow: TextOverflow.ellipsis)),
        IconButton(
            onPressed: () => _editField(context, index),
            icon: Icon(Icons.edit),
            tooltip: 'simulator.templatefield.edit.tooltip'.tr()),
        IconButton(
            onPressed: () => model.removeTemplateField(index),
            icon: Icon(Icons.delete),
            tooltip: 'simulator.templatefield.delete.tooltip'.tr()),
      ]),
    );
  }

  Future _editField(BuildContext context, int? index) async {
    var existing = index == null ? null : model.templateFields[index];
    var otherNames = [
      for (var i = 0; i < model.templateFields.length; i++)
        if (i != index) model.templateFields[i].name
    ];
    var result = await showDialog<TemplateField>(
        context: context,
        builder: (_) => SrxTheme(
            data: CustomTheme.srxTheme,
            child: TemplateFieldDialog(
                field: existing ?? TemplateField(model.newFieldName(), const RandomNumberGenerator()),
                otherNames: otherNames)));
    if (result == null) {
      return;
    }
    if (index == null) {
      model.addTemplateField(result);
    } else {
      model.replaceTemplateField(index, result);
    }
  }
}
