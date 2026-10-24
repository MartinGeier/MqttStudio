import 'dart:math';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/common/widgets/fast_topic_chip.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/recorder/model/recorded_message.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';
import 'package:mqttstudio/recorder/timeline_viewmodel.dart';
import 'package:mqttstudio/recorder/widgets/bookmark_dialog.dart';
import 'package:mqttstudio/recorder/widgets/recorder_format.dart';
import 'package:provider/provider.dart';

// The TIMELINE tab (doc/recorder-design.md §7.3): one lane per topic with its message density, gaps, markers and
// bookmarks. The mouse wheel zooms, dragging the time axis pans, dragging across the lanes selects a range.
class RecordingTimeline extends StatelessWidget {
  static const double labelWidth = 240;
  static const double laneHeight = 30;
  // the topic chips are smaller than in the viewers, with 4px around them in their lane
  static const double chipHeight = 22;
  static const double axisHeight = 36;
  static const double sideWidth = 340;

  const RecordingTimeline({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<TimelineViewmodel>();
    if (vm.info == null) {
      return Container();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildToolbar(context, vm),
      Divider(height: 1),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _TimelineCanvas()),
          Container(
            width: sideWidth,
            decoration: BoxDecoration(border: Border(left: BorderSide(color: Theme.of(context).dividerColor))),
            child: _TimelineSidePanel(),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildToolbar(BuildContext context, TimelineViewmodel vm) {
    var theme = Theme.of(context);
    var hint = theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor);
    var bookmarkAt = vm.bookmarkPosition;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        IconButton(onPressed: () => vm.zoom(0.5), icon: Icon(Icons.zoom_in), tooltip: 'timeline.zoomin.tooltip'.tr()),
        IconButton(onPressed: () => vm.zoom(2), icon: Icon(Icons.zoom_out), tooltip: 'timeline.zoomout.tooltip'.tr()),
        IconButton(onPressed: vm.showAll, icon: Icon(Icons.fit_screen), tooltip: 'timeline.showall.tooltip'.tr()),
        SizedBox(height: 40, child: VerticalDivider()),
        IconButton(
            onPressed: bookmarkAt == null ? null : () => vm.addBookmark(bookmarkAt),
            icon: Icon(Icons.bookmark_add),
            tooltip: bookmarkAt == null ? 'timeline.addbookmark.disabled.tooltip'.tr() : 'timeline.addbookmark.tooltip'.tr()),
        SizedBox(height: 40, child: VerticalDivider()),
        SizedBox(width: 8),
        Expanded(child: _buildRange(context, vm, hint)),
        if (vm.isAnalyzing) ...[
          Text('timeline.analyzing.label'.tr(args: ['${(vm.progress * 100).round()}']), style: hint),
          SizedBox(width: 12),
          SizedBox(width: 160, child: LinearProgressIndicator(value: vm.progress)),
        ],
        if (vm.analysisFailed) Text('timeline.analysisfailed.label'.tr(), style: hint.copyWith(color: theme.colorScheme.error)),
        if (vm.isCoarse) Tooltip(message: 'timeline.coarse.tooltip'.tr(), child: Text('timeline.coarse.label'.tr(), style: hint)),
        SizedBox(width: 8),
      ]),
    );
  }

  Widget _buildRange(BuildContext context, TimelineViewmodel vm, TextStyle hint) {
    if (!vm.hasRange) {
      return Text('timeline.norange.label'.tr(), style: hint, overflow: TextOverflow.ellipsis);
    }
    var from = vm.rangeFromMicros ?? 0;
    var to = vm.rangeToMicros ?? vm.durationMicros;
    return Row(children: [
      Flexible(
        child: Text(
            'timeline.range.label'.tr(args: [
              RecorderFormat.clock(Duration(microseconds: from)),
              RecorderFormat.clock(Duration(microseconds: to)),
              RecorderFormat.duration(Duration(microseconds: to - from)),
            ]),
            overflow: TextOverflow.ellipsis),
      ),
      IconButton(onPressed: vm.clearRange, icon: Icon(Icons.close), tooltip: 'timeline.clearrange.tooltip'.tr()),
    ]);
  }
}

class _TimelineCanvas extends StatefulWidget {
  @override
  State<_TimelineCanvas> createState() => _TimelineCanvasState();
}

class _TimelineCanvasState extends State<_TimelineCanvas> {
  final _scrollController = ScrollController();
  int? _dragStartMicros;
  int? _dragEndMicros;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<TimelineViewmodel>();
    var topics = vm.topics;
    return LayoutBuilder(builder: (context, constraints) {
      var laneWidth = max(1.0, constraints.maxWidth - RecordingTimeline.labelWidth);
      var style = _TimelineStyle.of(context);
      var selection = _dragStartMicros != null && _dragEndMicros != null
          ? (min(_dragStartMicros!, _dragEndMicros!), max(_dragStartMicros!, _dragEndMicros!))
          : vm.hasRange
              ? (vm.rangeFromMicros ?? 0, vm.rangeToMicros ?? vm.durationMicros)
              : null;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(width: RecordingTimeline.labelWidth),
          _buildAxis(vm, laneWidth, style, selection),
        ]),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: RecordingTimeline.labelWidth,
                  child: Column(children: [for (var topic in topics) _buildLabel(context, vm, topic)]),
                ),
                _buildLanes(vm, topics, laneWidth, style, selection),
              ]),
            ),
          ),
        ),
      ]);
    });
  }

  // the same divider below as its lane
  Widget _buildLabel(BuildContext context, TimelineViewmodel vm, String topic) {
    return Container(
      height: RecordingTimeline.laneHeight,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))),
      child: Tooltip(
        message: topic,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: double.infinity,
            minHeight: 0,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: FastTopicChip(
                  topic: topic, topicColor: vm.colorOf(topic), height: RecordingTimeline.chipHeight, onPressed: null),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAxis(TimelineViewmodel vm, double width, _TimelineStyle style, (int, int)? selection) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) => vm.pan((-details.delta.dx * vm.windowMicros / width).round()),
      child: Tooltip(
        message: 'timeline.axis.tooltip'.tr(),
        waitDuration: Duration(seconds: 1),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: CustomPaint(
            size: Size(width, RecordingTimeline.axisHeight),
            painter: _AxisPainter(vm, style, selection),
          ),
        ),
      ),
    );
  }

  Widget _buildLanes(TimelineViewmodel vm, List<String> topics, double width, _TimelineStyle style, (int, int)? selection) {
    int offsetAt(double x) => vm.viewFromMicros + (x.clamp(0, width) / width * vm.windowMicros).round();
    return Listener(
      // the wheel zooms here; over the topic labels it scrolls the lanes
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          GestureBinding.instance.pointerSignalResolver.register(event, (event) {
            var scroll = event as PointerScrollEvent;
            vm.zoom(pow(1.2, scroll.scrollDelta.dy / 40).toDouble(), aroundMicros: offsetAt(scroll.localPosition.dx));
          });
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (details) => setState(() {
          _dragStartMicros = offsetAt(details.localPosition.dx);
          _dragEndMicros = _dragStartMicros;
        }),
        onHorizontalDragUpdate: (details) => setState(() => _dragEndMicros = offsetAt(details.localPosition.dx)),
        onHorizontalDragEnd: (_) {
          var start = _dragStartMicros;
          var end = _dragEndMicros;
          setState(() {
            _dragStartMicros = null;
            _dragEndMicros = null;
          });
          if (start != null && end != null) {
            vm.selectRange(start, end);
          }
        },
        onSecondaryTapUp: (details) => _showMenu(vm, details.globalPosition, offsetAt(details.localPosition.dx)),
        child: CustomPaint(
          size: Size(width, max(1, topics.length) * RecordingTimeline.laneHeight),
          painter: _LanesPainter(vm, topics, style, selection),
        ),
      ),
    );
  }

  Future<void> _showMenu(TimelineViewmodel vm, Offset position, int offsetMicros) async {
    var action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
            value: 'bookmark',
            child: ListTile(
                leading: Icon(Icons.bookmark_add),
                title: Text('timeline.menu.addbookmark'.tr(args: [RecorderFormat.clock(Duration(microseconds: offsetMicros))])),
                dense: true)),
        PopupMenuItem(
            value: 'clear',
            enabled: vm.hasRange,
            child: ListTile(leading: Icon(Icons.close), title: Text('timeline.menu.clearrange'.tr()), dense: true)),
      ],
    );
    switch (action) {
      case 'bookmark':
        await vm.addBookmark(offsetMicros);
      case 'clear':
        vm.clearRange();
    }
  }
}

// Colors of the timeline, from the theme
class _TimelineStyle {
  final Color divider;
  final Color text;
  final Color gap;
  final Color connectionLost;
  final Color reconnected;
  final Color bookmark;
  final Color selection;
  final Color playhead;
  final TextStyle label;

  _TimelineStyle(this.divider, this.text, this.gap, this.connectionLost, this.reconnected, this.bookmark, this.selection,
      this.playhead, this.label);

  factory _TimelineStyle.of(BuildContext context) {
    var theme = Theme.of(context);
    return _TimelineStyle(
      theme.dividerColor,
      theme.hintColor,
      theme.colorScheme.error.withValues(alpha: 0.12),
      theme.custom.disconnectedColor,
      theme.custom.connectedColor,
      theme.colorScheme.primary,
      theme.colorScheme.secondary.withValues(alpha: 0.12),
      theme.colorScheme.secondary,
      theme.textTheme.bodySmall!.copyWith(color: theme.hintColor),
    );
  }
}

double _xOf(TimelineViewmodel vm, int offsetMicros, double width) =>
    (offsetMicros - vm.viewFromMicros) / max(1, vm.windowMicros) * width;

// markers, bookmarks, the selection and the playhead go across the axis and all lanes
void _paintOverlays(Canvas canvas, Size size, TimelineViewmodel vm, _TimelineStyle style, (int, int)? selection) {
  if (selection != null) {
    var left = _xOf(vm, selection.$1, size.width).clamp(0.0, size.width);
    var right = _xOf(vm, selection.$2, size.width).clamp(0.0, size.width);
    canvas.drawRect(Rect.fromLTRB(left, 0, max(left + 1, right), size.height), Paint()..color = style.selection);
  }
  for (var marker in vm.markers) {
    var x = _xOf(vm, marker.offsetMicros, size.width);
    if (x < 0 || x > size.width) {
      continue;
    }
    var color = marker.kind == RecordingMarker.connectionLost
        ? style.connectionLost
        : marker.kind == RecordingMarker.reconnected
            ? style.reconnected
            : style.text;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()
      ..color = color
      ..strokeWidth = 1.5);
  }
  for (var bookmark in vm.bookmarks) {
    var x = _xOf(vm, bookmark.offsetMicros, size.width);
    if (x >= 0 && x <= size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()
        ..color = style.bookmark
        ..strokeWidth = 1.5);
    }
  }
  var playhead = vm.playheadMicros;
  if (playhead != null) {
    var x = _xOf(vm, playhead, size.width);
    if (x >= 0 && x <= size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()
        ..color = style.playhead
        ..strokeWidth = 2);
    }
  }
}

class _AxisPainter extends CustomPainter {
  // tick steps in microseconds, from 1 ms to 1 day
  static const List<int> _steps = [
    1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000, 500000, //
    1000000, 2000000, 5000000, 10000000, 15000000, 30000000, //
    60000000, 120000000, 300000000, 600000000, 900000000, 1800000000, //
    3600000000, 7200000000, 10800000000, 21600000000, 43200000000, 86400000000,
  ];
  static const double _minTickSpacing = 110;

  final TimelineViewmodel vm;
  final _TimelineStyle style;
  final (int, int)? selection;

  _AxisPainter(this.vm, this.style, this.selection);

  @override
  void paint(Canvas canvas, Size size) {
    // nothing reaches into the side panel
    canvas.clipRect(Offset.zero & size);
    var line = Paint()..color = style.divider;
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), line);
    var step = _steps.firstWhere((step) => step / max(1, vm.windowMicros) * size.width >= _minTickSpacing,
        orElse: () => _steps.last);
    var withMillis = step < 1000000;
    // ticks on round local times, e.g. every full 10 s, not every 10 s from the start of the recording
    var start = vm.timeAt(0).toLocal();
    var base = start.microsecondsSinceEpoch + start.timeZoneOffset.inMicroseconds;
    var first = ((base + vm.viewFromMicros) / step).ceil() * step - base;
    for (var offset = first; offset <= vm.viewToMicros; offset += step) {
      var x = _xOf(vm, offset, size.width);
      canvas.drawLine(Offset(x, size.height - 8), Offset(x, size.height), line);
      var time = vm.timeAt(offset).toLocal();
      var label = DateFormat(withMillis ? 'HH:mm:ss.SSS' : 'HH:mm:ss').format(time);
      _text(canvas, label, Offset(x + 3, 4), style.label, maxRight: size.width);
    }
    _paintOverlays(canvas, size, vm, style, selection);
    for (var bookmark in vm.bookmarks) {
      var x = _xOf(vm, bookmark.offsetMicros, size.width);
      if (x >= 0 && x <= size.width) {
        _text(canvas, bookmark.label, Offset(x + 3, 18), style.label.copyWith(color: style.bookmark, fontWeight: FontWeight.w600));
      }
    }
  }

  // a label that would be cut at maxRight is left out
  static void _text(Canvas canvas, String text, Offset at, TextStyle style, {double? maxRight}) {
    var painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    if (maxRight != null && at.dx + painter.width > maxRight) {
      return;
    }
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _LanesPainter extends CustomPainter {
  final TimelineViewmodel vm;
  final List<String> topics;
  final _TimelineStyle style;
  final (int, int)? selection;

  _LanesPainter(this.vm, this.topics, this.style, this.selection);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    const lane = RecordingTimeline.laneHeight;
    var divider = Paint()..color = style.divider;
    var bins = max(1, (size.width / 3).floor());
    var binWidth = size.width / bins;
    for (var i = 0; i < topics.length; i++) {
      var top = i * lane;
      _paintGaps(canvas, size, topics[i], top);
      var counts = vm.densityOf(topics[i], bins);
      var most = counts.fold(0, max);
      if (most > 0) {
        var paint = Paint()..color = vm.colorOf(topics[i]).color;
        for (var bin = 0; bin < bins; bin++) {
          if (counts[bin] == 0) {
            continue;
          }
          // square root, so a few messages next to a burst are still visible
          var height = max(2.0, sqrt(counts[bin] / most) * (lane - 8));
          canvas.drawRect(Rect.fromLTWH(bin * binWidth, top + lane - 4 - height, max(1.0, binWidth - 0.5), height), paint);
        }
      }
      canvas.drawLine(Offset(0, top + lane - 0.5), Offset(size.width, top + lane - 0.5), divider);
    }
    _paintOverlays(canvas, size, vm, style, selection);
  }

  void _paintGaps(Canvas canvas, Size size, String topic, double top) {
    for (var gap in vm.gapsOf(topic)) {
      if (gap.endMicros < vm.viewFromMicros || gap.startMicros > vm.viewToMicros) {
        continue;
      }
      var left = _xOf(vm, gap.startMicros, size.width).clamp(0.0, size.width);
      var right = _xOf(vm, gap.endMicros, size.width).clamp(0.0, size.width);
      var color = gap.connectionLost ? style.connectionLost.withValues(alpha: 0.18) : style.gap;
      canvas.drawRect(Rect.fromLTRB(left, top + 1, max(left + 1, right), top + RecordingTimeline.laneHeight - 1), Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Bookmarks, gaps and duplicates of the recording, next to the lanes
class _TimelineSidePanel extends StatelessWidget {
  static const int _maxGapsShown = 500;
  static const List<int> _thresholdSeconds = [1, 5, 10, 30, 60, 300, 900, 3600];

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<TimelineViewmodel>();
    return ListView(padding: EdgeInsets.symmetric(vertical: 8), children: [
      ..._buildBookmarks(context, vm),
      Divider(),
      ..._buildGaps(context, vm),
      Divider(),
      ..._buildDuplicates(context, vm),
    ]);
  }

  Widget _title(BuildContext context, String text, [Widget? trailing]) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleSmall)),
          if (trailing != null) trailing,
        ]),
      );

  Widget _empty(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(text, style: TextStyle(color: Theme.of(context).hintColor)),
      );

  List<Widget> _buildBookmarks(BuildContext context, TimelineViewmodel vm) {
    var bookmarks = vm.bookmarks;
    return [
      _title(context, 'timeline.bookmarks.title'.tr()),
      if (bookmarks.isEmpty) _empty(context, 'timeline.nobookmarks.label'.tr()),
      for (var bookmark in bookmarks) _buildBookmark(context, vm, bookmark),
    ];
  }

  Widget _buildBookmark(BuildContext context, TimelineViewmodel vm, Bookmark bookmark) {
    return ListTile(
      dense: true,
      leading: Icon(Icons.bookmark, color: Theme.of(context).colorScheme.primary),
      title: Text(bookmark.label),
      subtitle: Text(RecorderFormat.clock(bookmark.offset)),
      onTap: () => vm.reveal(bookmark.offsetMicros, bookmark.offsetMicros),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            onPressed: () => _rename(context, vm, bookmark),
            icon: Icon(Icons.edit, size: 20),
            tooltip: 'timeline.bookmark.edit.tooltip'.tr()),
        IconButton(
            onPressed: () => vm.deleteBookmark(bookmark),
            icon: Icon(Icons.delete, size: 20),
            tooltip: 'timeline.bookmark.delete.tooltip'.tr()),
      ]),
    );
  }

  Future<void> _rename(BuildContext context, TimelineViewmodel vm, Bookmark bookmark) async {
    var label = await BookmarkDialog.show(context, bookmark.label);
    if (label != null) {
      await vm.renameBookmark(bookmark, label);
    }
  }

  List<Widget> _buildGaps(BuildContext context, TimelineViewmodel vm) {
    var gaps = vm.gaps;
    var hint = TextStyle(color: Theme.of(context).hintColor);
    return [
      _title(
        context,
        'timeline.gaps.title'.tr(),
        Tooltip(
          message: 'timeline.gapthreshold.tooltip'.tr(),
          child: DropdownButton<int?>(
            isDense: true,
            value: vm.gapThreshold?.inSeconds,
            onChanged: (seconds) => vm.setGapThreshold(seconds == null ? null : Duration(seconds: seconds)),
            items: [
              DropdownMenuItem(value: null, child: Text('timeline.gapthreshold.default'.tr())),
              for (var seconds in _thresholdSeconds)
                DropdownMenuItem(
                    value: seconds,
                    child: Text('timeline.gapthreshold.label'.tr(args: [RecorderFormat.duration(Duration(seconds: seconds))]))),
            ],
          ),
        ),
      ),
      if (vm.analysis != null && gaps.isEmpty) _empty(context, 'timeline.nogaps.label'.tr()),
      for (var gap in gaps.take(_maxGapsShown))
        ListTile(
          dense: true,
          title: Text(gap.topic, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              'timeline.gap.label'.tr(args: [
                RecorderFormat.clock(Duration(microseconds: gap.startMicros)),
                RecorderFormat.duration(Duration(microseconds: gap.lengthMicros)),
              ]),
              style: hint),
          trailing: gap.connectionLost
              ? Text('timeline.gap.connectionlost'.tr(), style: TextStyle(color: Theme.of(context).custom.disconnectedColor))
              : null,
          onTap: () => vm.reveal(gap.startMicros, gap.endMicros),
        ),
      if (gaps.length > _maxGapsShown) _empty(context, 'timeline.gaps.more'.tr(args: ['${gaps.length - _maxGapsShown}'])),
    ];
  }

  List<Widget> _buildDuplicates(BuildContext context, TimelineViewmodel vm) {
    var duplicates = vm.duplicates;
    return [
      _title(context, 'timeline.duplicates.title'.tr()),
      if (duplicates.isEmpty) _empty(context, 'timeline.noduplicates.label'.tr()),
      for (var entry in duplicates)
        ListTile(
          dense: true,
          title: Text(entry.topic, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              'timeline.duplicates.label'.tr(args: [RecorderFormat.count(entry.consecutive), RecorderFormat.count(entry.quickRepeats)]),
              style: TextStyle(color: Theme.of(context).hintColor)),
        ),
    ];
  }
}
