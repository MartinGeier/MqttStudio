import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

// The about dialog of the navigation drawer and the macOS app menu
Future showAboutMqttStudio() async {
  var info = await PackageInfo.fromPlatform();
  var context = GetIt.I.get<SrxNavigationService>().navigatorKey.currentContext!;
  if (!context.mounted) {
    return;
  }
  showAboutDialog(
      context: context,
      applicationIcon: Image.asset('./assets/icons/mqttstudio128.png', height: 64),
      applicationName: 'MQTT Studio',
      applicationVersion: 'v${info.version}',
      applicationLegalese: 'copyright_text'.tr(),
      children: [
        SizedBox(height: 16),
        SizedBox(width: 600, child: Text('aboutdialog.marketing_text'.tr(), style: Theme.of(context).textTheme.bodyMedium)),
        SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.web, size: 20),
            SizedBox(width: 6),
            _Link('www.mqttstudio.com', onTap: openWebsite),
            SizedBox(width: 24),
            Icon(Icons.email, size: 20),
            SizedBox(width: 6),
            _Link('info@sarix.eu', onTap: writeEmail),
          ],
        )
      ]);
}

Future openWebsite() async {
  await UrlLauncherPlatform.instance.launchUrl('https://www.mqttstudio.com', LaunchOptions());
}

Future writeEmail() async {
  await UrlLauncherPlatform.instance.launchUrl('mailto://info@sarix.eu', LaunchOptions());
}

// a text that is underlined while the mouse is over it
class _Link extends StatefulWidget {
  final String text;
  final Future Function() onTap;

  const _Link(this.text, {required this.onTap});

  @override
  State<_Link> createState() => _LinkState();
}

class _LinkState extends State<_Link> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    var style = Theme.of(context).textTheme.bodyMedium!;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(widget.text,
            style: _isHovering ? style.copyWith(decoration: TextDecoration.underline) : style),
      ),
    );
  }
}
