import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/model/mqtt_protocol_version.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/project/open_project_dialog.dart';
import 'package:mqttstudio/project/project_edit_dialog.dart';
import 'package:mqttstudio/project/project_viewmodel.dart';
import 'package:mqttstudio/project/recent_projects_viewmodel.dart';
import 'package:provider/provider.dart';

// shown in the topic viewer while no project is open
class RecentProjectsPanel extends StatelessWidget {
  static const int _columns = 3;
  static final DateFormat _lastUsedFormat = DateFormat('yyyy-MM-dd HH:mm');

  const RecentProjectsPanel();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RecentProjectsViewmodel(),
      child: Consumer<RecentProjectsViewmodel>(
        builder: (context, viewmodel, child) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 1080),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              SizedBox(height: 12),
              _buildBody(context, viewmodel),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text('recentprojects.title'.tr(), style: Theme.of(context).textTheme.titleLarge)),
        TextButton.icon(
          icon: Icon(Icons.create_new_folder_outlined),
          label: Text('recentprojects.newproject.button'.tr()),
          onPressed: () => _newProject(context),
        ),
        SizedBox(width: 8),
        TextButton.icon(
          icon: Icon(Icons.folder_open),
          label: Text('recentprojects.openproject.button'.tr()),
          onPressed: () => _showOpenProjectDialog(context),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, RecentProjectsViewmodel viewmodel) {
    if (!viewmodel.isLoaded) {
      return SizedBox(height: 88);
    }
    if (viewmodel.projects.isEmpty) {
      return _buildEmpty(context);
    }
    var projects = viewmodel.projects;
    var rows = <Widget>[];
    for (var start = 0; start < projects.length; start += _columns) {
      if (start > 0) {
        rows.add(SizedBox(height: 16));
      }
      rows.add(Row(
        children: [
          for (var i = start; i < start + _columns; i++) ...[
            if (i > start) SizedBox(width: 24),
            Expanded(child: i < projects.length ? _buildProject(context, projects[i]) : SizedBox()),
          ],
        ],
      ));
    }
    return Column(children: rows);
  }

  Widget _buildEmpty(BuildContext context) {
    var theme = Theme.of(context);
    return SizedBox(
      height: 88,
      child: Center(
        child: Text('recentprojects.empty'.tr(),
            style: theme.textTheme.headlineMedium!.copyWith(color: theme.dividerColor)),
      ),
    );
  }

  Widget _buildProject(BuildContext context, Project project) {
    var theme = Theme.of(context);
    var hintStyle = theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor);
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: () => _openProject(context, project),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Image.asset('assets/icons/mqttstudio.png', height: 32),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name,
                        style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    SizedBox(height: 4),
                    Text(_broker(project), style: hintStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    SizedBox(height: 4),
                    Text(_lastUsed(project), style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _broker(Project project) {
    var settings = project.mqttSettings;
    return '${settings.hostname}:${settings.port} | ${settings.protocolVersion.displayName}';
  }

  String _lastUsed(Project project) {
    var lastUsed = project.lastUsed;
    return lastUsed == null ? '' : 'recentprojects.lastused'.tr(args: [_lastUsedFormat.format(lastUsed.toLocal())]);
  }

  Future _openProject(BuildContext context, Project project) async {
    await context.read<ProjectViewmodel>().openProject(project);
  }

  Future _newProject(BuildContext context) async {
    var projectViewmodel = context.read<ProjectViewmodel>();
    Project? project = await showDialog(context: context, builder: (context) => ProjectEditDialog());
    if (project != null) {
      await projectViewmodel.openProject(project);
    }
  }

  Future _showOpenProjectDialog(BuildContext context) async {
    await showDialog(context: context, builder: (context) => OpenProjectDialog());
  }
}
