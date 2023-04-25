import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/project/open_project_viewmodel.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

class OpenProjectDialog extends StatelessWidget {
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return _buildBody(context);
  }

  Widget _buildBody(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OpenProjectViewmodel(),
      child: Consumer<OpenProjectViewmodel>(
        builder: (context, viewmodel, child) {
          return SimpleDialog(title: Text('open_project.title'.tr()), contentPadding: EdgeInsets.all(16), children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 400, maxWidth: 400, maxHeight: 400),
              child: Column(
                children: [
                  Expanded(
                      child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: ListView.builder(
                        controller: _scrollController,
                        itemCount: viewmodel.projects.length,
                        itemBuilder: (context, index) => _buildProjectItem(context, index, viewmodel)),
                  )),
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                            onPressed: () {
                              GetIt.I.get<SrxNavigationService>().pop(null);
                            },
                            child: Text('srx.common.cancel'.tr())),
                      ],
                    ),
                  )
                ],
              ),
            )
          ]);
        },
      ),
    );
  }

  Widget _buildProjectItem(BuildContext context, int index, OpenProjectViewmodel viewmodel) {
    if (viewmodel.projects.isEmpty) {
      return Container();
    }

    var project = viewmodel.projects[index];
    return ListTile(
      title: Text(project.name, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(project.mqttSettings.hostname),
      leading: Image.asset('assets/images/logo.png', height: 32),
      minLeadingWidth: 0,
      trailing: IconButton(icon: Icon(Icons.delete), onPressed: () => deleteProject(project, viewmodel)),
      onTap: () => _onTap(project, context),
    );
  }
}

Future deleteProject(Project project, OpenProjectViewmodel viewmodel) async {
  await viewmodel.deleteProject(project);
}

Future _onTap(Project project, BuildContext context) async {
  context.read<ProjectGlobalViewmodel>().openProject(project);
  await GetIt.I.get<SrxNavigationService>().pop();
}
