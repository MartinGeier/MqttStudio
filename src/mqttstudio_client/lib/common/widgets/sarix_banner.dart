import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/service/piwik_tracking_service.dart';
import 'package:url_launcher/url_launcher.dart';

// shown in the topic viewer while no project is open
class SarixBanner extends StatelessWidget {
  static const String _webSite = 'www.sarix.eu';
  static const String _email = 'info@sarix.eu';

  const SarixBanner();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(context),
                  SizedBox(height: 24),
                  _buildStrengths(context),
                  SizedBox(height: 24),
                  _buildLinks(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    var theme = Theme.of(context);
    return Column(
      children: [
        Semantics(
          label: 'sarixbanner.logo.semantics'.tr(),
          image: true,
          child: Image.asset('assets/images/sarix_logo.png', width: 168, excludeFromSemantics: true),
        ),
        SizedBox(height: 4),
        Text('sarixbanner.title'.tr(), style: theme.textTheme.headlineSmall),
        SizedBox(height: 4),
        Text('sarixbanner.subtitle'.tr(), style: theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor)),
      ],
    );
  }

  Widget _buildStrengths(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 1080),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildStrength(context, Icons.hub, 'sarixbanner.iot')),
            SizedBox(width: 24),
            Expanded(child: _buildStrength(context, Icons.memory, 'sarixbanner.embedded')),
            SizedBox(width: 24),
            Expanded(child: _buildStrength(context, Icons.settings_suggest, 'sarixbanner.configuration')),
          ],
        ),
      ),
    );
  }

  Widget _buildStrength(BuildContext context, IconData icon, String keyPrefix) {
    var theme = Theme.of(context);
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: theme.custom.sarixTint, shape: BoxShape.circle),
              child: Icon(icon, color: theme.custom.sarixBlue),
            ),
            SizedBox(height: 12),
            Text('$keyPrefix.title'.tr(), style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w500)),
            SizedBox(height: 8),
            Text('$keyPrefix.text'.tr(),
                style: theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildLinks(BuildContext context) {
    var theme = Theme.of(context);
    var linkStyle = TextButton.styleFrom(foregroundColor: theme.custom.sarixBlue);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          style: linkStyle,
          icon: Icon(Icons.language),
          label: Text(_webSite),
          onPressed: () => _open(Uri.parse('https://$_webSite'), 'Sarix website opened'),
        ),
        SizedBox(height: 24, child: VerticalDivider(width: 24)),
        TextButton.icon(
          style: linkStyle,
          icon: Icon(Icons.mail_outline),
          label: Text(_email),
          onPressed: () => _open(Uri.parse('mailto:$_email'), 'Sarix email opened'),
        ),
      ],
    );
  }

  Future _open(Uri uri, String trackingAction) async {
    await launchUrl(uri);
    await PiwikTrackingService().trackAction(trackingAction);
  }
}
