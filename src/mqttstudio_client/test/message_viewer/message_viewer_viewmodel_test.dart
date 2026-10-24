import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/message_viewer/message_buffer.dart';
import 'package:mqttstudio/message_viewer/message_viewer.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/model/mqtt_payload_type.dart';
import 'package:mqttstudio/project/project_manager.dart';
import '../helpers/fake_mqtt_adapter.dart';
import '../helpers/test_setup.dart';

void main() {
  late FakeMqttAdapter adapter;
  late MessageViewerViewmodel viewmodel;
  var start = DateTime(2026, 10, 23, 12);

  setUp(() async {
    adapter = setUpServices();
    var project = await openNewProject();
    await adapter.connect(project.mqttSettings);
    viewmodel = MessageViewerViewmodel();
  });

  tearDown(tearDownServices);

  // receives the payloads on one topic, one second apart, and selects the last message
  void receiveAndSelect(String topic, List<String> payloads) {
    for (var i = 0; i < payloads.length; i++) {
      adapter.receive(message(topic, payloads[i], receivedOn: start.add(Duration(seconds: i))));
    }
    viewmodel.selectedMessage = viewmodel.messageBuffer.getLastMessageForTopic(topic);
  }

  group('MessageViewerViewmodel defaults', () {
    test('starts grouped by ten seconds without selection', () {
      expect(viewmodel.topicViewMode, TopicViewMode.Grouped);
      expect(viewmodel.groupTimePeriod, MessageGroupTimePeriod.tenSeconds);
      expect(viewmodel.selectedMessage, isNull);
      expect(viewmodel.getSelectedMessageCount(), 0);
      expect(viewmodel.getValues(), isEmpty);
      expect(viewmodel.getMinValue(), isNull);
    });

    test('notifies when the view settings change', () {
      var notified = 0;
      viewmodel.addListener(() => notified++);

      viewmodel.topicViewMode = TopicViewMode.Tree;
      viewmodel.groupTimePeriod = MessageGroupTimePeriod.minute;
      viewmodel.filter = 'home';
      viewmodel.autoSelect = true;

      expect(notified, 4);
      expect(viewmodel.filter, 'home');
    });
  });

  group('MessageViewerViewmodel values of the selected topic', () {
    test('counts the messages of the selected topic', () {
      receiveAndSelect('home/temp', ['1', '2', '3']);
      adapter.receive(message('other', '9'));

      expect(viewmodel.getSelectedMessageCount(), 3);
    });

    test('calculates min, max and average of the numeric payloads', () {
      receiveAndSelect('home/temp', ['20.5', 'n/a', '18', '22.5']);

      expect(viewmodel.getMinValue(), 18);
      expect(viewmodel.getMaxValue(), 22.5);
      expect(viewmodel.getAvgValue(), closeTo(20.333, 0.001));
    });

    test('has no statistics for a topic without numbers', () {
      receiveAndSelect('home/state', ['on', 'off']);

      expect(viewmodel.getMinValue(), isNull);
      expect(viewmodel.getMaxValue(), isNull);
      expect(viewmodel.getAvgValue(), isNull);
    });

    test('chart values contain the numeric payloads, newest first', () {
      receiveAndSelect('home/temp', ['1', 'x', '3']);

      var values = viewmodel.getChartValues();

      expect(values.map((x) => x.item0), [start.add(Duration(seconds: 2)), start]);
      expect(values.map((x) => x.item1), [3, 1]);
    });

    test('chart values are limited to the last 100', () {
      receiveAndSelect('home/temp', List.generate(150, (i) => '$i'));

      expect(viewmodel.getChartValues(), hasLength(100));
    });

    test('values are the payloads as text, newest first', () {
      receiveAndSelect('home/position', ['47.1,11.1', '47.2,11.2']);

      expect(viewmodel.getValues(), ['47.2,11.2', '47.1,11.1']);
    });
  });

  group('MessageViewerViewmodel selection', () {
    test('auto select follows new messages of the selected topic', () {
      receiveAndSelect('home/temp', ['1']);
      viewmodel.autoSelect = true;

      adapter.receive(message('home/temp', '2', receivedOn: start.add(Duration(minutes: 1))));
      adapter.receive(message('other', '3', receivedOn: start.add(Duration(minutes: 2))));

      expect(viewmodel.selectedMessage!.payload, toPayload('2'));
    });

    test('without auto select the selection stays', () {
      receiveAndSelect('home/temp', ['1']);

      adapter.receive(message('home/temp', '2', receivedOn: start.add(Duration(minutes: 1))));

      expect(viewmodel.selectedMessage!.payload, toPayload('1'));
    });

    test('the selection is cleared when the project is closed', () async {
      receiveAndSelect('home/temp', ['1']);

      await GetIt.I.get<ProjectManager>().closeProject(true);

      expect(viewmodel.selectedMessage, isNull);
    });
  });

  group('MessageViewerViewmodel actions', () {
    test('clearing a retained topic publishes an empty retained message', () {
      adapter.receive(message('home/state', 'on', retain: true));
      viewmodel.selectedMessage = viewmodel.messageBuffer.getLastMessage();

      viewmodel.clearRetainedTopic();

      var published = adapter.published.single;
      expect(published.topic, 'home/state');
      expect(published.payload, '');
      expect(published.retain, isTrue);
    });

    test('republishing sends the selected message again', () {
      adapter.receive(message('home/state', 'on', retain: true));
      viewmodel.selectedMessage = viewmodel.messageBuffer.getLastMessage();

      viewmodel.rePublish();

      var published = adapter.published.single;
      expect(published.topic, 'home/state');
      expect(published.payload, toPayload('on'));
      expect(published.payloadType, MqttPayloadType.binary);
      expect(published.retain, isTrue);
    });

    test('disposing the viewmodel keeps the message viewer working', () async {
      adapter.receive(message('home/temp', '1'));

      viewmodel.dispose();
      await GetIt.I.get<ProjectManager>().closeProject(true);

      // MessageViewer clears its messages when the project is closed
      expect(GetIt.I.get<MessageViewer>().messageBuffer.length, 0);
    });
  });
}
