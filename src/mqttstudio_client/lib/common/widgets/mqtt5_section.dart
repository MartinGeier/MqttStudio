import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// Collapsed form section for settings that only exist in MQTT 5. It stays visible but disabled for MQTT 3.1.1 projects.
class Mqtt5Section extends StatelessWidget {
  final String title;
  final bool enabled;
  final List<Widget> children;

  const Mqtt5Section({Key? key, required this.title, required this.enabled, required this.children})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      enabled: enabled,
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.only(top: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      // the text theme carries a color, which would override the disabled color of the tile
      title: Text(title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: enabled ? null : Theme.of(context).disabledColor)),
      subtitle: enabled ? null : Text('mqtt5section.disabled.hint'.tr()),
      children: children,
    );
  }
}
