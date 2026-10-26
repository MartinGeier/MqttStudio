import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/utils/json_diff.dart';
import 'package:mqttstudio/common/widgets/fast_topic_chip.dart';
import 'package:mqttstudio/common/widgets/payload_diff_view.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:srx_flutter/srx_flutter.dart';

// One side of the comparison: the message, its decoded payload and the color of its topic
class ComparedMessage {
  final ReceivedMqttMessage message;
  final Object? value;
  final TopicColor color;

  const ComparedMessage(this.message, this.value, this.color);
}

// Two messages side by side, the older one on the left, with the changes highlighted
class CompareMessagesDialog extends StatelessWidget {
  static const int _maxListedChanges = 6;

  final ComparedMessage older;
  final ComparedMessage newer;

  CompareMessagesDialog._(this.older, this.newer);

  factory CompareMessagesDialog(ComparedMessage a, ComparedMessage b) =>
      a.message.receivedOn.isAfter(b.message.receivedOn) ? CompareMessagesDialog._(b, a) : CompareMessagesDialog._(a, b);

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(title: Text('comparemessagesdialog.title'.tr()), contentPadding: EdgeInsets.all(16), children: [
      ConstrainedBox(
        constraints: BoxConstraints(minWidth: 1100, maxWidth: 1100),
        child: SizedBox(
          height: 600,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _buildHeader(context, older)),
              SizedBox(width: 16),
              Expanded(child: _buildHeader(context, newer)),
            ]),
            SizedBox(height: 12),
            _buildSummary(context),
            SizedBox(height: 12),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _buildSide(context, JsonDiffSide.old)),
                SizedBox(width: 16),
                Expanded(child: _buildSide(context, JsonDiffSide.current)),
              ]),
            ),
            SizedBox(height: 16),
            SrxFormRow(alignment: CrossAxisAlignment.center, children: [
              Spacer(flex: 3),
              Expanded(
                  child: ElevatedButton(
                      autofocus: true,
                      onPressed: () => GetIt.I.get<SrxNavigationService>().pop(),
                      child: Text('srx.common.ok'.tr()))),
            ]),
          ]),
        ),
      )
    ]);
  }

  Widget _buildHeader(BuildContext context, ComparedMessage side) {
    return Row(children: [
      Flexible(child: FastTopicChip(topic: side.message.topicName, topicColor: side.color, onPressed: null)),
      SizedBox(width: 12),
      Text(DateFormat('HH:mm:ss.SSS').format(side.message.receivedOn), style: Theme.of(context).textTheme.titleMedium),
    ]);
  }

  Widget _buildSummary(BuildContext context) {
    var style = Theme.of(context).textTheme.bodyMedium;
    if (!PayloadDiffView.isStructured(older.value) || !PayloadDiffView.isStructured(newer.value)) {
      var equal = JsonDiff.equal(older.value, newer.value);
      return Text((equal ? 'comparemessagesdialog.equal' : 'comparemessagesdialog.different').tr(), style: style);
    }
    var changes = JsonDiff.compare(older.value, newer.value);
    if (changes.isEmpty) {
      return Text('comparemessagesdialog.equal'.tr(), style: style);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('comparemessagesdialog.changes'.plural(changes.length), style: Theme.of(context).textTheme.titleMedium),
      SizedBox(height: 4),
      for (var change in changes.take(_maxListedChanges)) SelectableText(_describe(change), style: diffTextStyle),
      if (changes.length > _maxListedChanges)
        Text('comparemessagesdialog.morechanges'.tr(args: ['${changes.length - _maxListedChanges}']), style: style),
    ]);
  }

  static String _describe(JsonChange change) {
    switch (change.kind) {
      case JsonChangeKind.added:
        return '+ ${change.path}: ${JsonDiff.compact(change.newValue)}';
      case JsonChangeKind.removed:
        return '- ${change.path}: ${JsonDiff.compact(change.oldValue)}';
      case JsonChangeKind.changed:
        return '~ ${change.path}: ${JsonDiff.compact(change.oldValue)} → ${JsonDiff.compact(change.newValue)}';
    }
  }

  Widget _buildSide(BuildContext context, JsonDiffSide side) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor)),
      padding: EdgeInsets.all(4),
      child: PayloadDiffView(oldValue: older.value, newValue: newer.value, side: side),
    );
  }
}
