import 'package:easy_localization/easy_localization.dart';
import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/recorder/engine/recorder_service.dart';
import 'package:mqttstudio/recorder/widgets/recorder_format.dart';

// The pill in the app bar that shows a running recording on every tab (R18). Tapping it opens the RECORDER tab.
class RecIndicator extends StatefulWidget {
  // index of the RECORDER tab
  final int recorderTab;

  const RecIndicator({Key? key, required this.recorderTab}) : super(key: key);

  @override
  State<RecIndicator> createState() => _RecIndicatorState();
}

class _RecIndicatorState extends State<RecIndicator> {
  final _recorder = GetIt.I.get<RecorderService>();

  @override
  void initState() {
    super.initState();
    _recorder.stateChangedEvent.subscribe(_onChanged);
    _recorder.statsChangedEvent.subscribe(_onChanged);
  }

  @override
  void dispose() {
    _recorder.stateChangedEvent.unsubscribe(_onChanged);
    _recorder.statsChangedEvent.unsubscribe(_onChanged);
    super.dispose();
  }

  void _onChanged(EventArgs? _) {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_recorder.isRecording) {
      return SizedBox.shrink();
    }
    var theme = Theme.of(context);
    var onPrimary = theme.colorScheme.onPrimary;
    // outlined while nothing is written yet
    var waiting = _recorder.state == RecorderState.connecting || _recorder.isWaitingForTrigger;
    var reconnecting = _recorder.state == RecorderState.reconnecting;
    var background = waiting
        ? Colors.transparent
        : reconnecting
            ? theme.textTheme.bodyMedium!.color!
            : theme.custom.recordingColor;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Center(
        child: Tooltip(
          message: 'recindicator.tooltip'.tr(),
          child: Material(
            color: background,
            shape: StadiumBorder(side: waiting ? BorderSide(color: onPrimary, width: 2) : BorderSide.none),
            child: InkWell(
              customBorder: StadiumBorder(),
              onTap: () => DefaultTabController.of(context).animateTo(widget.recorderTab),
              child: Container(
                height: 32,
                padding: EdgeInsets.only(left: 8, right: 12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: onPrimary, shape: BoxShape.circle)),
                  SizedBox(width: 8),
                  Text(_label(), style: theme.textTheme.labelLarge!.copyWith(color: onPrimary, fontFeatures: [FontFeature.tabularFigures()])),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _label() {
    switch (_recorder.state) {
      case RecorderState.connecting:
        return 'recindicator.connecting.label'.tr();
      case RecorderState.reconnecting:
        return 'recindicator.reconnecting.label'.tr(args: ['${_recorder.reconnectAttempt}']);
      case RecorderState.waiting:
        return 'recindicator.waiting.label'.tr(args: [RecorderFormat.count(_recorder.storedMessages)]);
      default:
        if (_recorder.isFlightRecorder) {
          return (_recorder.isSaveScheduled ? 'recindicator.flightsaving.label' : 'recindicator.flight.label').tr(args: [
            RecorderFormat.duration(_recorder.flightSpan),
            RecorderFormat.duration(Duration(seconds: _recorder.config!.flightOptions.windowSeconds)),
            RecorderFormat.bytes(_recorder.storedBytes),
          ]);
        }
        return 'recindicator.recording.label'.tr(args: [
          RecorderFormat.clock(_recorder.elapsed),
          RecorderFormat.count(_recorder.storedMessages),
          RecorderFormat.bytes(_recorder.storedBytes),
        ]);
    }
  }
}
