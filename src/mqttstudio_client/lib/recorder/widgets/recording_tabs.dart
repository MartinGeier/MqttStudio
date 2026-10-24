import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/common/widgets/error_snackbar.dart';
import 'package:mqttstudio/message_viewer/message_viewer_viewmodel.dart';
import 'package:mqttstudio/recorder/compare_viewmodel.dart';
import 'package:mqttstudio/recorder/recorder_viewmodel.dart';
import 'package:mqttstudio/recorder/recording_charts_viewmodel.dart';
import 'package:mqttstudio/recorder/recording_messages_viewmodel.dart';
import 'package:mqttstudio/recorder/storage/recording_library.dart';
import 'package:mqttstudio/recorder/timeline_viewmodel.dart';
import 'package:mqttstudio/recorder/widgets/recording_charts_view.dart';
import 'package:mqttstudio/recorder/widgets/recording_compare_view.dart';
import 'package:mqttstudio/recorder/widgets/recording_messages_view.dart';
import 'package:mqttstudio/recorder/widgets/recording_overview.dart';
import 'package:mqttstudio/recorder/widgets/recording_timeline.dart';
import 'package:provider/provider.dart';

// The selected recording below the command bar: its head and the OVERVIEW, TIMELINE, MESSAGES, CHARTS and COMPARE
// tabs.
// The tab viewmodels live as long as this widget, so switching tabs keeps their state; only the visible tab loads.
class RecordingTabs extends StatefulWidget {
  static const int overviewTab = 0;
  static const int timelineTab = 1;
  static const int messagesTab = 2;
  static const int chartsTab = 3;
  static const int compareTab = 4;

  const RecordingTabs({Key? key}) : super(key: key);

  @override
  State<RecordingTabs> createState() => _RecordingTabsState();
}

class _RecordingTabsState extends State<RecordingTabs> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this)..addListener(_onTabChanged);
  final _timeline = TimelineViewmodel();
  final _messages = RecordingMessagesViewmodel();
  late final MessageViewerViewmodel _viewer = MessageViewerViewmodel(source: _messages.source);
  final _charts = RecordingChartsViewmodel();
  final _compare = CompareViewmodel();
  // what each tab shows, so a rebuild during playback doesn't load again
  final Map<int, String> _shown = {};
  String? _messagesRecordingId;

  @override
  void initState() {
    super.initState();
    _timeline.onRangeSelected = (from, to) => context.read<RecorderViewmodel>().setRange(from, to);
    _timeline.onSaveFailed = (message) => ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(message, context));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _timeline.dispose();
    _viewer.dispose();
    _messages.dispose();
    _charts.dispose();
    _compare.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<RecorderViewmodel>();
    var info = vm.selected!;
    WidgetsBinding.instance.addPostFrameCallback((_) => _showActive(info, vm.options.rangeStartMicros, vm.options.rangeEndMicros));
    var theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RecordingHead.of(info),
      TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.hintColor,
        indicatorColor: theme.colorScheme.secondary,
        tabs: [
          Tab(text: 'recorder.tab.overview'.tr()),
          Tab(text: 'recorder.tab.timeline'.tr()),
          Tab(text: 'recorder.tab.messages'.tr()),
          Tab(text: 'recorder.tab.charts'.tr()),
          Tab(text: 'recorder.tab.compare'.tr()),
        ],
      ),
      Divider(height: 1),
      Expanded(
        child: AnimatedBuilder(
          animation: _tabs,
          builder: (context, _) => IndexedStack(index: _tabs.index, children: [
            RecordingOverview(),
            ChangeNotifierProvider.value(value: _timeline, child: RecordingTimeline()),
            MultiProvider(providers: [
              ChangeNotifierProvider.value(value: _messages),
              ChangeNotifierProvider.value(value: _viewer),
            ], child: RecordingMessagesView()),
            ChangeNotifierProvider.value(value: _charts, child: RecordingChartsView()),
            ChangeNotifierProvider.value(value: _compare, child: RecordingCompareView()),
          ]),
        ),
      ),
    ]);
  }

  void _onTabChanged() {
    var vm = context.read<RecorderViewmodel>();
    var info = vm.selected;
    if (info != null && !_tabs.indexIsChanging) {
      _showActive(info, vm.options.rangeStartMicros, vm.options.rangeEndMicros);
    }
  }

  void _showActive(RecordingInfo info, int? rangeFrom, int? rangeTo) {
    if (!mounted) {
      return;
    }
    var tab = _tabs.index;
    var bookmarks = info.footer.bookmarks.map((b) => '${b.offsetMicros}:${b.label}').join(',');
    var key = '${info.id}|${info.fileName}|${info.size}|$bookmarks|$rangeFrom|$rangeTo';
    if (_shown[tab] == key) {
      return;
    }
    _shown[tab] = key;
    switch (tab) {
      case RecordingTabs.timelineTab:
        _timeline.show(info, rangeFrom: rangeFrom, rangeTo: rangeTo);
      case RecordingTabs.messagesTab:
        // a selected message of another recording would stay in the detail view
        if (_messagesRecordingId != info.id) {
          _messagesRecordingId = info.id;
          _viewer.selectedMessage = null;
        }
        _messages.show(info, rangeFrom: rangeFrom, rangeTo: rangeTo);
      case RecordingTabs.chartsTab:
        _charts.show(info, rangeFrom: rangeFrom, rangeTo: rangeTo);
      case RecordingTabs.compareTab:
        _compare.show(info, rangeFrom: rangeFrom, rangeTo: rangeTo);
    }
  }
}
