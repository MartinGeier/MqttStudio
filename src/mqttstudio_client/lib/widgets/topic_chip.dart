import 'package:auto_size_text_pk/auto_size_text_pk.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/custom_theme.dart';

class TopicChip extends StatelessWidget {
  const TopicChip(
      {Key? key, required this.topic, required this.topicColor, required this.onPressed, this.onDeletePressed, this.paused = false})
      : super(key: key);

  final TopicColor topicColor;
  final String topic;
  final bool paused;
  final void Function()? onDeletePressed;
  final void Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    var bgColor = paused ? Theme.of(context).custom.watermark : topicColor.color;
    var textColor = bgColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 400),
      child: InputChip(
        showCheckmark: false,
        selected: paused,
        selectedColor: Theme.of(context).custom.watermark,
        onPressed: onPressed != null ? onPressed : null,
        label: AutoSizeText(topic, minFontSize: 10, style: Theme.of(context).textTheme.subtitle2!.copyWith(color: textColor)),
        backgroundColor: topicColor.color,
        deleteIcon: Icon(Icons.cancel_rounded, color: textColor),
        onDeleted: onDeletePressed != null ? onDeletePressed : null,
        elevation: 2,
      ),
    );
  }
}
