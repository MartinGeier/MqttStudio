import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/documentation/export/asyncapi_importer.dart';
import 'package:mqttstudio/documentation/export/import_merge.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

enum ImportMode { merge, replaceAll }

class DocImportRequest {
  final ImportPlan plan;
  final bool replaceAll;

  DocImportRequest(this.plan, this.replaceAll);
}

// Viewmodel of the dialog that imports an AsyncAPI document (doc/documentation-design.md §9.3)
class ImportViewmodel extends SrxChangeNotifier {
  static const String modeField = 'mode';

  late final FormGroup form;
  String? fileName;
  String? error;
  ImportedDocumentation? imported;
  ImportPlan? plan;
  StreamSubscription? _subscription;

  ImportViewmodel() {
    form = FormGroup({modeField: FormControl<ImportMode>(value: ImportMode.merge)});
    _subscription = form.control(modeField).valueChanges.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  bool get replaceAll => form.control(modeField).value == ImportMode.replaceAll;

  bool get canImport => plan != null && (replaceAll || plan!.items.any((item) => item.accept));

  // the browser hands over the bytes, the desktop the path
  Future<void> chooseFile() async {
    var picked = await FilePicker.pickFiles(
        dialogTitle: 'docimportdialog.choose.title'.tr(),
        type: FileType.custom,
        allowedExtensions: ['yaml', 'yml', 'json'],
        withData: kIsWeb);
    var file = picked?.files.single;
    if (file == null) {
      return;
    }
    var bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) {
      return;
    }
    load(file.name, utf8.decode(bytes, allowMalformed: true));
  }

  void load(String name, String text) {
    fileName = name;
    try {
      imported = AsyncApiImporter.read(text);
      plan = ImportPlan.of(GetIt.I.get<ProjectManager>().currentProject!.documentation, imported!.documentation);
      error = null;
    } on FormatException catch (exc) {
      imported = null;
      plan = null;
      error = exc.message;
    }
    notifyListeners();
  }

  void setAccept(ImportItem item, bool accept) {
    item.accept = accept;
    notifyListeners();
  }

  DocImportRequest? save() => canImport ? DocImportRequest(plan!, replaceAll) : null;
}
