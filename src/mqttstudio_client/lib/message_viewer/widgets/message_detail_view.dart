import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:typed_data/typed_buffers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_json_viewer/flutter_json_viewer.dart';
import 'package:mqttstudio/common/widgets/topic_chip.dart';
import 'package:mqttstudio/model/mqtt_message_properties.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:mqttstudio/custom_theme.dart';
import '../../common/widgets/topic_chart.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../common/utils/payload_utils.dart';

class MessageDetailView extends StatefulWidget {
  MessageDetailView({Key? key}) : super(key: key);

  @override
  State<MessageDetailView> createState() => _MessageDetailViewState();
}

class _MessageDetailViewState extends State<MessageDetailView> {
  final _scrollController = ScrollController();
  final _mapController = MapController();
  ReceivedMqttMessage? _centeredMessage;
  bool showLast1000Markers = false;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MessageViewerViewmodel>(builder: (context, viewmodel, child) {
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
              // a recorded message gets no new ones and is not published from here
              if (viewmodel.isLive) ...[
                _buildAutoSelectButton(viewmodel, context),
                _buildClearRetainedButton(viewmodel),
                _buildRepublishButton(viewmodel),
              ],
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
            if (topic.properties != null && !topic.properties!.isEmpty) ...[
              _buildMqtt5Properties(context, topic.properties!),
              SizedBox(height: 24),
            ],
            _buildPayload(context, topic, viewmodel),
            SizedBox(height: 12),
            chartValues.length > 1
                ? Container(height: 300, child: TopicChart(values: chartValues, topic: topic))
                : SizedBox(),
          ]));
    });
  }

  Widget _buildAutoSelectButton(MessageViewerViewmodel viewmodel, BuildContext context) {
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
                viewmodel.autoSelect
                    ? Icon(Icons.pause, color: Theme.of(context).primaryColor)
                    : Icon(Icons.play_arrow, color: Colors.green),
                SizedBox(width: 12),
                Text('messagedetailview.autoselectbutton.label'.tr())
              ]),
            ),
          )
        ]);
  }

  Widget _buildClearRetainedButton(MessageViewerViewmodel viewmodel) {
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

  Widget _buildRepublishButton(MessageViewerViewmodel viewmodel) {
    return Tooltip(
      message: "messagedetailview.republishbutton.tooltip".tr(),
      child: TextButton(
          onPressed: () => viewmodel.rePublish(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Icon(Icons.send),
              SizedBox(width: 12),
              Text('messagedetailview.republishbutton.label'.tr())
            ]),
          )),
    );
  }

  Widget _buildTopicChip(ReceivedMqttMessage topic, BuildContext context) {
    var color = context.read<MessageViewerViewmodel>().getTopicColor(topic.topicName);
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
            SelectableText(
                DateFormat('HH:mm:ss').format(topic.receivedOn) + nf.format(topic.receivedOn.millisecond / 1000),
                style: Theme.of(context).textTheme.headlineSmall)
          ]),
        ),
      ]),
    );
  }

  Padding _buildMessageCount(BuildContext context, MessageViewerViewmodel viewmodel, NumberFormat nf) {
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
              SelectableText(MqttQos.values[topic.qos.index].toString().tr(),
                  style: Theme.of(context).textTheme.headlineSmall)
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

  Widget _buildMqtt5Properties(BuildContext context, MqttMessageProperties properties) {
    var rows = <TableRow>[
      if (properties.contentType != null)
        _buildPropertyRow(context, 'messagedetailview.contenttype.label'.tr(), properties.contentType!),
      if (properties.responseTopic != null)
        _buildPropertyRow(context, 'messagedetailview.responsetopic.label'.tr(), properties.responseTopic!),
      if (properties.correlationData != null)
        _buildPropertyRow(context, 'messagedetailview.correlationdata.label'.tr(),
            PayloadUtils.toUtf8OrHex(properties.correlationData!)),
      if (properties.messageExpiryInterval != null)
        _buildPropertyRow(
            context, 'messagedetailview.messageexpiry.label'.tr(), '${properties.messageExpiryInterval} s'),
      if (properties.payloadFormatUtf8)
        _buildPropertyRow(context, 'messagedetailview.payloadformat.label'.tr(), 'UTF-8'),
      if (properties.subscriptionIdentifiers.isNotEmpty)
        _buildPropertyRow(context, 'messagedetailview.subscriptionids.label'.tr(),
            properties.subscriptionIdentifiers.join(', ')),
      for (var userProperty in properties.userProperties)
        _buildPropertyRow(context, userProperty.key, userProperty.value),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('messagedetailview.mqtt5properties.label'.tr(), style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: 6),
        Table(
            columnWidths: {0: FixedColumnWidth(160), 1: FlexColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: rows),
      ]),
    );
  }

  TableRow _buildPropertyRow(BuildContext context, String name, String value) {
    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 4, right: 12),
        child: Text(name, style: Theme.of(context).textTheme.titleSmall, overflow: TextOverflow.ellipsis),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: SelectableText(value, style: Theme.of(context).textTheme.bodyMedium),
      ),
    ]);
  }

  Widget _buildPayload(BuildContext context, ReceivedMqttMessage topic, MessageViewerViewmodel viewmodel) {
    var payLoadType = PayloadUtils.detectPayloadType(topic.payload);
    String payloadString = PayloadUtils.safePayloadToString(topic.payload);

    Widget viewer;
    switch (payLoadType) {
      case PayloadType.Json:
        viewer = _buildJsonViewer(payloadString, context);
        break;

      case PayloadType.Image:
        viewer = _buildImageViewer(topic.payload, context);
        break;

      case PayloadType.GnssCoordinates:
        viewer = _buildMapViewer(topic, payloadString, context, viewmodel);
        break;

      case PayloadType.Number:
        viewer = _buildNumberViewer(payloadString, viewmodel, context);
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
                    label: Text(payLoadType.name),
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
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: PayloadUtils.safePayloadToString(topic.payload))),
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

  Widget _buildNumberViewer(String payload, MessageViewerViewmodel viewmodel, BuildContext context) {
    return Expanded(
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      SelectableText(payload,
          style: payload.length < 25
              ? Theme.of(context).textTheme.headlineMedium
              : Theme.of(context).textTheme.bodyLarge!.copyWith(height: 1.7)),
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                  width: 36,
                  child: Text('messagedetailview.min.label'.tr(), style: Theme.of(context).textTheme.labelLarge)),
              SelectableText(viewmodel.getMinValue()?.toStringAsPrecision(10) ?? ''),
            ],
          ),
          Row(
            children: [
              SizedBox(
                  width: 36,
                  child: Text('messagedetailview.max.label'.tr(), style: Theme.of(context).textTheme.labelLarge)),
              SelectableText(viewmodel.getMaxValue()?.toStringAsPrecision(10) ?? '', maxLines: 1),
            ],
          ),
        ],
      ),
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                  width: 36,
                  child: Text('messagedetailview.avg.label'.tr(), style: Theme.of(context).textTheme.labelLarge)),
              SelectableText(viewmodel.getAvgValue()?.toStringAsPrecision(10) ?? '', maxLines: 1),
            ],
          ),
          Row(
            children: [Text('')],
          )
        ],
      )
    ]));
  }

  Widget _buildJsonViewer(String payload, BuildContext context) {
    return Expanded(
        child: SingleChildScrollView(controller: _scrollController, child: JsonViewer(jsonDecode(payload))));
  }

  Widget _buildMapViewer(
      ReceivedMqttMessage message, String payload, BuildContext context, MessageViewerViewmodel viewmodel) {
    var position = PayloadUtils.tryParseCoordinates(payload)!;
    _centerMapOnMessage(message, position);
    return Expanded(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Checkbox(
                      value: showLast1000Markers,
                      onChanged: (value) => setState(() => showLast1000Markers = value ?? false)),
                  InkWell(
                      child: Text("messagedetailview.showlast1000.label".tr(),
                          style: Theme.of(context).textTheme.labelLarge),
                      onTap: () => setState(() => showLast1000Markers = !showLast1000Markers)),
                ],
              ),
              Text('( ' + payload + ' )', style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: position, initialZoom: 18),
            children: [
              openStreetMapTileLayer,
              MarkerLayer(markers: [
                // add a marker for each message, skipping messages that are no coordinates
                if (showLast1000Markers)
                  ...viewmodel.getValues().map(PayloadUtils.tryParseCoordinates).nonNulls.map((point) => Marker(
                        point: point,
                        child: Icon(Icons.location_on, size: 24, color: Theme.of(context).colorScheme.primary),
                      )),
                Marker(
                  point: position,
                  child: Icon(Icons.location_on, size: 32, color: Theme.of(context).colorScheme.secondary),
                ),
              ]),
              openStreetMapAttribution,
            ],
          ),
        ),
      ],
    ));
  }

  // initialCenter only applies to the first map, afterwards the map controller keeps its camera.
  // So move the map to the pin of a newly selected message, keeping the current zoom.
  void _centerMapOnMessage(ReceivedMqttMessage message, LatLng position) {
    if (identical(message, _centeredMessage)) {
      return;
    }

    var isFirstMap = _centeredMessage == null;
    _centeredMessage = message;
    if (isFirstMap) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _mapController.move(position, _mapController.camera.zoom);
      }
    });
  }

  Widget _buildImageViewer(Uint8Buffer payload, BuildContext context) {
    return Expanded(
        child:
            SingleChildScrollView(controller: _scrollController, child: Image.memory(Uint8List.view(payload.buffer))));
  }

  TileLayer get openStreetMapTileLayer => TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        // OpenStreetMap blocks requests without a user agent identifying the app
        userAgentPackageName: 'eu.redpin.mqttstudio',
        // The default NetworkTileProvider of flutter_map 8 cancels obsolete tile requests itself.
      );

  // Attribution required by the OpenStreetMap tile usage policy
  Widget get openStreetMapAttribution => SimpleAttributionWidget(
        source: Text('OpenStreetMap contributors'),
        onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
      );
}
