import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/doc_node_editor_model.dart';
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/documentation/documentation_viewmodel.dart';
import 'package:mqttstudio/documentation/engine/doc_tree.dart';
import 'package:mqttstudio/documentation/engine/schema_paths.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/documentation/widgets/doc_format.dart';
import '../helpers/test_setup.dart';

void main() {
  group('SchemaPaths', () {
    test('parses and joins field paths', () {
      expect(SchemaPaths.parse(r'$.a.b'), ['a', 'b']);
      expect(SchemaPaths.parse(r'$.alarms[].code'), ['alarms', '[]', 'code']);
      expect(SchemaPaths.parse(r'$[]'), ['[]']);
      expect(SchemaPaths.parse(r'$'), isNull);
      expect(SchemaPaths.parse(r'$.'), isNull);
      expect(SchemaPaths.parse('a.b'), isNull);
      expect(SchemaPaths.join(['alarms', '[]', 'code']), r'$.alarms[].code');
    });

    test('put creates the objects and arrays above a field, flatten lists them', () {
      var schema = SchemaNode();
      SchemaPaths.put(schema, r'$.state', SchemaNode(type: SchemaType.string), required: true);
      SchemaPaths.put(schema, r'$.alarms[].code', SchemaNode(type: SchemaType.integer), required: true);
      var rows = SchemaPaths.flatten(schema);
      expect(rows.map((row) => row.path), [r'$.state', r'$.alarms', r'$.alarms[]', r'$.alarms[].code']);
      expect(rows.map((row) => row.required), [true, false, false, true]);
      expect(SchemaPaths.find(schema, r'$.alarms')!.type, SchemaType.array);
      expect(SchemaPaths.find(schema, r'$.alarms[]')!.type, SchemaType.object);
    });

    test('replacing a field keeps the fields below it, remove deletes it', () {
      var schema = SchemaNode();
      SchemaPaths.put(schema, r'$.a.b', SchemaNode(type: SchemaType.number), required: false);
      SchemaPaths.put(schema, r'$.a', SchemaNode(description: 'A'), required: true);
      expect(SchemaPaths.find(schema, r'$.a.b'), isNotNull);
      expect(schema.required, {'a'});
      SchemaPaths.remove(schema, r'$.a');
      expect(SchemaPaths.flatten(schema), isEmpty);
      expect(schema.required, isEmpty);
    });
  });

  group('DocFormat', () {
    test('durations', () {
      expect(DocFormat.parseDuration('500 ms'), 500);
      expect(DocFormat.parseDuration('10 s'), 10000);
      expect(DocFormat.parseDuration('10'), 10000);
      expect(DocFormat.parseDuration('1,5 min'), 90000);
      expect(DocFormat.parseDuration('2h'), 7200000);
      expect(DocFormat.parseDuration('soon'), isNull);
      expect(DocFormat.duration(90000), '1.5 min');
      expect(DocFormat.duration(10000), '10 s');
      expect(DocFormat.duration(250), '250 ms');
    });
  });

  group('editors', () {
    late DocumentationService service;

    setUp(() async {
      setUpServices();
      service = GetIt.I.get<DocumentationService>();
      await openNewProject();
    });

    tearDown(tearDownServices);

    test('a change goes to the node and into its edited fields', () async {
      var node = DocNode(path: 'plant/{line}/temp', topic: TopicSpec());
      service.addNode(node);
      var editor = DocNodeEditorModel(node.path, node);
      editor.form.control(DocNodeEditorModel.title).value = 'Temperature';
      editor.form.control(DocNodeEditorModel.qos).value = MqttQos.atLeastOnce;
      editor.form.control(DocNodeEditorModel.nominalInterval).value = '10 s';
      (editor.form.control(DocNodeEditorModel.parameters) as dynamic).controls[0].control('pattern').value = r'\d+';
      await Future.delayed(Duration.zero);
      expect(node.title, 'Temperature');
      expect(node.topic!.qos, MqttQos.atLeastOnce);
      expect(node.topic!.interval.nominalMs, 10000);
      expect(node.parameters.single.pattern, r'\d+');
      expect(node.editedFields, {
        DocNodeEditorModel.title,
        DocNodeEditorModel.qos,
        DocNodeEditorModel.nominalInterval,
        DocNodeEditorModel.parameters
      });
      editor.dispose();
    });

    test('an invalid duration keeps the documented one', () async {
      var node = DocNode(path: 'a', topic: TopicSpec(interval: IntervalSpec(nominalMs: 1000)));
      service.addNode(node);
      var editor = DocNodeEditorModel(node.path, node);
      editor.form.control(DocNodeEditorModel.nominalInterval).value = 'later';
      await Future.delayed(Duration.zero);
      expect(node.topic!.interval.nominalMs, 1000);
      expect(editor.form.control(DocNodeEditorModel.nominalInterval).hasError('duration'), isTrue);
      editor.dispose();
    });

    test('editing an implicit namespace creates its node', () async {
      service.addNode(DocNode(path: 'plant/line1/temp', topic: TopicSpec()));
      var editor = DocNodeEditorModel('plant', null);
      expect(service.nodeAt('plant'), isNull);
      editor.form.control(DocNodeEditorModel.description).value = 'The plant';
      await Future.delayed(Duration.zero);
      expect(service.nodeAt('plant')!.description, 'The plant');
      expect(editor.node, same(service.nodeAt('plant')));
      editor.dispose();
    });

    test('schema fields are added, moved and removed', () {
      var node = DocNode(path: 'a', topic: TopicSpec(payload: PayloadSpec(format: PayloadFormat.json)));
      service.addNode(node);
      var editor = DocNodeEditorModel(node.path, node);
      editor.putSchemaField(null, r'$.temp', SchemaNode(type: SchemaType.number, unit: '°C'), required: true);
      editor.putSchemaField(r'$.temp', r'$.temperature', SchemaNode(type: SchemaType.number, unit: 'K'),
          required: true);
      expect(SchemaPaths.flatten(node.topic!.payload.schema).map((row) => row.path), [r'$.temperature']);
      expect(node.editedFields, containsAll(['schema:\$.temp', 'schema:\$.temperature']));
      editor.removeSchemaField(r'$.temperature');
      expect(SchemaPaths.flatten(node.topic!.payload.schema), isEmpty);
      editor.dispose();
    });

    test('the viewmodel filters, selects and follows a move', () {
      var vm = DocumentationViewmodel();
      service.addNode(DocNode(path: 'plant/{line}/temp', description: 'Temperature', topic: TopicSpec()));
      service.addNode(DocNode(path: 'plant/{line}/speed', topic: TopicSpec()));
      expect(vm.topicCount, 2);
      expect(vm.undocumentedCount, 1);

      vm.setFilter(DocFilter.undocumented);
      expect(vm.rows.map((row) => row.entry.path), [null, 'plant', 'plant/{line}', 'plant/{line}/speed']);
      vm.setFilter(DocFilter.all);
      vm.setSearch('TEMPERATURE');
      expect(vm.rows.last.entry.path, 'plant/{line}/temp');
      vm.setSearch('');

      vm.select('plant/{line}/temp');
      expect(vm.editor!.isTopic, isTrue);
      vm.movePath('plant/{line}', 'plant/{lineNo}');
      expect(vm.selectedPath, 'plant/{lineNo}/temp');
      expect(vm.editor!.path, 'plant/{lineNo}/temp');

      vm.deletePath('plant');
      expect(vm.selectedPath, isNull);
      expect(vm.rootEditor, isNotNull);
      vm.dispose();
    });

    test('the tree counts topics and undocumented ones per level', () {
      var tree = DocTreeEntry.build([
        DocNode(path: 'a/b', topic: TopicSpec()),
        DocNode(path: 'a/c', description: 'C', topic: TopicSpec()),
        DocNode(path: 'a'),
      ]);
      var a = tree.children.single;
      expect(a.node, isNotNull);
      expect(a.topicCount, 2);
      expect(a.undocumentedCount, 1);
      expect(a.children.map((child) => child.segment), ['b', 'c']);
    });
  });
}
