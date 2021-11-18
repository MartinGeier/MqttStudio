import 'package:auto_size_text_pk/auto_size_text_pk.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/common/colorExt.dart';

class TopicChip extends StatelessWidget {
  final TopicColor topicColor;
  final String topic;
  final bool paused;
  final bool dense;
  final bool unlimitedWidth;
  final bool selected;
  final void Function(String)? onDeletePressed;
  final void Function()? onPressed;

  const TopicChip(
      {Key? key,
      required this.topic,
      required this.topicColor,
      required this.onPressed,
      this.onDeletePressed,
      this.selected = false,
      this.paused = false,
      this.dense = true,
      this.unlimitedWidth = false})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    var bgColor = paused
        ? Theme.of(context).custom.watermark
        : selected
            ? topicColor.color.lighten(0.3)
            : topicColor.color;
    var textColor = bgColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    var labelWidget = AutoSizeText(topic, minFontSize: 10, style: Theme.of(context).textTheme.subtitle2!.copyWith(color: textColor));
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: unlimitedWidth
              ? double.infinity
              : dense
                  ? 400
                  : 800),
      child: InputChip(
        showCheckmark: false,
        selected: paused || selected,
        selectedColor: selected ? topicColor.color.lighten(0.3) : Theme.of(context).custom.watermark,
        onPressed: onPressed,
        label: unlimitedWidth
            ? Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8, right: 4),
                child: Row(
                  children: [
                    Expanded(child: labelWidget),
                  ],
                ),
              )
            : labelWidget,
        backgroundColor: topicColor.color,
        deleteIcon: onDeletePressed != null ? Icon(Icons.cancel_rounded, color: textColor) : Container(),
        onDeleted: onDeletePressed != null ? () => onDeletePressed!(topic) : null,
        elevation: 2,
      ),
    );
  }
}
