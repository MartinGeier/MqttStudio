import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/simulator/device_edit_viewmodel.dart';
import 'package:mqttstudio/simulator/generator_editor_model.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:mqttstudio/simulator/topic_edit_viewmodel.dart';
import '../helpers/test_setup.dart';

void main() {
  setUp(() => setUpServices());
  tearDown(tearDownServices);

  group('GeneratorEditorModel', () {
    test('builds the generator from its form', () {
      var model = GeneratorEditorModel(const RandomWalkGenerator(start: 5));
      model.form.control(GeneratorEditorModel.max).value = 9.0;
      var built = model.build() as RandomWalkGenerator;
      expect(built.start, 5);
      expect(built.max, 9);
      model.dispose();
    });

    test('keeps the values of a type when switching back and forth', () {
      var model = GeneratorEditorModel(const CounterGenerator());
      model.form.control(GeneratorEditorModel.prefix).value = 'ORD-';
      model.typeControl.value = GeneratorType.boolean;
      expect(model.build(), isA<BoolGenerator>());
      model.typeControl.value = GeneratorType.counter;
      expect((model.build() as CounterGenerator).prefix, 'ORD-');
      model.dispose();
    });

    test('a template field cannot be a template or an image', () {
      var model = GeneratorEditorModel(const CounterGenerator(), isTemplateField: true);
      expect(model.availableTypes, isNot(contains(GeneratorType.template)));
      expect(model.availableTypes, isNot(contains(GeneratorType.randomImage)));
      model.dispose();
    });

    test('template references must name a field', () {
      var model = GeneratorEditorModel(const TemplateGenerator(template: '{{a}}'));
      expect(model.validate(), isFalse);
      model.addTemplateField(TemplateField('a', const CounterGenerator()));
      expect(model.validate(), isTrue);
      var built = model.build() as TemplateGenerator;
      expect(built.fields.keys, ['a']);
      model.dispose();
    });

    test('switching to the template type brings the fields of the example template', () {
      var model = GeneratorEditorModel(const CounterGenerator());
      model.typeControl.value = GeneratorType.template;
      expect(model.validate(), isTrue);
      expect(model.templateFields.map((f) => f.name), ['value', 'ts']);
      model.dispose();
    });

    test('value lists and waypoints are read one per line', () {
      var list = GeneratorEditorModel(const ValueListGenerator());
      list.form.control(GeneratorEditorModel.values).value = 'ok\n warning \n\nerror';
      expect((list.build() as ValueListGenerator).values, ['ok', 'warning', 'error']);

      var gps = GeneratorEditorModel(const GpsTrackGenerator());
      gps.form.control(GeneratorEditorModel.mode).value = GpsMode.route;
      gps.form.control(GeneratorEditorModel.waypoints).value = '48.1,11.5';
      expect(gps.validate(), isFalse);
      gps.form.control(GeneratorEditorModel.waypoints).value = '48.1,11.5\n48.2, 11.6';
      expect(gps.validate(), isTrue);
      expect((gps.build() as GpsTrackGenerator).waypoints.last.lon, 11.6);
      expect(GeneratorEditorModel.parseWaypoints('91,0'), isNull);
      list.dispose();
      gps.dispose();
    });

    test('the preview generates samples and recognizes numbers and invalid JSON', () {
      var model = GeneratorEditorModel(const CounterGenerator());
      model.generatePreview();
      expect(model.preview!.samples.take(3), ['1', '2', '3']);
      expect(model.preview!.numbers, isNotNull);

      var template = GeneratorEditorModel(const TemplateGenerator(template: '{"a": oops}'));
      template.generatePreview();
      expect(template.preview!.invalidJson, isTrue);
      model.dispose();
      template.dispose();
    });
  });

  group('TopicEditViewmodel', () {
    test('saves the edited topic with interval range and MQTT 5 properties', () async {
      var project = await openNewProject();
      project.mqttSettings.protocolVersion = MqttProtocolVersion.v5;
      var device = SimulatedDevice(name: 'd', instanceCount: 2);
      var vm = TopicEditViewmodel(device, null);
      expect(vm.isNew, isTrue);
      vm.form.control(TopicEditViewmodel.topicField).value = 'w/{n}/t';
      vm.form.control(TopicEditViewmodel.intervalField).value = 500;
      vm.form.control(TopicEditViewmodel.upToField).value = 900;
      vm.form.control(TopicEditViewmodel.qosField).value = MqttQos.atLeastOnce;
      vm.form.control(TopicEditViewmodel.contentTypeField).value = 'text/plain';
      vm.addUserProperty();
      vm.form.control('${TopicEditViewmodel.userPropertiesField}.0.${TopicEditViewmodel.userPropertyKeyField}').value = 'k';

      var topic = vm.save()!;
      expect(topic.topic, 'w/{n}/t');
      expect(topic.interval.minMs, 500);
      expect(topic.interval.maxMs, 900);
      expect(topic.qos, MqttQos.atLeastOnce);
      expect(topic.mqtt5.contentType, 'text/plain');
      expect(topic.mqtt5.userProperties.single.key, 'k');
      expect(vm.resolvedRange, 'w/1/t … w/2/t');
      expect(vm.mqttSummary, contains('QoS 1'));
      vm.dispose();
    });

    test('rejects topics without {n} on multi-instance devices, wildcards and a reversed range', () async {
      await openNewProject();
      var vm = TopicEditViewmodel(SimulatedDevice(name: 'd', instanceCount: 2), null);
      vm.form.control(TopicEditViewmodel.topicField).value = 'w/t';
      expect(vm.save(), isNull);
      vm.form.control(TopicEditViewmodel.topicField).value = 'w/+/{n}';
      expect(vm.save(), isNull);
      vm.form.control(TopicEditViewmodel.topicField).value = 'w/{n}';
      vm.form.control(TopicEditViewmodel.intervalField).value = 1000;
      vm.form.control(TopicEditViewmodel.upToField).value = 500;
      expect(vm.save(), isNull);
      vm.form.control(TopicEditViewmodel.upToField).value = null;
      expect(vm.save()!.interval.isRandom, isFalse);
      vm.dispose();
    });

    test('keeps the id of an edited topic', () async {
      await openNewProject();
      var topic = SimulatedTopic(topic: 'a', generator: const BoolGenerator());
      var vm = TopicEditViewmodel(SimulatedDevice(name: 'd'), topic);
      expect(vm.save()!.id, topic.id);
      expect(vm.generator.type, GeneratorType.boolean);
      vm.dispose();
    });
  });

  group('DeviceEditViewmodel', () {
    test('proposes a free name and rejects duplicates', () {
      var simulation = Simulation(devices: [SimulatedDevice(name: 'Device 2')]);
      var vm = DeviceEditViewmodel(null, simulation);
      expect(vm.form.control(DeviceEditViewmodel.nameField).value, 'Device 3');
      vm.form.control(DeviceEditViewmodel.nameField).value = 'device 2';
      expect(vm.save(), isNull);
    });

    test('saves name and instances and keeps the topics', () {
      var device = SimulatedDevice(name: 'd', topics: [SimulatedTopic(topic: 't/{n}', generator: const BoolGenerator())]);
      var vm = DeviceEditViewmodel(device, Simulation(devices: [device]));
      vm.form.control(DeviceEditViewmodel.instanceCountField).value = 10;
      vm.form.control(DeviceEditViewmodel.firstInstanceField).value = 5;
      expect(vm.resolvedTopics, ['t/5 … t/14']);
      expect(vm.rate, closeTo(10, 1e-9));
      var saved = vm.save()!;
      expect(saved.id, device.id);
      expect(saved.instanceCount, 10);
      expect(saved.topics.single.topic, 't/{n}');
      expect(device.instanceCount, 1);
    });

    test('warns about topics without {n} and limits the instances', () {
      var device = SimulatedDevice(name: 'd', topics: [SimulatedTopic(topic: 't', generator: const BoolGenerator())]);
      var vm = DeviceEditViewmodel(device, Simulation(devices: [device]));
      vm.form.control(DeviceEditViewmodel.instanceCountField).value = 2;
      expect(vm.hasTopicsWithoutInstance, isTrue);
      vm.form.control(DeviceEditViewmodel.instanceCountField).value = 1001;
      expect(vm.save(), isNull);
    });
  });
}
