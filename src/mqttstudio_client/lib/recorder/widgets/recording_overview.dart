import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/common/widgets/fast_topic_chip.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:mqttstudio/recorder/engine/recording_player.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/model/recording_summary.dart';
import 'package:mqttstudio/recorder/recorder_viewmodel.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/widgets/recorder_format.dart';
import 'package:provider/provider.dart';

// Column widths of the topic table, shared by the header and the rows
class _Columns {
  static const double check = 48;
  static const double count = 96;
  static const double rate = 72;
  static const double interval = 96;
  static const double range = 150;
  static const double kind = 100;
  static const double size = 90;
  static const double duplicates = 96;
  static const double retained = 96;
  static const double gaps = 64;
  static const double minTopic = 260;
  static const double padding = 16;
  static const double minTable =
      check + count + rate + interval + range + kind + size + duplicates + gaps + retained + minTopic + padding;
}

// The topic table keeps its columns in a narrow window and scrolls sideways instead
class _TableFrame extends StatelessWidget {
  final Widget child;

  const _TableFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= _Columns.minTable) {
        return child;
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: _Columns.minTable, height: constraints.maxHeight, child: child),
      );
    });
  }
}

// Name, time, size, broker and filters of a recording, above its tabs or the live statistics
class RecordingHead extends StatelessWidget {
  final String name;
  final String meta;
  final String? broker;
  final List<RecorderFilter> filters;

  const RecordingHead({Key? key, required this.name, required this.meta, this.broker, required this.filters})
      : super(key: key);

  factory RecordingHead.of(RecordingInfo info) {
    var footer = info.footer;
    var header = info.header;
    return RecordingHead(
      name: info.name,
      meta: '${RecorderFormat.date(header.startedAt)} · ${RecorderFormat.duration(footer.duration)} · '
          '${'recorder.messages.label'.tr(args: [RecorderFormat.count(footer.summary.messages)])} · ${RecorderFormat.bytes(info.size)}',
      broker: '${header.broker} · ${header.protocol.displayName} · ${header.clientId}'
          '${header.projectName == null ? '' : ' · ${header.projectName}'}',
      filters: header.filters,
    );
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var hint = theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 16, children: [
          SelectableText(name, style: theme.textTheme.titleLarge),
          Text(meta, style: hint),
        ]),
        if (broker != null) ...[SizedBox(height: 4), Text(broker!, style: hint)],
        SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          // FastTopicChip paints its padding outside the width it takes, so it gets the room here
          for (var filter in filters.where((filter) => !filter.exclude))
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: FastTopicChip(topic: filter.filter, topicColor: filter.color ?? TopicColor(Colors.black), onPressed: null),
            ),
          for (var filter in filters.where((filter) => filter.exclude))
            Text('recorder.excluding.label'.tr(args: [filter.filter]), style: hint),
        ]),
      ]),
    );
  }
}

// The OVERVIEW of the selected recording: its topics with their statistics, below RecordingHead. The checkboxes
// choose the topics to play. For the running recording it shows the head and the live statistics.
class RecordingOverview extends StatelessWidget {
  const RecordingOverview({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<RecorderViewmodel>();
    if (vm.liveSelected && vm.isRecording) {
      return _buildLive(context, vm);
    }
    var info = vm.selected;
    if (info == null) {
      var theme = Theme.of(context);
      return Center(
          child: Text('recorder.noselection.watermark'.tr(),
              style: theme.textTheme.headlineMedium!.copyWith(color: theme.dividerColor)));
    }
    return _buildRecording(context, vm, info);
  }

  Widget _buildLive(BuildContext context, RecorderViewmodel vm) {
    var summary = vm.liveSummary;
    var topics = summary == null ? <String>[] : (summary.perTopic.keys.toList()..sort());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RecordingHead(
        name: vm.liveName,
        meta: 'recorder.live.meta'.tr(args: [
          RecorderFormat.clock(vm.liveElapsed),
          RecorderFormat.count(vm.liveMessages),
          RecorderFormat.bytes(vm.liveBytes),
          RecorderFormat.count(vm.liveExcluded),
        ]),
        filters: vm.liveFilters,
      ),
      Expanded(
        child: _TableFrame(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _buildTableHeader(context, null),
            Expanded(
              child: ListView(children: [
                for (var topic in topics)
                  _buildRow(context, topic, summary!.perTopic[topic]!, vm.liveColorOf(topic), vm.liveElapsed, null),
              ]),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildRecording(BuildContext context, RecorderViewmodel vm, RecordingInfo info) {
    var footer = info.footer;
    var header = info.header;
    var topics = List.of(footer.topics)..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(height: 8),
      _buildFacts(context, vm, info),
      Expanded(
        child: _TableFrame(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _buildTableHeader(context, vm),
            Expanded(
              child: ListView(children: [
                for (var topic in topics)
                  _buildRow(context, topic, footer.summary.perTopic[topic] ?? TopicSummary(),
                      _colorOf(topic, header.filters), footer.duration, vm),
              ]),
            ),
          ]),
        ),
      ),
      _buildFoot(context, vm),
    ]);
  }

  TopicColor _colorOf(String topic, List<RecorderFilter> filters) =>
      RecorderRules.colorFilterOf(topic, filters)?.color ?? TopicColor(Colors.black);

  Widget _buildFacts(BuildContext context, RecorderViewmodel vm, RecordingInfo info) {
    var theme = Theme.of(context);
    var summary = info.footer.summary;
    var snapshotTopics = summary.perTopic.values.where((topic) => topic.snapshotCount > 0).length;
    var gaps = summary.markers[RecordingMarker.connectionLost] ?? 0;
    var bookmarks = info.footer.bookmarks;
    var bold = theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w500);
    Widget fact(String label, String value) =>
        Text.rich(TextSpan(children: [TextSpan(text: '$label ', style: bold), TextSpan(text: value)]));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(spacing: 24, runSpacing: 4, children: [
        fact('recorder.snapshot.label'.tr(), 'recorder.topics.count'.tr(args: ['$snapshotTopics'])),
        fact('recorder.connectiongaps.label'.tr(), '$gaps'),
        if (bookmarks.isNotEmpty)
          fact('recorder.bookmarks.label'.tr(),
              bookmarks.map((bookmark) => '${bookmark.label} ${RecorderFormat.clock(bookmark.offset)}').join(' · ')),
        if (info.footer.notes.isNotEmpty) fact('recorder.notes.label'.tr(), info.footer.notes),
      ]),
    );
  }

  Widget _buildTableHeader(BuildContext context, RecorderViewmodel? vm) {
    var theme = Theme.of(context);
    var style = theme.textTheme.bodySmall!.copyWith(color: theme.hintColor);
    var info = vm?.selected;
    bool? allChecked;
    if (vm != null && info != null) {
      var count = vm.selectedTopicCount;
      allChecked = count == info.footer.topics.length ? true : (count == 0 ? false : null);
    }
    return Container(
      height: 36,
      padding: EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
      child: Row(children: [
        SizedBox(
          width: _Columns.check,
          child: vm == null
              ? null
              : Tooltip(
                  message: 'recorder.playall.tooltip'.tr(),
                  child: Checkbox(tristate: true, value: allChecked, onChanged: (_) => vm.setAllTopics(allChecked != true)),
                ),
        ),
        Expanded(child: Text('recorder.column.topic'.tr(), style: style)),
        _cell(_Columns.count, Text('recorder.column.messages'.tr(), style: style), right: true),
        _cell(_Columns.rate, Text('recorder.column.rate'.tr(), style: style), right: true),
        _cell(_Columns.interval, Text('recorder.column.interval'.tr(), style: style), right: true),
        _cell(_Columns.range, Text('recorder.column.range'.tr(), style: style), right: true),
        _cell(_Columns.kind, Text('recorder.column.payload'.tr(), style: style)),
        _cell(_Columns.size, Text('recorder.column.size'.tr(), style: style), right: true),
        _cell(_Columns.duplicates, Text('recorder.column.duplicates'.tr(), style: style), right: true),
        _cell(_Columns.gaps, Text('recorder.column.gaps'.tr(), style: style), right: true),
        _cell(_Columns.retained, Text('recorder.column.retained'.tr(), style: style)),
      ]),
    );
  }

  Widget _buildRow(
      BuildContext context, String topic, TopicSummary stats, TopicColor color, Duration duration, RecorderViewmodel? vm) {
    var theme = Theme.of(context);
    var hint = theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor);
    var seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
    var median = stats.medianInterval;
    var range = stats.intervalMinMicros == null
        ? '–'
        : '${RecorderFormat.duration(Duration(microseconds: stats.intervalMinMicros!))} – '
            '${RecorderFormat.duration(Duration(microseconds: stats.intervalMaxMicros!))}';
    var retained = stats.snapshotCount > 0
        ? 'recorder.retained.snapshot'.tr()
        : stats.retainedCount > 0
            ? RecorderFormat.count(stats.retainedCount)
            : '–';
    return Container(
      height: 44,
      padding: EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
      child: Row(children: [
        SizedBox(
          width: _Columns.check,
          child: vm == null
              ? null
              : Checkbox(value: vm.isTopicSelected(topic), onChanged: (play) => vm.toggleTopic(topic, play ?? false)),
        ),
        // a long topic is cut at the column edge, the tooltip shows all of it
        Expanded(
          child: Tooltip(
            message: topic,
            child: ClipRect(
              child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  // keeps the chip at its own height instead of the row's
                  minHeight: 0,
                  child: FastTopicChip(topic: topic, topicColor: color, onPressed: null)),
            ),
          ),
        ),
        _cell(_Columns.count, Text(RecorderFormat.count(stats.count)), right: true),
        _cell(_Columns.rate, Text(seconds <= 0 ? '–' : RecorderFormat.messagesPerSecond(stats.count / seconds)), right: true),
        _cell(_Columns.interval, Text(median == null ? '–' : RecorderFormat.duration(median)), right: true),
        _cell(_Columns.range, Text(range, style: hint), right: true),
        _cell(_Columns.kind, Text(stats.mainKind == null ? '–' : 'recorder.kind.${stats.mainKind}'.tr())),
        _cell(_Columns.size, Text(RecorderFormat.bytes(stats.averagePayload)), right: true),
        _cell(_Columns.duplicates, Text(RecorderFormat.count(stats.consecutiveDuplicates)), right: true),
        _cell(_Columns.gaps, _buildGaps(context, vm, topic), right: true),
        _cell(_Columns.retained, Text(retained, style: hint)),
      ]),
    );
  }

  // known once the analysis of the recording is done; the TIMELINE lists them
  Widget _buildGaps(BuildContext context, RecorderViewmodel? vm, String topic) {
    var count = vm?.gapCountOf(topic);
    if (count == null) {
      return Text('–', style: TextStyle(color: Theme.of(context).hintColor));
    }
    return Text(RecorderFormat.count(count),
        style: count > 0 ? TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w500) : null);
  }

  Widget _buildFoot(BuildContext context, RecorderViewmodel vm) {
    var theme = Theme.of(context);
    var hint = theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor);
    var info = vm.selected!;
    var estimate = vm.estimate;
    var player = vm.player;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerColor))),
      child: Row(children: [
        Text('recorder.selectedtopics.label'.tr(args: ['${vm.selectedTopicCount}', '${info.footer.topics.length}']),
            style: hint),
        SizedBox(width: 24),
        if (player != null && vm.playbackState != PlaybackState.stopped) Expanded(child: _buildProgress(context, vm, player)),
        if (player == null || vm.playbackState == PlaybackState.stopped) Spacer(),
        Text(
            'recorder.estimate.label'
                .tr(args: [RecorderFormat.rate(estimate.rate), RecorderFormat.speed(vm.options.speed), RecorderFormat.rate(estimate.peak)]),
            style: hint),
      ]),
    );
  }

  Widget _buildProgress(BuildContext context, RecorderViewmodel vm, RecordingPlayer player) {
    var theme = Theme.of(context);
    var start = player.rangeStartMicros;
    var length = player.rangeEndMicros - start;
    var progress = length <= 0 ? 0.0 : ((player.positionMicros - start) / length).clamp(0.0, 1.0);
    var label = vm.playbackState == PlaybackState.paused ? 'recorder.paused.label'.tr() : 'recorder.playing.label'.tr();
    return Row(children: [
      Text(label, style: theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w500)),
      SizedBox(width: 12),
      SizedBox(width: 160, child: LinearProgressIndicator(value: progress)),
      SizedBox(width: 12),
      Flexible(
        child: Text(
          'recorder.progress.label'.tr(args: [
            RecorderFormat.clock(Duration(microseconds: player.positionMicros)),
            RecorderFormat.count(player.sent),
            RecorderFormat.duration(Duration(microseconds: player.lagMicros)),
            if (player.loopCount > 0) '${player.loopCount}' else '0',
          ]),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }

  Widget _cell(double width, Widget child, {bool right = false}) => SizedBox(
      width: width,
      child: Align(
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(padding: EdgeInsets.only(left: 8), child: child)));
}
