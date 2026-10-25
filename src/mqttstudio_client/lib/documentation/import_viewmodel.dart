import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/documentation/export/asyncapi_importer.dart';
import 'package:mqttstudio/documentation/export/import_merge.dart';
import 'package:mqttstudio/documentation/presets/vda5050_preset.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/protocol/vda5050/vda5050_model.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

enum ImportMode { merge, replaceAll }

class DocImportRequest {
  final ImportPlan plan;
  final bool replaceAll;

  DocImportRequest(this.plan, this.replaceAll);
}

// Viewmodel of the dialog that imports an AsyncAPI document (doc/documentation-design.md §9.3) or adds the VDA 5050
// documentation preset (doc/vda5050-design.md §9.1); both end in the same plan.
class ImportViewmodel extends SrxChangeNotifier {
  static const String modeField = 'mode';
  static const String versionField = 'version';
  static const String interfaceNameField = 'interfaceName';

  // the VDA 5050 preset instead of a file
  final bool preset;
  late final FormGroup form;
  String? fileName;
  String? error;
  ImportedDocumentation? imported;
  ImportPlan? plan;
  bool loading = false;
  final List<StreamSubscription> _subscriptions = [];
  // the preset requested last; an older one that finishes later is dropped
  int _presetRequest = 0;

  ImportViewmodel({this.preset = false}) {
    form = FormGroup({
      modeField: FormControl<ImportMode>(value: ImportMode.merge),
      if (preset) versionField: FormControl<VdaVersion>(value: VdaVersion.v3),
      if (preset)
        interfaceNameField: FormControl<String>(
            value: Vda5050Preset.defaultInterfaceName(VdaVersion.v3),
            validators: [Validators.required, Validators.delegate(_validateInterfaceName)]),
    });
    _subscriptions.add(form.control(modeField).valueChanges.listen((_) => notifyListeners()));
    if (preset) {
      _subscriptions
        ..add(form.control(versionField).valueChanges.listen((value) => _onVersionChanged(value as VdaVersion?)))
        ..add(form.control(interfaceNameField).valueChanges.listen((_) => loadPreset()));
    }
  }

  @override
  void dispose() {
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  VdaVersion get presetVersion => (form.control(versionField).value as VdaVersion?) ?? VdaVersion.v3;

  // builds the preset for the chosen version and interface name and compares it with the documentation
  Future<void> loadPreset() async {
    var request = ++_presetRequest;
    var interfaceName = Vda5050Preset.validInterfaceName((form.control(interfaceNameField).value as String?) ?? '');
    if (interfaceName == null) {
      imported = null;
      plan = null;
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();
    try {
      var built = await Vda5050Preset.build(presetVersion, interfaceName: interfaceName);
      if (request != _presetRequest) {
        return;
      }
      imported = built;
      plan = ImportPlan.of(GetIt.I.get<ProjectManager>().currentProject!.documentation, built.documentation);
      error = null;
    } catch (exc) {
      if (request != _presetRequest) {
        return;
      }
      imported = null;
      plan = null;
      error = '$exc';
    }
    loading = false;
    notifyListeners();
  }

  // the usual interface name follows the version unless the user chose another one
  void _onVersionChanged(VdaVersion? version) {
    var control = form.control(interfaceNameField);
    var other = Vda5050Preset.defaultInterfaceName(version == VdaVersion.v2 ? VdaVersion.v3 : VdaVersion.v2);
    if (control.value == other) {
      // changing the name loads the preset
      control.value = Vda5050Preset.defaultInterfaceName(version ?? VdaVersion.v3);
    } else {
      loadPreset();
    }
  }

  static Map<String, dynamic>? _validateInterfaceName(AbstractControl<dynamic> control) {
    var name = (control.value as String?) ?? '';
    return name.trim().isNotEmpty && Vda5050Preset.validInterfaceName(name) == null ? {'level': true} : null;
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
