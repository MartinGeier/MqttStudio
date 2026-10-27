import 'dart:convert';
import 'package:darq/darq.dart' show Tuple2;
import 'package:flutter/foundation.dart';
import 'package:mqttstudio/common/utils/json_diff.dart';
import 'package:mqttstudio/common/utils/payload_decoder.dart';
import 'package:mqttstudio/common/widgets/payload_diff_view.dart';
import 'package:mqttstudio/message_viewer/compare_messages_dialog.dart';
import 'package:mqttstudio/message_viewer/publish_topic_dialog.dart';
import 'package:mqttstudio/message_viewer/topic_stats.dart';
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
import 'package:mqttstudio/protocol/protocol_profile.dart';
import 'package:mqttstudio/protocol/sparkplug/sparkplug_profile.dart';
import 'package:mqttstudio/protocol/widgets/interpreted_payload_view.dart';
import 'package:mqttstudio/protocol/widgets/rebirth_request.dart';
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
  // the detail view is 500 px wide
  static const int _hexBytesPerLine = 8;

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
            _buildToolbar(context, viewmodel, topic),
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
            chartValues.length > 1 ? _buildChart(context, viewmodel, chartValues, topic) : SizedBox(),
          ]));
    });
  }

  Widget _buildToolbar(BuildContext context, MessageViewerViewmodel viewmodel, ReceivedMqttMessage message) {
    return Row(children: [
      // a recorded message gets no new ones and is not published from here
      if (viewmodel.isLive) _buildAutoSelectButton(viewmodel, context),
      Spacer(),
      if (viewmodel.isLive) ...[
        IconButton(
            onPressed: () => viewmodel.rePublish(),
            icon: Icon(Icons.send),
            tooltip: 'messagedetailview.republishbutton.tooltip'.tr()),
        IconButton(
            onPressed: viewmodel.canEditPayload(message) ? () => _editAndPublish(message) : null,
            icon: Icon(Icons.edit_note),
            tooltip: viewmodel.canEditPayload(message)
                ? 'messagedetailview.editbutton.tooltip'.tr()
                : 'messagedetailview.editbutton.binary.tooltip'.tr()),
        // Sparkplug node and device messages are never retained: their place has the rebirth request (§12.2)
        if (viewmodel.edgeNodeOf(message) != null && !message.retain)
          _buildRebirthButton(context, viewmodel, message)
        else
          IconButton(
              onPressed: message.retain ? () => viewmodel.clearRetainedTopic() : null,
              icon: Icon(Icons.unpublished_outlined),
              tooltip: 'messagedetailview.clearretainedbutton.tooltip'.tr()),
      ],
      _buildMarkButton(context, viewmodel, message),
      _buildCompareButton(viewmodel, message),
      IconButton(
          onPressed: () => viewmodel.selectedMessage = null,
          icon: Icon(Icons.close),
          tooltip: 'messagedetailview.close.tooltip'.tr())
    ]);
  }

  Widget _buildRebirthButton(BuildContext context, MessageViewerViewmodel viewmodel, ReceivedMqttMessage message) {
    var node = viewmodel.edgeNodeOf(message)!;
    return IconButton(
        onPressed: viewmodel.canRequestRebirth ? () => RebirthRequest.confirmAndSend(context, viewmodel, [node]) : null,
        icon: Icon(Icons.autorenew),
        tooltip: 'sparkplug.rebirth.tooltip'.tr(args: [node.edgeNode]));
  }

  // the button next to the missing-birth warning, or when it was asked for
  Widget? _buildInterpretationAction(
      BuildContext context, MessageViewerViewmodel viewmodel, ReceivedMqttMessage message, String action) {
    var node = viewmodel.edgeNodeOf(message);
    if (action != SparkplugProfile.rebirthAction || node == null || !viewmodel.isLive) {
      return null;
    }
    var requested = viewmodel.rebirthRequestedAt(node);
    if (requested != null) {
      return Text('sparkplug.rebirth.requested.label'.tr(args: [DateFormat.Hms().format(requested)]),
          style: Theme.of(context).textTheme.bodySmall!.copyWith(color: Theme.of(context).hintColor));
    }
    return TextButton(
        onPressed: viewmodel.canRequestRebirth ? () => RebirthRequest.confirmAndSend(context, viewmodel, [node]) : null,
        style: TextButton.styleFrom(minimumSize: Size(0, 32)),
        child: Text('sparkplug.rebirth.button'.tr()));
  }

  Widget _buildMarkButton(BuildContext context, MessageViewerViewmodel viewmodel, ReceivedMqttMessage message) {
    var marked = viewmodel.markedMessage;
    var isMarked = identical(marked, message);
    return IconButton(
        onPressed: isMarked ? viewmodel.clearMark : viewmodel.markForCompare,
        icon: Icon(marked == null ? Icons.push_pin_outlined : Icons.push_pin),
        color: isMarked ? Theme.of(context).colorScheme.secondary : null,
        tooltip: isMarked
            ? 'messagedetailview.unmark.tooltip'.tr()
            : marked == null
                ? 'messagedetailview.mark.tooltip'.tr()
                : 'messagedetailview.remark.tooltip'.tr());
  }

  Widget _buildCompareButton(MessageViewerViewmodel viewmodel, ReceivedMqttMessage message) {
    var marked = viewmodel.markedMessage;
    var canCompare = marked != null && !identical(marked, message);
    return IconButton(
        onPressed: canCompare ? () => _compare(viewmodel, marked, message) : null,
        icon: Icon(Icons.compare_arrows),
        tooltip: canCompare
            ? 'messagedetailview.compare.tooltip'
                .tr(args: [marked.topicName, DateFormat('HH:mm:ss.SSS').format(marked.receivedOn)])
            : 'messagedetailview.compare.nomark.tooltip'.tr());
  }

  Future<void> _compare(MessageViewerViewmodel viewmodel, ReceivedMqttMessage marked, ReceivedMqttMessage message) async {
    ComparedMessage side(ReceivedMqttMessage msg) =>
        ComparedMessage(msg, viewmodel.decode(msg).comparable, viewmodel.getTopicColor(msg.topicName));
    await showDialog(context: context, builder: (_) => CompareMessagesDialog(side(marked), side(message)));
  }

  Future<void> _editAndPublish(ReceivedMqttMessage message) async {
    await showDialog(context: context, builder: (_) => PublishTopicDialog(message: message));
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

  // an interpreted topic charts one of its values, chosen above the chart
  Widget _buildChart(BuildContext context, MessageViewerViewmodel viewmodel, List<Tuple2<DateTime, double>> values,
      ReceivedMqttMessage topic) {
    var series = viewmodel.chartSeries;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (series.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Tooltip(
            message: 'messagedetailview.chartseries.tooltip'.tr(),
            child: DropdownButton<String>(
                isDense: true,
                value: viewmodel.selectedChartSeries,
                onChanged: (value) => viewmodel.selectedChartSeries = value,
                items: [for (var name in series) DropdownMenuItem(value: name, child: Text(name))]),
          ),
        ),
      Container(height: 300, child: TopicChart(values: values, topic: topic)),
    ]);
  }

  Widget _buildPayload(BuildContext context, ReceivedMqttMessage topic, MessageViewerViewmodel viewmodel) {
    var decoder = viewmodel.decoderOf(topic.topicName);
    var decoded = viewmodel.decode(topic);
    // a protocol like VDA 5050: what the message means instead of its JSON (doc/vda5050-design.md §7)
    var interpretation = viewmodel.interpret(topic);
    var anyway = viewmodel.interpretAnyway(topic);
    // base64 and gzip unpack the bytes, the viewers then pick by the content as for auto
    var shownBytes = decoder == PayloadDecoder.base64 || decoder == PayloadDecoder.gzip
        ? (Uint8Buffer()..addAll(decoded.bytes))
        : topic.payload;
    var byContent = decoder == PayloadDecoder.auto || decoder == PayloadDecoder.base64 || decoder == PayloadDecoder.gzip;
    var payLoadType = PayloadUtils.detectPayloadType(shownBytes);
    var binary = byContent && payLoadType == PayloadType.Text && !PayloadDecoding.isUtf8(shownBytes);
    var isImage = byContent && payLoadType == PayloadType.Image;

    Widget viewer;
    if (viewmodel.showChanges) {
      viewer = _buildChanges(context, viewmodel, topic);
    } else if (interpretation != null) {
      viewer = Expanded(
          child: InterpretedPayloadView(
              interpretation: interpretation,
              isCollapsed: viewmodel.isSectionCollapsed,
              onToggle: viewmodel.toggleSection,
              controller: _scrollController,
              actionBuilder: (action) => _buildInterpretationAction(context, viewmodel, topic, action)));
    } else if (decoded.error != null) {
      viewer = _buildDecodeError(context, decoded.error!);
    } else if (byContent) {
      viewer = binary ? _buildHexViewer(decoded.bytes, context) : _buildViewerByType(context, topic, shownBytes, payLoadType, viewmodel);
    } else if (decoder == PayloadDecoder.hex) {
      viewer = _buildHexViewer(decoded.bytes, context);
    } else if (decoder == PayloadDecoder.text) {
      viewer = _buildTextViewer(utf8.decode(decoded.bytes, allowMalformed: true), context);
    } else {
      viewer = _buildDecodedValueViewer(decoded.value, context);
    }

    var kind = binary
        ? 'messagedetailview.binary.label'.tr()
        : byContent
            ? payLoadType.name
            : 'payloaddecoder.${decoder.name}'.tr();
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Text('messagedetailview.payload.label'.tr(), style: Theme.of(context).textTheme.titleMedium),
              SizedBox(width: 16),
              // an interpretable message names its protocol in the toggle instead of the chip, the panel is narrow
              anyway != null ? _buildInterpretedToggle(context, viewmodel, topic, anyway) : Chip(label: Text(kind)),
              Spacer(),
              if (interpretation == null) _buildDecoderDropDown(viewmodel, topic, decoder),
              IconButton(
                  tooltip: 'messagedetailview.changes.tooltip'.tr(),
                  color: viewmodel.showChanges ? Theme.of(context).colorScheme.secondary : null,
                  onPressed: () => viewmodel.showChanges = !viewmodel.showChanges,
                  icon: Icon(Icons.difference_outlined)),
              Visibility(
                visible: !isImage,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: IconButton(
                    tooltip: 'messagedetailview.copypayload.label'.tr(),
                    onPressed: () => Clipboard.setData(ClipboardData(text: _copyText(topic, decoder, decoded, binary))),
                    icon: Icon(Icons.copy)),
              ),
            ],
          ),
          viewer
        ]),
      ),
    );
  }

  // the protocol's view or the payload as it is, for this topic and session
  Widget _buildInterpretedToggle(
      BuildContext context, MessageViewerViewmodel viewmodel, ReceivedMqttMessage message, Interpretation interpretation) {
    var raw = viewmodel.isRaw(message.topicName);
    return Tooltip(
      message: 'messagedetailview.interpreted.tooltip'.tr(),
      child: ToggleButtons(
        constraints: BoxConstraints(minHeight: 28, minWidth: 48),
        textStyle: Theme.of(context).textTheme.labelLarge,
        isSelected: [!raw, raw],
        onPressed: (index) => viewmodel.setRaw(message.topicName, index == 1),
        children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('${viewmodel.protocolOf(message.topicName)!.profile.name} ${interpretation.protocolVersion}')),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('messagedetailview.raw.label'.tr())),
        ],
      ),
    );
  }

  Widget _buildDecoderDropDown(MessageViewerViewmodel viewmodel, ReceivedMqttMessage message, PayloadDecoder decoder) {
    return Tooltip(
      message: 'messagedetailview.decoder.tooltip'.tr(),
      child: DropdownButton<PayloadDecoder>(
          isDense: true,
          value: decoder,
          onChanged: (value) => viewmodel.setDecoder(message.topicName, value!),
          items: [
            for (var item in PayloadDecoder.values)
              DropdownMenuItem(value: item, child: Text('payloaddecoder.${item.name}'.tr()))
          ]),
    );
  }

  Widget _buildViewerByType(BuildContext context, ReceivedMqttMessage message, Uint8Buffer payload, PayloadType type,
      MessageViewerViewmodel viewmodel) {
    String payloadString = PayloadUtils.safePayloadToString(payload);
    switch (type) {
      case PayloadType.Json:
        return _buildJsonViewer(payloadString, context);
      case PayloadType.Image:
        return _buildImageViewer(payload, context);
      case PayloadType.GnssCoordinates:
        return _buildMapViewer(message, payloadString, context, viewmodel);
      case PayloadType.Number:
        return _buildNumberViewer(payloadString, viewmodel, context);
      default:
        return _buildTextViewer(payloadString, context);
    }
  }

  String _copyText(ReceivedMqttMessage message, PayloadDecoder decoder, DecodedPayload decoded, bool binary) {
    if (decoded.error != null) {
      return PayloadUtils.safePayloadToString(message.payload);
    }
    if (decoder == PayloadDecoder.hex || binary) {
      return PayloadDecoding.hexDump(decoded.bytes);
    }
    if (decoder == PayloadDecoder.messagePack || decoder == PayloadDecoder.cbor) {
      return JsonEncoder.withIndent('  ', (value) => '$value').convert(decoded.value);
    }
    return utf8.decode(decoded.bytes, allowMalformed: true);
  }

  Widget _buildDecodeError(BuildContext context, String error) {
    return Expanded(
        child: Text('messagedetailview.decodeerror.label'.tr(args: [error]),
            style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: Theme.of(context).colorScheme.error)));
  }

  Widget _buildHexViewer(Uint8List bytes, BuildContext context) {
    var hidden = bytes.length - PayloadDecoding.maxHexDumpBytes;
    return Expanded(
        child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText(PayloadDecoding.hexDump(bytes, bytesPerLine: _hexBytesPerLine), style: diffTextStyle),
              if (hidden > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('messagedetailview.hextruncated.label'.tr(args: ['$hidden']),
                      style: Theme.of(context).textTheme.labelLarge),
                ),
            ])));
  }

  // MessagePack and CBOR data
  Widget _buildDecodedValueViewer(Object? value, BuildContext context) {
    if (value is Map || value is List) {
      return Expanded(child: SingleChildScrollView(controller: _scrollController, child: JsonViewer(value)));
    }
    return _buildTextViewer(value is String ? value : JsonDiff.compact(value), context);
  }

  // what changed since the previous message of the topic, decoded with the topic's decoder
  Widget _buildChanges(BuildContext context, MessageViewerViewmodel viewmodel, ReceivedMqttMessage message) {
    var previous = viewmodel.previousOfSelected;
    var style = Theme.of(context).textTheme.labelLarge;
    if (previous == null) {
      return Expanded(child: Text('messagedetailview.changes.first'.tr(), style: style));
    }
    var oldValue = viewmodel.decode(previous).comparable;
    var newValue = viewmodel.decode(message).comparable;
    var earlier = TopicStats.formatDuration(message.receivedOn.difference(previous.receivedOn));
    String summary;
    if (PayloadDiffView.isStructured(oldValue) && PayloadDiffView.isStructured(newValue)) {
      var changes = JsonDiff.compare(oldValue, newValue).length;
      summary = changes == 0
          ? 'messagedetailview.changes.none'.tr(args: [earlier])
          : 'messagedetailview.changes.summary'.plural(changes, namedArgs: {'earlier': earlier});
    } else {
      summary = JsonDiff.equal(oldValue, newValue)
          ? 'messagedetailview.changes.none'.tr(args: [earlier])
          : 'messagedetailview.changes.text'.tr(args: [earlier]);
    }
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(summary, style: style),
        SizedBox(height: 8),
        Expanded(child: PayloadDiffView(oldValue: oldValue, newValue: newValue)),
      ]),
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
        userAgentPackageName: 'eu.sarix.mqttstudio',
        // The default NetworkTileProvider of flutter_map 8 cancels obsolete tile requests itself.
      );

  // Attribution required by the OpenStreetMap tile usage policy
  Widget get openStreetMapAttribution => SimpleAttributionWidget(
        source: Text('OpenStreetMap contributors'),
        onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
      );
}
