import 'package:auto_size_text_pk/auto_size_text_pk.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/common/colorExt.dart';

class TopicChip extends StatefulWidget {
  final TopicColor topicColor;
  final String topic;
  final String? countLabel;
  final DateTime? receivedTime;
  final bool paused;
  final bool dense;
  final bool unlimitedWidth;
  final bool selected;
  final bool showGlowAnimation;
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
      this.countLabel,
      this.receivedTime,
      this.showGlowAnimation = false,
      this.unlimitedWidth = false})
      : super(key: key);

  @override
  State<TopicChip> createState() => _TopicChipState();
}

class _TopicChipState extends State<TopicChip> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation _animation;

  @override
  void initState() {
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: 400));
    _animation = TweenSequence([
      TweenSequenceItem<double>(tween: Tween<double>(begin: 1, end: 1.1), weight: 50),
      TweenSequenceItem<double>(tween: Tween<double>(begin: 1.1, end: 1), weight: 50)
    ]).animate(_controller);
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showGlowAnimation) {
      _controller.reset();
      _controller.forward();
    }
    var bgColor = widget.paused
        ? Theme.of(context).custom.watermark
        : widget.selected
            ? widget.topicColor.color.lighten(0.3)
            : widget.topicColor.color;
    var textColor = bgColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    var labelWidget =
        AutoSizeText(widget.topic, minFontSize: 10, style: Theme.of(context).textTheme.titleSmall!.copyWith(color: textColor));
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: widget.unlimitedWidth
              ? double.infinity
              : widget.dense
                  ? 1800
                  : 800),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _animation.value,
            child: InputChip(
              showCheckmark: false,
              selected: widget.paused || widget.selected,
              selectedColor: widget.selected ? widget.topicColor.color.lighten(0.3) : Theme.of(context).custom.watermark,
              onPressed: widget.onPressed,
              label: widget.unlimitedWidth
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 8, right: 4),
                      child: Row(
                        children: [
                          Expanded(child: labelWidget),
                        ],
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        labelWidget,
                        widget.countLabel != null
                            ? Row(
                                children: [
                                  SizedBox(width: 12),
                                  Text('|', style: Theme.of(context).textTheme.titleSmall!.copyWith(color: textColor)),
                                  SizedBox(width: 12),
                                  Text('# ' + widget.countLabel!,
                                      style: Theme.of(context).textTheme.titleSmall!.copyWith(color: textColor)),
                                ],
                              )
                            : SizedBox(),
                        widget.receivedTime != null
                            ? Row(
                                children: [
                                  SizedBox(width: 12),
                                  Text('|', style: Theme.of(context).textTheme.titleSmall!.copyWith(color: textColor)),
                                  SizedBox(width: 12),
                                  Text(DateFormat('HH:mm:ss').format(widget.receivedTime!),
                                      style: Theme.of(context).textTheme.titleSmall!.copyWith(color: textColor)),
                                ],
                              )
                            : SizedBox(),
                      ],
                    ),
              backgroundColor: widget.topicColor.color,
              deleteIcon: widget.onDeletePressed != null ? Icon(Icons.cancel_rounded, color: textColor) : Container(),
              onDeleted: widget.onDeletePressed != null ? () => widget.onDeletePressed!(widget.topic) : null,
              elevation: 2,
            ),
          );
        },
      ),
    );
  }
}
