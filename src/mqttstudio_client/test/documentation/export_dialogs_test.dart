import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/documentation/documentation_page.dart';
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/documentation/documentation_viewmodel.dart';
import 'package:mqttstudio/documentation/export/doc_export.dart';
import 'package:mqttstudio/documentation/export/import_merge.dart';
import 'package:mqttstudio/documentation/export_dialog.dart';
import 'package:mqttstudio/documentation/export_viewmodel.dart';
import 'package:mqttstudio/documentation/import_viewmodel.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/documentation/schema_json_viewmodel.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';

String asyncApi(List<String> paths) => DocExport.run(
    TopicDocumentation(title: 'Imported', nodes: [
      for (var path in paths) DocNode(path: path, title: 'Title of $path', topic: TopicSpec()),
    ]),
    DocExportOptions(DocExportFormat.asyncapiYaml));

void main() {
  setUpAll(loadTranslations);

  setUp(() async {
    setUpServices();
    GetIt.I.registerSingleton(SrxNavigationService(Container(), Container()));
    await openNewProject();
  });

  tearDown(tearDownServices);

  group('ExportViewmodel', () {
    test('the file name follows the format, CSV disables the details', () async {
      var vm = ExportViewmodel(title: 'Demo: factory', selectedPath: 'plant');
      expect(vm.form.control(ExportViewmodel.fileNameField).value, 'Demo- factory.md');
      vm.form.control(ExportViewmodel.fileNameField).value = 'mine.md';
      vm.form.control(ExportViewmodel.formatField).value = DocExportFormat.asyncapiYaml;
      await pumpEventQueue();
      expect(vm.form.control(ExportViewmodel.fileNameField).value, 'mine.asyncapi.yaml');
      vm.form.control(ExportViewmodel.formatField).value = DocExportFormat.csv;
      await pumpEventQueue();
      expect(vm.form.control(ExportViewmodel.fileNameField).value, 'mine.csv');
      expect(vm.form.control(ExportViewmodel.examplesField).enabled, isFalse);
      vm.form.control(ExportViewmodel.scopeField).value = 'plant';
      var request = vm.save()!;
      expect(request.options.format, DocExportFormat.csv);
      expect(request.options.scope, 'plant');
      expect(request.fileName, 'mine.csv');
      vm.dispose();
    });
  });

  group('ImportViewmodel', () {
    test('plans the import of a file and rejects what is no AsyncAPI', () {
      var service = GetIt.I.get<DocumentationService>();
      service.addNode(DocNode(path: 'a/b', title: 'Title of a/b', topic: TopicSpec()));
      var vm = ImportViewmodel();
      vm.load('topics.yaml', asyncApi(['a/b', 'a/c']));
      expect(vm.error, isNull);
      expect(vm.plan!.countOf(ImportState.same), 1);
      expect(vm.plan!.countOf(ImportState.added), 1);
      expect(vm.canImport, isTrue);
      vm.setAccept(vm.plan!.items.firstWhere((item) => item.state == ImportState.added), false);
      expect(vm.canImport, isFalse);
      vm.form.control(ImportViewmodel.modeField).value = ImportMode.replaceAll;
      expect(vm.canImport, isTrue);

      vm.load('broken.json', '{"no": "asyncapi"}');
      expect(vm.error, contains('asyncapi'));
      expect(vm.canImport, isFalse);
      vm.dispose();
    });

    test('applying an import adds the topics and marks the project as changed', () {
      var documentationVm = DocumentationViewmodel();
      var vm = ImportViewmodel()..load('topics.yaml', asyncApi(['x/y', 'x/z']));
      documentationVm.importDocumentation(vm.save()!);
      expect(GetIt.I.get<DocumentationService>().nodes.map((node) => node.path), ['x/y', 'x/z']);
      expect(documentationVm.topicCount, 2);
      vm.dispose();
      documentationVm.dispose();
    });
  });

  test('a schema edited as JSON round trips and names what it leaves out', () {
    var schema = SchemaNode(
        properties: {'temp': SchemaNode(type: SchemaType.number, unit: '°C', maximum: 120)}, required: {'temp'});
    var vm = SchemaJsonViewmodel(schema);
    var saved = vm.save()!;
    expect(saved.toJson(), schema.toJson());
    expect(vm.warnings, isEmpty);

    vm.form.control(SchemaJsonViewmodel.textField).value = '{"type": "object", "properties": {"a": {"oneOf": []}}}';
    expect(vm.save()!.properties.keys, ['a']);
    expect(vm.warnings.single, contains('oneOf'));

    vm.form.control(SchemaJsonViewmodel.textField).value = '[1, 2]';
    expect(vm.save(), isNull);
    vm.form.control(SchemaJsonViewmodel.textField).value = '{broken';
    expect(vm.save(), isNull);
    vm.dispose();
  });

  testWidgets('the export dialog returns the chosen format and scope', (tester) async {
    await ignoringOverflowErrors(() async {
      await tester.binding.setSurfaceSize(Size(1600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(testApp(DialogHost(ExportDialog(title: 'Demo', selectedPath: 'plant'))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Export Documentation'), findsOneWidget);
      expect(find.textContaining('never exported'), findsOneWidget);
      await tester.tap(find.text('Markdown'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AsyncAPI 3.0 (YAML)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('EXPORT'));
      await tester.pumpAndSettle();
      var request = tester.state<DialogHostState>(find.byType(DialogHost)).result as DocExportRequest;
      expect(request.options.format, DocExportFormat.asyncapiYaml);
      expect(request.options.scope, isNull);
      expect(request.fileName, 'Demo.asyncapi.yaml');
    });
  });

  testWidgets('IMPORT and EXPORT are in the command bar', (tester) async {
    await ignoringOverflowErrors(() async {
      await tester.binding.setSurfaceSize(Size(1600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(testApp(DocumentationPage()));
      await tester.pumpAndSettle();
      expect(find.text('IMPORT'), findsOneWidget);
      await tester.tap(find.text('EXPORT'));
      await tester.pumpAndSettle();
      expect(find.text('Export Documentation'), findsOneWidget);
    });
  });
}
