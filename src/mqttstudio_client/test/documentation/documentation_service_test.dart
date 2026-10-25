import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/project/project_manager.dart';
import '../helpers/test_setup.dart';

void main() {
  late DocumentationService service;

  setUp(() async {
    setUpServices();
    service = GetIt.I.get<DocumentationService>();
    await openNewProject();
  });

  tearDown(tearDownServices);

  test('a project saved without documentation loads with an empty one', () {
    var json = createProject().toJson()..remove('documentation');
    var project = Project.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
    expect(project.documentation.nodes, isEmpty);
  });

  test('the documentation survives a JSON round trip', () {
    var project = createProject();
    project.documentation.nodes.add(DocNode(
        path: 'plant/{line}/temp',
        title: 'Temperature',
        status: DocStatus.stable,
        parameters: [DocParameter(name: 'line', pattern: r'\d+')],
        editedFields: {'title'},
        topic: TopicSpec(
            payload: PayloadSpec(
                format: PayloadFormat.json,
                schema: SchemaNode(
                    properties: {'temp': SchemaNode(type: SchemaType.number, unit: '°C')}, required: {'temp'})),
            retain: RetainMode.always,
            interval: IntervalSpec(kind: IntervalKind.periodic, nominalMs: 1000))));
    var copy = Project.fromJson(jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>);
    var node = copy.documentation.nodes.single;
    expect(node.title, 'Temperature');
    expect(node.editedFields, {'title'});
    expect(node.topic!.payload.schema!.properties['temp']!.unit, '°C');
    expect(node.topic!.payload.schema!.required, {'temp'});
    expect(node.topic!.interval.nominalMs, 1000);
  });

  test('editing the documentation marks the project as changed', () async {
    var manager = GetIt.I.get<ProjectManager>();
    expect(manager.hasProjectChanged(), isFalse);
    service.addNode(DocNode(path: 'plant/temp', topic: TopicSpec()));
    expect(manager.hasProjectChanged(), isTrue);
  });

  test('adding a node creates its parameters and keeps the nodes sorted', () {
    var events = 0;
    service.documentationChangedEvent.subscribe((_) => events++);
    service.addNode(DocNode(path: 'z/{id}'));
    service.addNode(DocNode(path: 'a/{line}/m{machine}'));
    expect(service.nodes.map((node) => node.path), ['a/{line}/m{machine}', 'z/{id}']);
    expect(service.nodeAt('a/{line}/m{machine}')!.parameters.map((p) => p.name), ['line', 'machine']);
    expect(events, 2);
  });

  test('conflicts are the same path or a template with the same shape', () {
    service.addNode(DocNode(path: 'a/{x}/c'));
    expect(service.conflictOf('a/{x}/c'), DocPathConflict.exists);
    expect(service.conflictOf('a/{y}/c'), DocPathConflict.sameShape);
    expect(service.conflictOf('a/b/c'), isNull);
    expect(service.conflictOf('a/{y}/c', ignore: {'a/{x}/c'}), isNull);
  });

  test('moving a namespace moves the nodes below it and keeps parameter descriptions', () {
    service.addNode(DocNode(path: 'plant/{line}', description: 'Lines'));
    service.addNode(DocNode(path: 'plant/{line}/temp', topic: TopicSpec()));
    service.addNode(DocNode(path: 'plant/old', status: DocStatus.deprecated, replacedBy: 'plant/{line}/temp'));
    service.nodeAt('plant/{line}/temp')!.parameters.single.description = 'Line number';

    service.movePath('plant/{line}', 'factory/{lineNo}');

    expect(service.nodes.map((node) => node.path), ['factory/{lineNo}', 'factory/{lineNo}/temp', 'plant/old']);
    var moved = service.nodeAt('factory/{lineNo}/temp')!;
    expect(moved.parameters.single.name, 'lineNo');
    expect(moved.parameters.single.description, 'Line number');
    expect(service.nodeAt('plant/old')!.replacedBy, 'factory/{lineNo}/temp');
  });

  test('a move onto an existing path is refused and changes nothing', () {
    service.addNode(DocNode(path: 'a/b'));
    service.addNode(DocNode(path: 'c/b'));
    expect(() => service.movePath('a', 'c'), throwsArgumentError);
    expect(service.nodes.map((node) => node.path), ['a/b', 'c/b']);
  });

  test('deleting a path deletes the nodes below it', () {
    service.addNode(DocNode(path: 'a'));
    service.addNode(DocNode(path: 'a/b'));
    service.addNode(DocNode(path: 'ab'));
    expect(service.deletePath('a'), 2);
    expect(service.nodes.map((node) => node.path), ['ab']);
  });

  test('clearing deletes every node and keeps the documentation texts', () {
    var documentation = GetIt.I.get<ProjectManager>().currentProject!.documentation..title = 'Plant';
    service.addNode(DocNode(path: 'a'));
    service.addNode(DocNode(path: 'a/b', topic: TopicSpec()));
    var events = 0;
    service.documentationChangedEvent.subscribe((_) => events++);
    expect(service.clearAll(), 2);
    expect(service.nodes, isEmpty);
    expect(documentation.title, 'Plant');
    expect(events, 1);
  });

  test('duplicating finds a free path', () {
    var node = DocNode(path: 'a/b', title: 'B', topic: TopicSpec());
    service.addNode(node);
    expect(service.duplicate(node).path, 'a/b_copy');
    var second = service.duplicate(node);
    expect(second.path, 'a/b_copy2');
    expect(second.title, 'B');
    expect(identical(second.topic, node.topic), isFalse);
  });

  test('ensureNode creates the node of an implicit namespace once', () {
    var node = service.ensureNode('plant');
    expect(service.ensureNode('plant'), same(node));
    expect(node.isTopic, isFalse);
  });

  test('a namespace becomes a topic and back', () {
    var node = service.ensureNode('plant/temp');
    service.setTopic(node, true);
    expect(node.isTopic, isTrue);
    service.setTopic(node, false);
    expect(node.topic, isNull);
  });
}
