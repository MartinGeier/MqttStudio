import 'dart:convert';
import 'dart:typed_data';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:typed_data/typed_buffers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_json_viewer/flutter_json_viewer.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/topic_chip.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:mqttstudio/topic_viewer/topic_viewer_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:mqttstudio/custom_theme.dart';

class MessageDetailView extends StatelessWidget {
  final _scrollController = ScrollController();

  MessageDetailView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<TopicViewerViewmodel>(builder: (context, viewmodel, child) {
      var topic = viewmodel.selectedMessage;
      final nf = NumberFormat('.000', context.locale.countryCode);
      if (topic == null) {
        return Container();
      }
      return Container(
          width: 500,
          padding: EdgeInsets.all(6),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: Theme.of(context).dividerColor))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(onPressed: () {}, icon: Icon(Icons.pause)),
              IconButton(onPressed: () => viewmodel.selectedMessage = null, icon: Icon(Icons.close))
            ]),
            SizedBox(height: 12),
            _buildTopicChip(topic, context),
            SizedBox(height: 16),
            _buildInfoRow(context, topic),
            SizedBox(height: 16),
            _buildReceivedOn(context, topic, nf),
            SizedBox(height: 16),
            _buildPayload(context, topic),
          ]));
    });
  }

  Widget _buildTopicChip(ReceivedMqttMessage topic, BuildContext context) {
    var color = GetIt.I.get<ProjectGlobalViewmodel>().getTopicColor(topic.topicName);
    return Stack(
      children: [
        TopicChip(
          unlimitedWidth: true,
          topic: topic.topicName,
          topicColor: color,
          onPressed: () {},
        ),
        Positioned(
          right: 4,
          child: IconButton(
              color: Theme.of(context).getTextColor(color.color),
              tooltip: 'Copy topic name',
              onPressed: () => Clipboard.setData(ClipboardData(text: topic.topicName)),
              icon: Icon(Icons.copy)),
        ),
      ],
    );
  }

  Padding _buildReceivedOn(BuildContext context, ReceivedMqttMessage topic, NumberFormat nf) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Received on', style: Theme.of(context).textTheme.subtitle1),
          SelectableText(DateFormat('HH:mm:ss').format(topic.receivedOn) + nf.format(topic.receivedOn.millisecond / 1000),
              style: Theme.of(context).textTheme.headline4)
        ]),
      ]),
    );
  }

  Widget _buildInfoRow(BuildContext context, ReceivedMqttMessage topic) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Qos', style: Theme.of(context).textTheme.subtitle1),
            SelectableText(topic.qos.index.toString(), style: Theme.of(context).textTheme.headline4)
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Retain', style: Theme.of(context).textTheme.subtitle1),
            SelectableText(topic.retain.toString(), style: Theme.of(context).textTheme.headline4)
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Payload size', style: Theme.of(context).textTheme.subtitle1),
            SelectableText('${topic.payload.length.toString()} B', style: Theme.of(context).textTheme.headline4)
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Id', style: Theme.of(context).textTheme.subtitle1),
            SelectableText(topic.id.toString(), style: Theme.of(context).textTheme.headline4)
          ])
        ],
      ),
    );
  }

  Widget _buildPayload(BuildContext context, ReceivedMqttMessage topic) {
    var payLoadType = detectPayloadType(topic.payload);
    String payloadString = MqttPublishPayload.bytesToStringAsString(topic.payload);

    Widget viewer;
    switch (payLoadType) {
      case PayloadType.Json:
        viewer = _buildJsonViewer(payloadString, context);
        break;

      case PayloadType.Image:
        viewer = _buildImageViewer(topic.payload, context);
        break;

      default:
        viewer = _buildTextViewer(payloadString, context);
        break;
    }

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Payload', style: Theme.of(context).textTheme.subtitle1),
              Visibility(
                visible: payLoadType != PayloadType.Image,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: IconButton(
                    tooltip: 'Copy payload',
                    onPressed: () => Clipboard.setData(ClipboardData(text: MqttPublishPayload.bytesToStringAsString(topic.payload))),
                    icon: Icon(Icons.copy)),
              ),
            ],
          ),
          viewer
        ]),
      ),
    );
  }

  Widget _buildTextViewer(String payload, BuildContext context) {
    return Expanded(
        child: SingleChildScrollView(
            controller: _scrollController,
            child: SelectableText(payload,
                style: payload.length < 25
                    ? Theme.of(context).textTheme.headline4
                    : Theme.of(context).textTheme.bodyText1!.copyWith(height: 1.7))));
  }

  Widget _buildJsonViewer(String payload, BuildContext context) {
    return Expanded(child: SingleChildScrollView(controller: _scrollController, child: JsonViewer(jsonDecode(payload))));
  }

  Widget _buildImageViewer(Uint8Buffer payload, BuildContext context) {
    return Expanded(child: SingleChildScrollView(controller: _scrollController, child: Image.memory(Uint8List.view(payload.buffer))));
  }

  PayloadType detectPayloadType(Uint8Buffer payload) {
    String payloadString = MqttPublishPayload.bytesToStringAsString(payload);

    if (double.tryParse(payloadString) != null) {
      return PayloadType.Number;
    }

    try {
      jsonDecode(payloadString);
      return PayloadType.Json;
    } catch (error) {
      // ignore errors
    }

    // PNG
    if (payload[0] == 137 && payload[1] == 80 && payload[2] == 78 && payload[3] == 71) {
      return PayloadType.Image;
    }

    // JPG
    if (payload[0] == 255 && payload[1] == 216 && payload[2] == 255) {
      return PayloadType.Image;
    }

    return PayloadType.Text;
  }
}

enum PayloadType { Text, Number, Json, Image }
