import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:clock/clock.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:mqttstudio/simulator/engine/generator_instances.dart';
import 'package:mqttstudio/simulator/engine/simulation_rules.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:reactive_forms/reactive_forms.dart';

class TemplateField {
  String name;
  PayloadGenerator generator;

  TemplateField(this.name, this.generator);
}

class GeneratorPreview {
  final List<String> samples;
  // the samples as numbers when all of them are numbers, for the chart
  final List<double>? numbers;
  // a template that should be JSON and is not
  final bool invalidJson;
  final String? error;

  GeneratorPreview(this.samples, {this.numbers, this.invalidJson = false, this.error});
}

// Form controls of the generator part of the topic dialog and of the template field dialog. Keeps one form per
// generator type, so switching the type back and forth loses nothing. Only the selected type is saved.
class GeneratorEditorModel extends ChangeNotifier {
  // field names of the forms
  static const String minLength = 'minLength';
  static const String maxLength = 'maxLength';
  static const String charSet = 'charSet';
  static const String prefix = 'prefix';
  static const String postfix = 'postfix';
  static const String min = 'min';
  static const String max = 'max';
  static const String decimals = 'decimals';
  static const String start = 'start';
  static const String step = 'step';
  static const String resetAfter = 'resetAfter';
  static const String trueProbability = 'trueProbability';
  static const String trueText = 'trueText';
  static const String falseText = 'falseText';
  static const String values = 'values';
  static const String order = 'order';
  static const String volatility = 'volatility';
  static const String shape = 'shape';
  static const String offset = 'offset';
  static const String amplitude = 'amplitude';
  static const String periodSeconds = 'periodSeconds';
  static const String phaseDegrees = 'phaseDegrees';
  static const String noise = 'noise';
  static const String format = 'format';
  static const String pattern = 'pattern';
  static const String utc = 'utc';
  static const String mode = 'mode';
  static const String centerLat = 'centerLat';
  static const String centerLon = 'centerLon';
  static const String radiusMeters = 'radiusMeters';
  static const String turnRate = 'turnRate';
  static const String waypoints = 'waypoints';
  static const String speedMps = 'speedMps';
  static const String gpsFormat = 'gpsFormat';
  static const String folderPath = 'folderPath';
  static const String extensions = 'extensions';
  static const String template = 'template';
  static const String validateJson = 'validateJson';

  // a template field may not be a template or an image
  final bool isTemplateField;
  final FormControl<GeneratorType> typeControl;
  final Map<GeneratorType, FormGroup> _forms = {};
  final List<TemplateField> templateFields = [];
  GeneratorPreview? preview;

  GeneratorEditorModel(PayloadGenerator initial, {this.isTemplateField = false})
      : typeControl = FormControl<GeneratorType>(value: initial.type) {
    _forms[initial.type] = _buildForm(initial);
    if (initial is TemplateGenerator) {
      templateFields.addAll(initial.fields.entries.map((entry) => TemplateField(entry.key, entry.value)));
    }
    _typeSubscription = typeControl.valueChanges.listen((_) => _typeChanged());
  }

  late final StreamSubscription _typeSubscription;

  @override
  void dispose() {
    _typeSubscription.cancel();
    typeControl.dispose();
    super.dispose();
  }

  GeneratorType get type => typeControl.value!;

  List<GeneratorType> get availableTypes => GeneratorType.values
      .where((type) => !isTemplateField || type.allowedInTemplate)
      .where((type) => !kIsWeb || type != GeneratorType.randomImage || type == typeControl.value)
      .toList();

  FormGroup get form => _forms.putIfAbsent(type, () {
        var defaults = PayloadGenerator.defaultOf(type);
        // the example template refers to its fields, without them it would not be valid
        if (defaults is TemplateGenerator && templateFields.isEmpty) {
          templateFields.addAll(defaults.fields.entries.map((entry) => TemplateField(entry.key, entry.value)));
        }
        return _buildForm(defaults);
      });

  bool validate() {
    form.markAllAsTouched();
    return form.valid;
  }

  PayloadGenerator build() => _read(type, form);

  void addTemplateField(TemplateField field) {
    templateFields.add(field);
    _templateFieldsChanged();
  }

  void replaceTemplateField(int index, TemplateField field) {
    templateFields[index] = field;
    _templateFieldsChanged();
  }

  void removeTemplateField(int index) {
    templateFields.removeAt(index);
    _templateFieldsChanged();
  }

  // a name for a new field that is not used yet
  String newFieldName() {
    var number = templateFields.length + 1;
    while (templateFields.any((field) => field.name == 'field$number')) {
      number++;
    }
    return 'field$number';
  }

  // generates samples with a fresh state, as if the topic was started now
  void generatePreview({int instance = 1, String deviceName = '', Duration interval = const Duration(seconds: 1)}) {
    if (!validate()) {
      preview = null;
      notifyListeners();
      return;
    }
    var generator = build();
    var count = generator is TemplateGenerator ? 1 : 20;
    var now = clock.now();
    try {
      var instanceOfGenerator = createGeneratorInstance(
          generator, GeneratorContext(random: Random(), instanceNumber: instance, deviceName: deviceName, startedAt: now));
      var values = [
        for (var i = 1; i <= count; i++) instanceOfGenerator.next(now.add(interval * i), interval),
      ];
      var samples = values.map((value) => value.describe(maxLength: 2000)).toList();
      var numbers = samples.map(double.tryParse).toList();
      var invalidJson = generator is TemplateGenerator && generator.validateJson && !_isJson(samples.first);
      preview = GeneratorPreview(samples,
          numbers: numbers.every((n) => n != null) ? numbers.cast<double>() : null, invalidJson: invalidJson);
    } on GeneratorException catch (exc) {
      preview = GeneratorPreview([], error: exc.message);
    }
    notifyListeners();
  }

  static bool _isJson(String text) {
    try {
      jsonDecode(text);
      return true;
    } on FormatException {
      return false;
    }
  }

  void _typeChanged() {
    preview = null;
    notifyListeners();
  }

  void _templateFieldsChanged() {
    _forms[GeneratorType.template]?.control(template).updateValueAndValidity();
    preview = null;
    notifyListeners();
  }

  FormGroup _buildForm(PayloadGenerator generator) {
    switch (generator) {
      case RandomStringGenerator g:
        return FormGroup({
          minLength: _int(g.minLength, minValue: 0),
          maxLength: _int(g.maxLength, minValue: 0),
          charSet: FormControl<String>(value: g.charSet, validators: [Validators.required]),
          ..._affixes(g.prefix, g.postfix),
        });
      case RandomNumberGenerator g:
        return FormGroup({
          min: _double(g.min),
          max: _double(g.max),
          decimals: _decimals(g.decimals),
          ..._affixes(g.prefix, g.postfix),
        });
      case CounterGenerator g:
        return FormGroup({
          start: _double(g.start),
          step: _double(g.step),
          decimals: _decimals(g.decimals),
          resetAfter: FormControl<int>(value: g.resetAfter, validators: [_optionalMin(1)]),
          ..._affixes(g.prefix, g.postfix),
        });
      case BoolGenerator g:
        return FormGroup({
          trueProbability: _double(g.trueProbability, minValue: 0, maxValue: 1),
          trueText: FormControl<String>(value: g.trueText),
          falseText: FormControl<String>(value: g.falseText),
        });
      case ValueListGenerator g:
        return FormGroup({
          values: FormControl<String>(value: g.values.join('\n'), validators: [Validators.required]),
          order: FormControl<PickOrder>(value: g.order),
        });
      case RandomWalkGenerator g:
        return FormGroup({
          start: _double(g.start),
          min: _double(g.min),
          max: _double(g.max),
          volatility: _double(g.volatility, minValue: 0),
          decimals: _decimals(g.decimals),
          ..._affixes(g.prefix, g.postfix),
        });
      case WaveGenerator g:
        return FormGroup({
          shape: FormControl<WaveShape>(value: g.shape),
          offset: _double(g.offset),
          amplitude: _double(g.amplitude),
          periodSeconds: _double(g.periodSeconds, minValue: 0.001),
          phaseDegrees: _double(g.phaseDegrees),
          noise: _double(g.noise, minValue: 0),
          decimals: _decimals(g.decimals),
          ..._affixes(g.prefix, g.postfix),
        });
      case TimestampGenerator g:
        return FormGroup({
          format: FormControl<TimestampFormat>(value: g.format),
          pattern: FormControl<String>(value: g.pattern),
          utc: FormControl<bool>(value: g.utc),
        });
      case GpsTrackGenerator g:
        var group = FormGroup({
          mode: FormControl<GpsMode>(value: g.mode),
          centerLat: _double(g.centerLat, minValue: -90, maxValue: 90),
          centerLon: _double(g.centerLon, minValue: -180, maxValue: 180),
          radiusMeters: _double(g.radiusMeters, minValue: 1),
          turnRate: _double(g.turnRateDegPerSecond, minValue: 0),
          waypoints: FormControl<String>(
              value: g.waypoints.map((p) => '${p.lat},${p.lon}').join('\n'), validators: [Validators.delegate(_validateWaypoints)]),
          speedMps: _double(g.speedMps, minValue: 0),
          decimals: _decimals(g.decimals),
          gpsFormat: FormControl<GpsFormat>(value: g.format),
        });
        // a route needs waypoints, wandering does not
        group.control(mode).valueChanges.listen((_) => group.control(waypoints).updateValueAndValidity());
        return group;
      case RandomImageGenerator g:
        return FormGroup({
          folderPath: FormControl<String>(value: g.folderPath, validators: [Validators.required]),
          extensions: FormControl<String>(value: g.extensions.join(', '), validators: [Validators.required]),
          order: FormControl<PickOrder>(value: g.order),
        });
      case TemplateGenerator g:
        return FormGroup({
          template: FormControl<String>(
              value: g.template, validators: [Validators.required, Validators.delegate(_validateTemplateReferences)]),
          validateJson: FormControl<bool>(value: g.validateJson),
        });
    }
  }

  PayloadGenerator _read(GeneratorType type, FormGroup f) {
    T v<T>(String name) => f.control(name).value as T;
    String text(String name) => (f.control(name).value as String?) ?? '';
    switch (type) {
      case GeneratorType.randomString:
        return RandomStringGenerator(
            minLength: v(minLength), maxLength: v(maxLength), charSet: text(charSet), prefix: text(prefix), postfix: text(postfix));
      case GeneratorType.randomNumber:
        return RandomNumberGenerator(
            min: v(min), max: v(max), decimals: v(decimals), prefix: text(prefix), postfix: text(postfix));
      case GeneratorType.counter:
        return CounterGenerator(
            start: v(start),
            step: v(step),
            decimals: v(decimals),
            resetAfter: v<int?>(resetAfter),
            prefix: text(prefix),
            postfix: text(postfix));
      case GeneratorType.boolean:
        return BoolGenerator(trueProbability: v(trueProbability), trueText: text(trueText), falseText: text(falseText));
      case GeneratorType.valueList:
        return ValueListGenerator(values: _lines(text(values)), order: v(order));
      case GeneratorType.randomWalk:
        return RandomWalkGenerator(
            start: v(start),
            min: v(min),
            max: v(max),
            volatility: v(volatility),
            decimals: v(decimals),
            prefix: text(prefix),
            postfix: text(postfix));
      case GeneratorType.wave:
        return WaveGenerator(
            shape: v(shape),
            offset: v(offset),
            amplitude: v(amplitude),
            periodSeconds: v(periodSeconds),
            phaseDegrees: v(phaseDegrees),
            noise: v(noise),
            decimals: v(decimals),
            prefix: text(prefix),
            postfix: text(postfix));
      case GeneratorType.timestamp:
        return TimestampGenerator(format: v(format), pattern: text(pattern), utc: v<bool?>(utc) ?? true);
      case GeneratorType.gpsTrack:
        return GpsTrackGenerator(
            mode: v(mode),
            centerLat: v(centerLat),
            centerLon: v(centerLon),
            radiusMeters: v(radiusMeters),
            turnRateDegPerSecond: v(turnRate),
            waypoints: parseWaypoints(text(waypoints)) ?? [],
            speedMps: v(speedMps),
            decimals: v(decimals),
            format: v(gpsFormat));
      case GeneratorType.randomImage:
        return RandomImageGenerator(
            folderPath: text(folderPath).trim(),
            extensions: text(extensions)
                .split(',')
                .map((e) => e.trim().toLowerCase())
                .where((e) => e.isNotEmpty)
                .map((e) => e.startsWith('.') ? e : '.$e')
                .toList(),
            order: v(order));
      case GeneratorType.template:
        return TemplateGenerator(
            template: text(template),
            fields: {for (var field in templateFields) field.name: field.generator},
            validateJson: v<bool?>(validateJson) ?? false);
    }
  }

  static List<String> _lines(String text) =>
      text.split(RegExp(r'\r?\n')).map((line) => line.trim()).where((line) => line.isNotEmpty).toList();

  // one "lat,lon" per line, null when a line is not a position
  static List<GpsPoint>? parseWaypoints(String text) {
    var points = <GpsPoint>[];
    for (var line in _lines(text)) {
      var parts = line.split(',');
      var lat = parts.length == 2 ? double.tryParse(parts[0].trim()) : null;
      var lon = parts.length == 2 ? double.tryParse(parts[1].trim()) : null;
      if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
        return null;
      }
      points.add(GpsPoint(lat, lon));
    }
    return points;
  }

  Map<String, dynamic>? _validateWaypoints(AbstractControl<dynamic> control) {
    var group = control.parent as FormGroup?;
    var waypointsText = (control.value as String?) ?? '';
    var parsed = parseWaypoints(waypointsText);
    if (parsed == null) {
      return {'waypoints': true};
    }
    var isRoute = group != null && group.control(mode).value == GpsMode.route;
    if (isRoute && parsed.length < 2) {
      return {'tooFewWaypoints': true};
    }
    return null;
  }

  Map<String, dynamic>? _validateTemplateReferences(AbstractControl<dynamic> control) {
    var names = templateFields.map((field) => field.name).toSet();
    var unknown = SimulationRules.templateReferences((control.value as String?) ?? '').difference(names);
    return unknown.isEmpty ? null : {'unknownFields': unknown.join(', ')};
  }

  static Map<String, FormControl<String>> _affixes(String prefixValue, String postfixValue) => {
        prefix: FormControl<String>(value: prefixValue),
        postfix: FormControl<String>(value: postfixValue),
      };

  static FormControl<double> _double(double value, {double? minValue, double? maxValue}) => FormControl<double>(
      value: value,
      validators: [Validators.required, if (minValue != null) Validators.min(minValue), if (maxValue != null) Validators.max(maxValue)]);

  static FormControl<int> _int(int value, {int? minValue}) =>
      FormControl<int>(value: value, validators: [Validators.required, if (minValue != null) Validators.min(minValue)]);

  static FormControl<int> _decimals(int value) =>
      FormControl<int>(value: value, validators: [Validators.required, Validators.min(0), Validators.max(10)]);

  // an optional number, Validators.min would reject an empty field
  static Validator<dynamic> _optionalMin(int minValue) => Validators.delegate((control) {
        var value = control.value as int?;
        return value != null && value < minValue ? {ValidationMessage.min: value} : null;
      });

  // validation messages of the generator fields
  static Map<String, String Function(Object)> get validationMessages => {
        ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
        ValidationMessage.min: (_) => 'simulator.value.toosmall.error'.tr(),
        ValidationMessage.max: (_) => 'simulator.value.toolarge.error'.tr(),
        ValidationMessage.number: (_) => 'simulator.value.number.error'.tr(),
        'waypoints': (_) => 'simulator.waypoints.error'.tr(),
        'tooFewWaypoints': (_) => 'simulator.issue.routeTooShort'.tr(),
        'unknownFields': (error) => 'simulator.template.unknownfields.error'.tr(args: ['$error']),
      };
}
