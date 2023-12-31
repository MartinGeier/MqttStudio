import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:typed_data/typed_buffers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_json_viewer/flutter_json_viewer.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/topic_chip.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:mqttstudio/topic_viewer/topic_detailviewer_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:mqttstudio/custom_theme.dart';
import '../../common/widgets/topic_chart.dart';

class MessageDetailView extends StatelessWidget {
  final _scrollController = ScrollController();

  MessageDetailView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<TopicDetailViewerViewmodel>(builder: (context, viewmodel, child) {
      var topic = viewmodel.selectedMessage;
      final nf = NumberFormat('.000', context.locale.countryCode);
      var chartValues = viewmodel.getChartValues();
      if (topic == null) {
        return Container();
      }
      return Container(
          width: 500,
          padding: EdgeInsets.all(6),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: Theme.of(context).dividerColor))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _buildAutoSelectButton(viewmodel),
              _buildClearRetainedButton(viewmodel),
              _buildRepublishButton(viewmodel),
              Spacer(),
              IconButton(onPressed: () => viewmodel.selectedMessage = null, icon: Icon(Icons.close))
            ]),
            SizedBox(height: 12),
            _buildTopicChip(topic, context),
            SizedBox(height: 24),
            _buildInfoRow(context, topic),
            SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_buildReceivedOn(context, topic, nf), _buildMessageCount(context, viewmodel, nf), Spacer()],
            ),
            SizedBox(height: 24),
            _buildPayload(context, topic),
            SizedBox(height: 32),
            chartValues.length > 1 ? Container(height: 300, child: TopicChart(values: chartValues, topic: topic)) : SizedBox(),
          ]));
    });
  }

  Widget _buildAutoSelectButton(TopicDetailViewerViewmodel viewmodel) {
    return ToggleButtons(
        renderBorder: false,
        isSelected: [viewmodel.autoSelect],
        onPressed: (_) {
          viewmodel.autoSelect = !viewmodel.autoSelect;
        },
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Tooltip(
              message: "messagedetailview.autoselectbutton.tooltip".tr(),
              child: Row(children: [
                viewmodel.autoSelect ? Icon(Icons.pause, color: Colors.blue) : Icon(Icons.play_arrow, color: Colors.green),
                SizedBox(width: 12),
                Text('messagedetailview.autoselectbutton.label'.tr())
              ]),
            ),
          )
        ]);
  }

  Widget _buildClearRetainedButton(TopicDetailViewerViewmodel viewmodel) {
    return Tooltip(
      message: "messagedetailview.clearretainedbutton.tooltip".tr(),
      child: TextButton(
          onPressed: viewmodel.selectedMessage?.retain ?? false ? () => viewmodel.clearRetainedTopic() : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Icon(Icons.unpublished_outlined),
              SizedBox(width: 12),
              Text('messagedetailview.clearretainedbutton.label'.tr())
            ]),
          )),
    );
  }

  Widget _buildRepublishButton(TopicDetailViewerViewmodel viewmodel) {
    return Tooltip(
      message: "messagedetailview.republishbutton.tooltip".tr(),
      child: TextButton(
          onPressed: () => viewmodel.rePublish(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [Icon(Icons.send), SizedBox(width: 12), Text('messagedetailview.republishbutton.label'.tr())]),
          )),
    );
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
              tooltip: 'messagedetailview.copytopic.tooltip'.tr(),
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
        SizedBox(
          width: 160,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('messagedetailview.receivedon.label'.tr(), style: Theme.of(context).textTheme.titleMedium),
            SelectableText(DateFormat('HH:mm:ss').format(topic.receivedOn) + nf.format(topic.receivedOn.millisecond / 1000),
                style: Theme.of(context).textTheme.headlineSmall)
          ]),
        ),
      ]),
    );
  }

  Padding _buildMessageCount(BuildContext context, TopicDetailViewerViewmodel viewmodel, NumberFormat nf) {
    var msgCount = viewmodel.getSelectedMessageCount();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
        SizedBox(
          width: 80,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('messagedetailview.messagecount.label'.tr(), style: Theme.of(context).textTheme.titleMedium),
            SelectableText(msgCount.toString(), style: Theme.of(context).textTheme.headlineSmall)
          ]),
        ),
      ]),
    );
  }

  Widget _buildInfoRow(BuildContext context, ReceivedMqttMessage topic) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 160,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('messagedetailview.qos.label'.tr(), style: Theme.of(context).textTheme.titleMedium),
              SelectableText(MqttQos.values[topic.qos.index].toString().tr(), style: Theme.of(context).textTheme.headlineSmall)
            ]),
          ),
          SizedBox(
            width: 80,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('messagedetailview.retain.label'.tr(), style: Theme.of(context).textTheme.titleMedium),
              SelectableText(topic.retain.toString(), style: Theme.of(context).textTheme.headlineSmall)
            ]),
          ),
          SizedBox(
            width: 100,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('messagedetailview.payloadsize.label'.tr(), style: Theme.of(context).textTheme.titleMedium),
              SelectableText('${topic.payload.length.toString()} B', style: Theme.of(context).textTheme.headlineSmall)
            ]),
          ),
          SizedBox(
            width: 48,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('messagedetailview.id.label'.tr(), style: Theme.of(context).textTheme.titleMedium),
              SelectableText(topic.id.toString(), style: Theme.of(context).textTheme.headlineSmall)
            ]),
          )
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
              Row(
                children: [
                  Text('messagedetailview.payload.label'.tr(), style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(width: 32),
                  Chip(
                    label: Text(describeEnum(payLoadType)),
                  ),
                ],
              ),
              Visibility(
                visible: payLoadType != PayloadType.Image,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: IconButton(
                    tooltip: 'messagedetailview.copypayload.label'.tr(),
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
                    ? Theme.of(context).textTheme.headlineMedium
                    : Theme.of(context).textTheme.bodyLarge!.copyWith(height: 1.7))));
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
      if (payloadString.trim().startsWith('{')) {
        jsonDecode(payloadString);
        return PayloadType.Json;
      }
    } catch (error) {
      // ignore errors
    }

    // PNG
    if (payload.isNotEmpty && payload[0] == 137 && payload[1] == 80 && payload[2] == 78 && payload[3] == 71) {
      return PayloadType.Image;
    }

    // JPG
    if (payload.isNotEmpty && payload[0] == 255 && payload[1] == 216 && payload[2] == 255) {
      return PayloadType.Image;
    }

    return PayloadType.Text;
  }
}

enum PayloadType { Text, Number, Json, Image }
