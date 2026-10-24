import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/cli/duration_parser.dart';
import 'package:mqttstudio/recorder/tools/recording_import.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

// Viewmodel of the import dialog: the file, its format and the name of the new recording
class ImportViewmodel extends SrxChangeNotifier {
  static const String formatField = 'format';
  static const String nameField = 'name';
  static const String intervalField = 'interval';
  static const String fileField = 'file';

  late final FormGroup form = FormGroup({
    fileField: FormControl<String>(validators: [Validators.required]),
    formatField: FormControl<ImportFormat>(value: ImportFormat.mqttrec),
    nameField: FormControl<String>(validators: [Validators.required, Validators.maxLength(100)]),
    intervalField: FormControl<String>(value: '1s', validators: [Validators.delegate(_validateInterval)]),
  });
  late final StreamSubscription _subscription;
  String? _path;
  Uint8List? _bytes;

  ImportViewmodel() {
    _subscription = form.valueChanges.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  ImportFormat get format => form.control(formatField).value as ImportFormat? ?? ImportFormat.mqttrec;

  bool get needsInterval => format == ImportFormat.mosquittoVerbose;

  // a .mqttrec file keeps its own name
  bool get needsName => format != ImportFormat.mqttrec;

  // the browser hands over the bytes, the desktop the path
  Future<void> chooseFile() async {
    var picked = await FilePicker.pickFiles(dialogTitle: 'import.choose.title'.tr(), withData: kIsWeb);
    var file = picked?.files.single;
    if (file == null) {
      return;
    }
    _path = file.path;
    _bytes = file.bytes;
    var head = await _head(file);
    var format = RecordingImport.formatOf(file.name, head) ?? ImportFormat.mosquittoVerbose;
    var dot = file.name.lastIndexOf('.');
    form.control(fileField).value = file.name;
    form.control(formatField).value = format;
    form.control(nameField).value = dot > 0 ? file.name.substring(0, dot) : file.name;
    notifyListeners();
  }

  // the first line, to guess the format
  Future<String> _head(PlatformFile file) async {
    var bytes = file.bytes;
    if (bytes == null && file.path != null) {
      var stream = File(file.path!).openRead(0, 4096);
      bytes = Uint8List.fromList(await stream.fold<List<int>>([], (all, chunk) => all..addAll(chunk)));
    }
    if (bytes == null) {
      return '';
    }
    var text = utf8.decode(bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes, allowMalformed: true);
    return const LineSplitter().convert(text).firstOrNull ?? '';
  }

  ImportRequest? save() {
    if (!needsName) {
      form.control(nameField).markAsDisabled();
    } else {
      form.control(nameField).markAsEnabled();
    }
    form.markAllAsTouched();
    if (!form.valid) {
      return null;
    }
    var interval = ((form.control(intervalField).value as String?) ?? '').trim();
    return ImportRequest(
      form.control(fileField).value as String,
      format,
      ((form.control(nameField).value as String?) ?? '').trim(),
      path: _path,
      bytes: _bytes,
      interval: interval.isEmpty ? const Duration(seconds: 1) : DurationParser.parse(interval),
    );
  }

  static Map<String, dynamic>? _validateInterval(AbstractControl<dynamic> control) {
    var value = ((control.value as String?) ?? '').trim();
    if (value.isEmpty) {
      return null;
    }
    try {
      return DurationParser.parse(value) > Duration.zero ? null : {'duration': true};
    } on FormatException {
      return {'duration': true};
    }
  }
}

// Imports a recording: a .mqttrec file, JSON lines, CSV or mosquitto_sub output. Returns an ImportRequest or null.
class ImportDialog extends StatelessWidget {
  const ImportDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ImportViewmodel>(
      create: (_) => ImportViewmodel(),
      child: Consumer<ImportViewmodel>(builder: (context, vm, _) {
        return SimpleDialog(
          title: Text('import.title'.tr()),
          contentPadding: EdgeInsets.all(16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 480, maxWidth: 480),
              child: ReactiveForm(
                formGroup: vm.form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SrxFormRow(alignment: CrossAxisAlignment.center, children: [
                    Expanded(
                      child: ReactiveTextField<String>(
                        formControlName: ImportViewmodel.fileField,
                        readOnly: true,
                        decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'import.file.label'.tr(), isDense: true),
                        validationMessages: {ValidationMessage.required: (_) => 'import.nofile.error'.tr()},
                        onTap: (_) => vm.chooseFile(),
                      ),
                    ),
                    SizedBox(width: 16),
                    OutlinedButton(autofocus: true, onPressed: vm.chooseFile, child: Text('import.choose.button'.tr())),
                  ]),
                  SrxFormRow(children: [
                    Expanded(
                      child: ReactiveDropdownField<ImportFormat>(
                        formControlName: ImportViewmodel.formatField,
                        decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'import.format.label'.tr(), isDense: true),
                        items: [
                          for (var format in ImportFormat.values)
                            DropdownMenuItem(value: format, child: Text('import.format.${format.name}'.tr()))
                        ],
                      ),
                    ),
                  ]),
                  if (vm.needsName)
                    SrxFormRow(children: [
                      Expanded(
                        child: ReactiveTextField<String>(
                          formControlName: ImportViewmodel.nameField,
                          decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'import.name.label'.tr(), isDense: true),
                          validationMessages: {
                            ValidationMessage.required: (_) => 'srx.common.fieldrequired'.tr(),
                            ValidationMessage.maxLength: (_) => 'common.fieldcontenttolong.error'.tr(),
                          },
                          onSubmitted: (_) => _onImportPressed(vm),
                        ),
                      ),
                    ]),
                  if (vm.needsInterval)
                    SrxFormRow(children: [
                      Expanded(
                        child: ReactiveTextField<String>(
                          formControlName: ImportViewmodel.intervalField,
                          decoration: InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'import.interval.label'.tr(),
                              helperText: 'import.interval.helper'.tr(),
                              isDense: true),
                          validationMessages: {'duration': (_) => 'recorddialog.duration.error'.tr()},
                          onSubmitted: (_) => _onImportPressed(vm),
                        ),
                      ),
                    ]),
                  SizedBox(height: 16),
                  SrxFormRow(alignment: CrossAxisAlignment.center, children: [
                    Spacer(flex: 1),
                    Expanded(
                        flex: 5,
                        child: OutlinedButton(
                            onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null),
                            child: Text('srx.common.cancel'.tr()))),
                    SizedBox(width: 16),
                    Expanded(
                        flex: 5,
                        child: ElevatedButton(onPressed: () => _onImportPressed(vm), child: Text('import.import.button'.tr()))),
                  ]),
                ]),
              ),
            ),
          ],
        );
      }),
    );
  }

  void _onImportPressed(ImportViewmodel vm) {
    var request = vm.save();
    if (request != null) {
      GetIt.I.get<SrxNavigationService>().pop(request);
    }
  }
}
