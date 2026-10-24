import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/common/widgets/error_snackbar.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/recorder/recorder_viewmodel.dart';
import 'package:mqttstudio/recorder/widgets/recorder_command_bar.dart';
import 'package:mqttstudio/recorder/widgets/recording_list.dart';
import 'package:mqttstudio/recorder/widgets/recording_overview.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';

// The RECORDER tab: records topics into the recordings library and plays recordings back
class RecorderPage extends StatefulWidget {
  const RecorderPage({Key? key}) : super(key: key);

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> {
  late final RecorderViewmodel _viewmodel;

  @override
  void initState() {
    super.initState();
    _viewmodel = RecorderViewmodel()
      ..onError = _showError
      ..onWarning = _showWarning
      ..onInfo = _showInfo;
  }

  @override
  void dispose() {
    _viewmodel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewmodel,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RecordingList(),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            RecorderCommandBar(),
            Expanded(child: RecordingOverview()),
          ]),
        ),
      ]),
    );
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    showDialog(
        context: context,
        builder: (_) =>
            SrxTheme(data: CustomTheme.srxTheme, child: SrxDialog.error(title: 'recorder.error.title'.tr(), bodyText: message)));
  }

  void _showWarning(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(message, context));
  }

  void _showInfo(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
