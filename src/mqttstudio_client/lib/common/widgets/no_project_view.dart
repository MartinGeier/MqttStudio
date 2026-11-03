import 'package:flutter/material.dart';
import 'package:mqttstudio/common/widgets/sarix_banner.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/project/recent_projects_panel.dart';

// The topic viewer while no project is open: the recent projects fill the space above the Sarix banner, which has a
// band of its own at the bottom
class NoProjectView extends StatelessWidget {
  const NoProjectView();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          // the empty first child lets spaceBetween center the recent projects in the space above the banner
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: RecentProjectsPanel()),
              ),
              _buildBannerBand(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBannerBand(BuildContext context) {
    var theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.custom.sarixTint,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.all(24),
      child: Center(child: SarixBanner()),
    );
  }
}
