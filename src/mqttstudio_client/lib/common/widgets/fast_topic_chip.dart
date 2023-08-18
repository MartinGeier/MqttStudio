import 'package:flutter/material.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/common/colorExt.dart';

class FastTopicChip extends StatelessWidget {
  final TopicColor topicColor;
  final String topic;
  final DateTime? receivedTime;
  final bool dense;
  final bool selected;
  final void Function()? onPressed;

  const FastTopicChip({
    Key? key,
    required this.topic,
    required this.topicColor,
    required this.onPressed,
    this.selected = false,
    this.dense = true,
    this.receivedTime,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var bgColor = selected ? topicColor.color.lighten(0.3) : topicColor.color;
    var textColor = bgColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    var textStyle = Theme.of(context).textTheme.titleSmall!.copyWith(color: textColor);
    var width = calculateTextWidth(topic, textStyle);
    return InkWell(
      onTap: onPressed != null ? () => onPressed!() : null,
      child: SizedBox(
          height: 28,
          width: width,
          child: CustomPaint(
            painter: RectanglePainter(topic, bgColor, textStyle, width),
          )),
    );
  }

  double calculateTextWidth(String text, TextStyle textStyle) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    return textPainter.width;
  }
}

class RectanglePainter extends CustomPainter {
  final String label;
  final Color backgroundColor;
  final TextStyle labelStyle;
  final double width;

  const RectanglePainter(this.label, this.backgroundColor, this.labelStyle, this.width);

  @override
  void paint(Canvas canvas, Size size) {
    final double borderRadius = 20.0; // Adjust the corner radius as needed
    final Rect rect = Rect.fromPoints(Offset(0, 0), Offset(width + 20, size.height));
    final RRect roundedRect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));
    final Paint paint = Paint()..color = backgroundColor; // Set your desired color here
    canvas.drawRRect(roundedRect, paint);

    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: labelStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width); // Adjust maximum width as needed

    final double textX = 10; // Align to the left
    final double textY = (size.height - textPainter.height) / 2;

    textPainter.paint(canvas, Offset(textX, textY));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false; // Since the rectangle never changes, no need to repaint
  }
}
