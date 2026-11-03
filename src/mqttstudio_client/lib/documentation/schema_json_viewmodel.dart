import 'dart:convert';
import 'package:mqttstudio/documentation/export/schema_json.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the dialog that edits a payload schema as JSON Schema text (doc/documentation-design.md §6)
class SchemaJsonViewmodel extends SrxChangeNotifier {
  static const String textField = 'text';

  late final FormGroup form;
  // keywords outside the supported subset, left out when saving
  List<String> warnings = [];

  SchemaJsonViewmodel(SchemaNode? schema) {
    var text = schema == null
        ? '{\n  "type": "object",\n  "properties": {}\n}'
        : _encoder.convert(SchemaJson.toJsonSchema(schema));
    form = FormGroup({
      textField: FormControl<String>(value: text, validators: [Validators.required, Validators.delegate(_validate)]),
    });
  }

  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  static Map<String, dynamic>? _validate(AbstractControl<dynamic> control) {
    try {
      return jsonDecode((control.value as String?) ?? '') is Map ? null : {'object': true};
    } on FormatException catch (exc) {
      return {'json': exc.message};
    }
  }

  // the schema, or null while the text is invalid
  SchemaNode? save() {
    if (!form.valid) {
      form.markAllAsTouched();
      return null;
    }
    var json =
        (jsonDecode(form.control(textField).value as String) as Map).map((key, value) => MapEntry('$key', value));
    warnings = [];
    var schema = SchemaJson.fromJsonSchema(json, warnings: warnings);
    notifyListeners();
    return schema;
  }
}
