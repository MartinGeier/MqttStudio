import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';

// A list of short texts as chips in an outlined field: Enter or a comma adds the typed text, the chip's ✕ removes it
class ReactiveTagField extends ReactiveFormField<List<String>, List<String>> {
  ReactiveTagField({Key? key, required String formControlName, required String labelText, bool enabled = true})
      : super(
            key: key,
            formControlName: formControlName,
            builder: (field) => _TagEditor(
                tags: field.value ?? const [], labelText: labelText, enabled: enabled, onChanged: field.didChange));
}

class _TagEditor extends StatefulWidget {
  final List<String> tags;
  final String labelText;
  final bool enabled;
  final void Function(List<String> tags) onChanged;

  const _TagEditor({required this.tags, required this.labelText, required this.enabled, required this.onChanged});

  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!mounted) {
        return;
      }
      if (!_focus.hasFocus) {
        _add(_controller.text);
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(String text) {
    var tags = List.of(widget.tags);
    for (var part in text.split(',')) {
      var tag = part.trim();
      if (tag.isNotEmpty && !tags.contains(tag)) {
        tags.add(tag);
      }
    }
    _controller.clear();
    if (tags.length != widget.tags.length) {
      widget.onChanged(tags);
    }
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return InputDecorator(
        isFocused: _focus.hasFocus,
        isEmpty: widget.tags.isEmpty && _controller.text.isEmpty && !_focus.hasFocus,
        decoration: InputDecoration(
            border: OutlineInputBorder(), labelText: widget.labelText, isDense: true, enabled: widget.enabled),
        child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (var tag in widget.tags)
            Chip(
                label: Text(tag),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                deleteButtonTooltipMessage: 'tagfield.remove.tooltip'.tr(),
                onDeleted: widget.enabled ? () => widget.onChanged(List.of(widget.tags)..remove(tag)) : null),
          if (widget.enabled)
            IntrinsicWidth(
                child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: 120),
                    child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        style: theme.textTheme.bodyMedium,
                        decoration:
                            InputDecoration.collapsed(hintText: _focus.hasFocus ? 'tagfield.add.hint'.tr() : ''),
                        onChanged: (text) {
                          if (text.contains(',')) {
                            _add(text);
                          }
                        },
                        onSubmitted: (text) {
                          _add(text);
                          _focus.requestFocus();
                        })))
        ]));
  }
}
