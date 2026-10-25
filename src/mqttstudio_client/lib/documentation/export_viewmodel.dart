import 'dart:async';
import 'package:mqttstudio/documentation/export/doc_export.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

class DocExportRequest {
  final DocExportOptions options;
  final String fileName;

  DocExportRequest(this.options, this.fileName);
}

// Viewmodel of the export dialog (doc/documentation-design.md §12.5)
class ExportViewmodel extends SrxChangeNotifier {
  static const String formatField = 'format';
  static const String scopeField = 'scope';
  static const String examplesField = 'examples';
  static const String observedField = 'observed';
  static const String brokerField = 'broker';
  static const String fileNameField = 'fileName';
  // the scope value of the whole documentation
  static const String wholeDocumentation = '';

  final String baseName;
  // the selected namespace or topic, offered as scope
  final String? selectedPath;
  late final FormGroup form;
  final List<StreamSubscription> _subscriptions = [];

  ExportViewmodel({required String title, this.selectedPath}) : baseName = _safeName(title) {
    form = FormGroup({
      formatField: FormControl<DocExportFormat>(value: DocExportFormat.markdown),
      scopeField: FormControl<String>(value: wholeDocumentation),
      examplesField: FormControl<bool>(value: true),
      observedField: FormControl<bool>(value: false),
      brokerField: FormControl<bool>(value: false),
      fileNameField: FormControl<String>(
          value: _fileName(DocExportFormat.markdown), validators: [Validators.required, Validators.maxLength(200)]),
    });
    _subscriptions.add(form.control(formatField).valueChanges.listen((_) => _onFormatChanged()));
  }

  @override
  void dispose() {
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  DocExportFormat get format => form.control(formatField).value as DocExportFormat;

  // CSV has no examples, statistics or broker
  bool get hasDetails => format != DocExportFormat.csv && format != DocExportFormat.jsonSchema;

  static String _safeName(String title) {
    var name = title.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-');
    return name.isEmpty ? 'mqtt-topics' : name;
  }

  String _fileName(DocExportFormat format) => '$baseName.${DocExport.extensionOf(format)}';

  // the extension follows the format, the name stays what the user typed
  void _onFormatChanged() {
    var control = form.control(fileNameField);
    var name = ((control.value as String?) ?? '').trim();
    var stem = name;
    for (var format in DocExportFormat.values) {
      var extension = '.${DocExport.extensionOf(format)}';
      if (name.endsWith(extension)) {
        stem = name.substring(0, name.length - extension.length);
        break;
      }
    }
    control.value = '${stem.isEmpty ? baseName : stem}.${DocExport.extensionOf(format)}';
    // CSV and the JSON Schema bundle have none of these details; they stay visible, disabled
    for (var name in [examplesField, observedField, brokerField]) {
      if (hasDetails) {
        form.control(name).markAsEnabled();
      } else {
        form.control(name).markAsDisabled();
      }
    }
    notifyListeners();
  }

  DocExportRequest? save() {
    if (!form.valid) {
      form.markAllAsTouched();
      return null;
    }
    var scope = form.control(scopeField).value as String?;
    bool flag(String name) => form.control(name).value == true;
    return DocExportRequest(
        DocExportOptions(format,
            scope: scope == null || scope == wholeDocumentation ? null : scope,
            includeExamples: flag(examplesField),
            includeObserved: flag(observedField),
            includeBroker: flag(brokerField)),
        ((form.control(fileNameField).value as String?) ?? '').trim());
  }
}
