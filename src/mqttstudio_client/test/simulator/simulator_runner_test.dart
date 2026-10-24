import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/simulator/engine/simulator_publisher.dart';
import 'package:mqttstudio/simulator/engine/simulator_runner.dart';
import 'package:mqttstudio/simulator/model/payload_generators.dart';
import 'package:mqttstudio/simulator/model/simulation.dart';
import 'package:typed_data/typed_buffers.dart';

class SentMessage {
  final String topic;
  final String payload;
  final MqttQos qos;
  final bool retain;
  final MqttMessageProperties? properties;
  final Duration at;

  SentMessage(this.topic, this.payload, this.qos, this.retain, this.properties, this.at);
}

class FakePublisher implements SimulatorPublisher {
  final FakeAsync async;
  final List<SentMessage> sent = [];
  @override
  bool isConnected = true;
  @override
  bool supportsProperties = true;

  FakePublisher(this.async);

  @override
  void publish(String topic, Uint8Buffer payload, MqttQos qos, bool retain, MqttMessageProperties? properties) {
    sent.add(SentMessage(topic, utf8.decode(payload), qos, retain, properties, async.elapsed));
  }

  List<SentMessage> to(String topic) => sent.where((m) => m.topic == topic).toList();
}

SimulatedTopic counterTopic(String topic, {int minMs = 1000, int? maxMs}) =>
    SimulatedTopic(topic: topic, generator: const CounterGenerator(), interval: PublishInterval(minMs: minMs, maxMs: maxMs));

void main() {
  test('publishes every interval after a first message within one interval', () {
    fakeAsync((async) {
      var publisher = FakePublisher(async);
      var runner = SimulatorRunner(publisher, seed: 1);
      var device = SimulatedDevice(name: 'd', topics: [counterTopic('a')]);

      runner.startDevice(device);
      expect(runner.isRunning(device.topics.single.id), isTrue);
      async.elapse(const Duration(milliseconds: 999));
      expect(publisher.sent.length, lessThanOrEqualTo(1));
      async.elapse(const Duration(seconds: 10));

      var messages = publisher.to('a');
      expect(messages.length, inInclusiveRange(10, 11));
      expect(messages.map((m) => m.payload).take(3), ['1', '2', '3']);
      for (var i = 1; i < messages.length; i++) {
        expect(messages[i].at - messages[i - 1].at, const Duration(seconds: 1));
      }
      runner.dispose();
    });
  });

  test('instances resolve {n}, are staggered and keep their own state', () {
    fakeAsync((async) {
      var publisher = FakePublisher(async);
      var runner = SimulatorRunner(publisher, seed: 3);
      var device = SimulatedDevice(name: 'd', instanceCount: 5, firstInstance: 1, topics: [counterTopic('t/{n}')]);

      runner.startDevice(device);
      async.elapse(const Duration(milliseconds: 1000));
      var firstTimes = [for (var n = 1; n <= 5; n++) publisher.to('t/$n').first.at];
      expect(firstTimes.toSet().length, greaterThan(1));
      async.elapse(const Duration(seconds: 5));
      for (var n = 1; n <= 5; n++) {
        expect(publisher.to('t/$n').map((m) => m.payload).take(3), ['1', '2', '3']);
      }
      var stats = runner.statsOf(device.topics.single.id);
      expect(stats.sent, publisher.sent.length);
      expect(stats.lastInstance, inInclusiveRange(1, 5));
      runner.dispose();
    });
  });

  test('random intervals stay in their range', () {
    fakeAsync((async) {
      var publisher = FakePublisher(async);
      var runner = SimulatorRunner(publisher, seed: 5);
      runner.startDevice(SimulatedDevice(name: 'd', topics: [counterTopic('a', minMs: 200, maxMs: 600)]));
      async.elapse(const Duration(seconds: 60));
      var messages = publisher.sent;
      var gaps = [for (var i = 1; i < messages.length; i++) (messages[i].at - messages[i - 1].at).inMilliseconds];
      expect(gaps.every((gap) => gap >= 200 && gap <= 600), isTrue);
      expect(gaps.toSet().length, greaterThan(5));
      runner.dispose();
    });
  });

  test('stop, stopDevice and stopAll end the timers', () {
    fakeAsync((async) {
      var publisher = FakePublisher(async);
      var runner = SimulatorRunner(publisher, seed: 1);
      var a = counterTopic('a');
      var b = counterTopic('b');
      var device = SimulatedDevice(name: 'd', topics: [a, b]);
      runner.startDevice(device);
      async.elapse(const Duration(seconds: 3));
      runner.stopTopic(a.id);
      var sentToA = publisher.to('a').length;
      async.elapse(const Duration(seconds: 3));
      expect(publisher.to('a').length, sentToA);
      expect(runner.isRunning(b.id), isTrue);
      runner.stopAll();
      var sent = publisher.sent.length;
      async.elapse(const Duration(seconds: 3));
      expect(publisher.sent.length, sent);
      expect(runner.isAnyRunning, isFalse);
      expect(runner.stateOf(a.id), TopicRunState.stopped);
    });
  });

  test('a topic that cannot start gets an error, the others run', () {
    fakeAsync((async) {
      var publisher = FakePublisher(async);
      var runner = SimulatorRunner(publisher, seed: 1);
      var errors = <String>[];
      runner.topicErrorEvent.subscribe((args) => errors.add(args.message));
      var images = SimulatedTopic(topic: 'img/{n}', generator: const RandomImageGenerator(folderPath: r'Z:\does\not\exist'));
      var invalid = counterTopic('no/instance');
      var good = counterTopic('ok/{n}');
      var device = SimulatedDevice(name: 'd', instanceCount: 2, topics: [images, invalid, good]);

      runner.startDevice(device);
      async.elapse(const Duration(seconds: 3));
      expect(runner.stateOf(images.id), TopicRunState.error);
      expect(runner.statsOf(images.id).error, contains('Image folder not found'));
      expect(runner.stateOf(invalid.id), TopicRunState.error);
      expect(runner.statsOf(invalid.id).error, contains('{n}'));
      expect(runner.stateOf(good.id), TopicRunState.running);
      expect(publisher.to('ok/1'), isNotEmpty);
      expect(errors.length, 2);
      expect(runner.errorCount, 2);
      runner.dispose();
    });
  });

  test('a lost connection is reported once, messages are skipped and resume after a reconnect', () {
    fakeAsync((async) {
      var publisher = FakePublisher(async);
      var runner = SimulatorRunner(publisher, seed: 1);
      var lost = 0;
      runner.connectionLostEvent.subscribe((_) => lost++);
      runner.startDevice(SimulatedDevice(name: 'd', topics: [counterTopic('a')]));
      async.elapse(const Duration(seconds: 2));
      var before = publisher.sent.length;

      publisher.isConnected = false;
      async.elapse(const Duration(seconds: 5));
      expect(lost, 1);
      expect(publisher.sent.length, before);

      publisher.isConnected = true;
      async.elapse(const Duration(seconds: 3));
      expect(publisher.sent.length, greaterThan(before));
      runner.dispose();
    });
  });

  test('restart applies a new configuration and resets the generator state', () {
    fakeAsync((async) {
      var publisher = FakePublisher(async);
      var runner = SimulatorRunner(publisher, seed: 1);
      var topic = counterTopic('a');
      var device = SimulatedDevice(name: 'd', topics: [topic]);
      runner.startDevice(device);
      async.elapse(const Duration(seconds: 5));

      topic.generator = const CounterGenerator(start: 100);
      runner.restart(device, [topic]);
      publisher.sent.clear();
      async.elapse(const Duration(seconds: 2));
      expect(publisher.sent.first.payload, '100');
      runner.dispose();
    });
  });

  test('sends MQTT 5 properties with placeholders and the generator content type', () {
    fakeAsync((async) {
      var publisher = FakePublisher(async);
      var runner = SimulatorRunner(publisher, seed: 1);
      var topic = SimulatedTopic(
          topic: 't/{n}',
          qos: MqttQos.atLeastOnce,
          retain: true,
          generator: const TemplateGenerator(template: '{"a":1}'),
          mqtt5: Mqtt5PublishProperties(
              messageExpirySeconds: 30, userProperties: [SimulatedUserProperty('device', '{device}-{n:3}')]));
      runner.startDevice(SimulatedDevice(name: 'Line', instanceCount: 2, firstInstance: 7, topics: [topic]));
      async.elapse(const Duration(seconds: 1));

      var message = publisher.to('t/7').first;
      expect(message.qos, MqttQos.atLeastOnce);
      expect(message.retain, isTrue);
      expect(message.properties!.contentType, 'application/json');
      expect(message.properties!.messageExpiryInterval, 30);
      expect(message.properties!.payloadFormatUtf8, isTrue);
      expect(message.properties!.userProperties.single.value, 'Line-007');

      publisher.supportsProperties = false;
      async.elapse(const Duration(seconds: 1));
      expect(publisher.sent.last.properties, isNull);
      runner.dispose();
    });
  });

  test('the same seed gives the same payloads', () {
    List<String> payloads(int seed) {
      late List<String> result;
      fakeAsync((async) {
        var publisher = FakePublisher(async);
        var runner = SimulatorRunner(publisher, seed: seed);
        var device = SimulatedDevice(
            id: 'device', name: 'd', topics: [SimulatedTopic(id: 'topic', topic: 'a', generator: const RandomNumberGenerator())]);
        runner.startDevice(device);
        async.elapse(const Duration(seconds: 20));
        result = publisher.sent.map((m) => m.payload).toList();
        runner.dispose();
      });
      return result;
    }

    expect(payloads(42), payloads(42));
    expect(payloads(42), isNot(payloads(43)));
  });

  test('stats are reported at most every 500 ms and running rate is estimated', () {
    fakeAsync((async) {
      var publisher = FakePublisher(async);
      var runner = SimulatorRunner(publisher, seed: 1);
      var events = 0;
      runner.statsChangedEvent.subscribe((_) => events++);
      runner.startDevice(SimulatedDevice(name: 'd', instanceCount: 10, topics: [counterTopic('t/{n}', minMs: 100)]));
      async.elapse(const Duration(seconds: 5));
      expect(publisher.sent.length, greaterThan(400));
      expect(events, inInclusiveRange(9, 11));
      expect(runner.runningRate, closeTo(100, 1e-9));
      runner.dispose();
    });
  });

  test('clearRetained publishes empty retained messages to every instance of retained topics', () {
    fakeAsync((async) {
      var publisher = FakePublisher(async);
      var runner = SimulatorRunner(publisher);
      var retained = counterTopic('r/{n}')..retain = true;
      var device = SimulatedDevice(name: 'd', instanceCount: 3, topics: [retained, counterTopic('x/{n}')]);
      expect(runner.clearRetained(device.topics.map((t) => (device, t))), 3);
      expect(publisher.sent.map((m) => (m.topic, m.payload, m.retain)), [('r/1', '', true), ('r/2', '', true), ('r/3', '', true)]);
    });
  });

  test('reset clears the statistics', () {
    fakeAsync((async) {
      var publisher = FakePublisher(async);
      var runner = SimulatorRunner(publisher, seed: 1);
      var topic = counterTopic('a');
      runner.startDevice(SimulatedDevice(name: 'd', topics: [topic]));
      async.elapse(const Duration(seconds: 3));
      expect(runner.statsOf(topic.id).sent, greaterThan(0));
      runner.reset();
      expect(runner.statsOf(topic.id).sent, 0);
      expect(runner.isAnyRunning, isFalse);
    });
  });
}
