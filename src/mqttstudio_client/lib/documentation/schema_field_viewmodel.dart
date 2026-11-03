import 'dart:async';
import 'package:mqttstudio/documentation/engine/schema_paths.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

class SchemaFieldResult {
  final String path;
  final SchemaNode field;
  final bool required;

  SchemaFieldResult(this.path, this.field, this.required);
}

// Viewmodel of the dialog that adds or edits one field of a payload schema
class SchemaFieldViewmodel extends SrxChangeNotifier {
  static const String pathField = 'path';
  static const String typeField = 'type';
  static const String formatField = 'format';
  static const String unitField = 'unit';
  static const String minimumField = 'minimum';
  static const String maximumField = 'maximum';
  static const String enumField = 'enum';
  static const String requiredField = 'required';
  static const String descriptionField = 'description';

  static const List<String> formats = ['date-time', 'uri', 'email', 'uuid'];

  final SchemaNode? schema;
  final String? oldPath;
  late final FormGroup form;
  final List<StreamSubscription> _subscriptions = [];

  SchemaFieldViewmodel(this.schema, this.oldPath, {bool required = false}) {
    var field = oldPath == null ? null : SchemaPaths.find(schema, oldPath!);
    form = FormGroup({
      pathField: FormControl<String>(
          value: oldPath ?? '${SchemaPaths.root}.',
          validators: [Validators.required, Validators.delegate(_validatePath)]),
      typeField: FormControl<SchemaType>(value: field?.type ?? SchemaType.string),
      formatField: FormControl<String>(value: field?.format),
      unitField: FormControl<String>(value: field?.unit ?? '', validators: [Validators.maxLength(50)]),
      minimumField: FormControl<double>(value: field?.minimum),
      maximumField: FormControl<double>(value: field?.maximum, validators: [Validators.delegate(_validateMaximum)]),
      enumField: FormControl<List<String>>(value: List.of(field?.enumValues ?? [])),
      requiredField: FormControl<bool>(value: required),
      descriptionField: FormControl<String>(value: field?.description ?? '', validators: [Validators.maxLength(2000)])
    });
    _subscriptions.add(
        form.control(minimumField).valueChanges.listen((_) => form.control(maximumField).updateValueAndValidity()));
    _subscriptions.add(form.control(typeField).valueChanges.listen((_) => notifyListeners()));
  }

  @override
  void dispose() {
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  bool get isNew => oldPath == null;

  SchemaType get type => form.control(typeField).value as SchemaType;

  bool get isNumber => type == SchemaType.number || type == SchemaType.integer;

  bool get isString => type == SchemaType.string;

  bool get isItems => ((form.control(pathField).value as String?) ?? '').trim().endsWith(SchemaPaths.items);

  Map<String, dynamic>? _validatePath(AbstractControl<dynamic> control) {
    var path = ((control.value as String?) ?? '').trim();
    if (path.isEmpty) {
      return null;
    }
    if (SchemaPaths.parse(path) == null) {
      return {'schemaPath': true};
    }
    if (path != oldPath && SchemaPaths.find(schema, path) != null) {
      return {'taken': true};
    }
    return null;
  }

  Map<String, dynamic>? _validateMaximum(AbstractControl<dynamic> control) {
    var minimum = (control.parent as FormGroup?)?.control(minimumField).value as double?;
    var maximum = control.value as double?;
    return minimum != null && maximum != null && minimum > maximum ? {'range': true} : null;
  }

  SchemaFieldResult? save() {
    if (!form.valid) {
      form.markAllAsTouched();
      return null;
    }
    String text(String name) => ((form.control(name).value as String?) ?? '').trim();
    var field = SchemaNode(
        type: type,
        description: text(descriptionField),
        unit: isNumber && text(unitField).isNotEmpty ? text(unitField) : null,
        format: isString ? form.control(formatField).value as String? : null,
        minimum: isNumber ? form.control(minimumField).value as double? : null,
        maximum: isNumber ? form.control(maximumField).value as double? : null,
        enumValues: isString || isNumber ? List.of(form.control(enumField).value as List<String>) : []);
    return SchemaFieldResult(text(pathField), field, !isItems && form.control(requiredField).value == true);
  }
}
