import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/recorder/recorder_viewmodel.dart';
import 'package:mqttstudio/recorder/widgets/recorder_format.dart';
import 'package:srx_flutter/srx_flutter.dart';

// How to split a recording: at its bookmarks, at the playhead or by topic. Returns a SplitMode or null.
class SplitDialog extends StatelessWidget {
  final int bookmarkCount;
  final int? playheadMicros;
  final int topicCount;

  const SplitDialog({Key? key, required this.bookmarkCount, this.playheadMicros, required this.topicCount}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text('split.title'.tr()),
      contentPadding: EdgeInsets.all(16),
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: 480, maxWidth: 480),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _option(context, Icons.bookmark, 'split.bookmarks.label'.tr(args: ['$bookmarkCount', '${bookmarkCount + 1}']),
                bookmarkCount > 0 ? SplitMode.atBookmarks : null),
            _option(
                context,
                Icons.vertical_split,
                playheadMicros == null
                    ? 'split.playhead.disabled'.tr()
                    : 'split.playhead.label'.tr(args: [RecorderFormat.clock(Duration(microseconds: playheadMicros!))]),
                playheadMicros == null ? null : SplitMode.atPlayhead),
            _option(context, Icons.account_tree, 'split.topics.label'.tr(args: ['$topicCount']),
                topicCount > 1 ? SplitMode.byTopic : null),
            SizedBox(height: 16),
            SrxFormRow(alignment: CrossAxisAlignment.center, children: [
              Spacer(flex: 6),
              Expanded(
                  flex: 5,
                  child: OutlinedButton(
                      onPressed: () => GetIt.I.get<SrxNavigationService>().pop(null), child: Text('srx.common.cancel'.tr()))),
            ]),
          ]),
        ),
      ],
    );
  }

  Widget _option(BuildContext context, IconData icon, String label, SplitMode? mode) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      enabled: mode != null,
      onTap: mode == null ? null : () => GetIt.I.get<SrxNavigationService>().pop(mode),
    );
  }
}
