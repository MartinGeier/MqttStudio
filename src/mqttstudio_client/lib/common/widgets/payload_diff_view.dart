import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/common/utils/json_diff.dart';
import 'package:mqttstudio/custom_theme.dart';

const TextStyle diffTextStyle = TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['Cascadia Mono', 'monospace'], fontSize: 13);

// Shows how a payload changed. Decoded JSON is pretty printed with the changed lines highlighted, other payloads as
// text. Without a side it shows the current payload with the removed members struck out; with a side it shows only
// that side, for two payloads side by side.
class PayloadDiffView extends StatelessWidget {
  final Object? oldValue;
  final Object? newValue;
  final JsonDiffSide? side;

  const PayloadDiffView({Key? key, required this.oldValue, required this.newValue, this.side}) : super(key: key);

  static bool isStructured(Object? value) => value is Map || value is List;

  @override
  Widget build(BuildContext context) {
    if (isStructured(oldValue) && isStructured(newValue)) {
      return _buildJson(context);
    }
    return _buildText(context);
  }

  Widget _buildJson(BuildContext context) {
    var lines = JsonDiff.lines(oldValue, newValue, side ?? JsonDiffSide.current, withRemoved: side == null);
    return SelectionArea(
      child: ListView.builder(
        itemCount: lines.length,
        itemBuilder: (context, index) => _buildLine(context, lines[index]),
      ),
    );
  }

  Widget _buildLine(BuildContext context, JsonDiffLine line) {
    var removed = line.kind == JsonChangeKind.removed;
    return Container(
      color: _colorOf(context, line.kind),
      padding: EdgeInsets.only(left: 4.0 + line.indent * 16, top: 1, bottom: 1),
      child: Text.rich(TextSpan(children: [
        TextSpan(
            text: line.text,
            style: removed ? diffTextStyle.copyWith(decoration: TextDecoration.lineThrough) : diffTextStyle),
        if (line.otherValue != null)
          TextSpan(
              text: '  ${(side == JsonDiffSide.old ? 'payloaddiff.now.label' : 'payloaddiff.was.label').tr(args: [line.otherValue!])}',
              style: diffTextStyle.copyWith(color: Theme.of(context).hintColor, fontStyle: FontStyle.italic)),
      ])),
    );
  }

  Widget _buildText(BuildContext context) {
    var oldText = _textOf(oldValue);
    var newText = _textOf(newValue);
    var changed = oldText != newText;
    if (side != null) {
      var text = side == JsonDiffSide.old ? oldText : newText;
      return _buildTextBlock(context, text, changed ? JsonChangeKind.changed : null);
    }
    if (!changed) {
      return _buildTextBlock(context, newText, null);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Flexible(child: _buildTextBlock(context, oldText, JsonChangeKind.removed)),
      SizedBox(height: 8),
      Flexible(child: _buildTextBlock(context, newText, JsonChangeKind.added)),
    ]);
  }

  static String _textOf(Object? value) => value is String ? value : JsonDiff.compact(value);

  Widget _buildTextBlock(BuildContext context, String text, JsonChangeKind? kind) {
    return Container(
      color: _colorOf(context, kind),
      padding: EdgeInsets.all(4),
      child: SingleChildScrollView(
          child: SelectableText(text,
              style: kind == JsonChangeKind.removed
                  ? diffTextStyle.copyWith(decoration: TextDecoration.lineThrough)
                  : diffTextStyle)),
    );
  }

  static Color? _colorOf(BuildContext context, JsonChangeKind? kind) {
    var colors = Theme.of(context).custom;
    switch (kind) {
      case JsonChangeKind.added:
        return colors.diffAdded;
      case JsonChangeKind.removed:
        return colors.diffRemoved;
      case JsonChangeKind.changed:
        return colors.diffChanged;
      case null:
        return null;
    }
  }
}
