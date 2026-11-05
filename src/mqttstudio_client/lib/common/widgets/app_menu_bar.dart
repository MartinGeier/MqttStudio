import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqttstudio/common/about_mqttstudio.dart';
import 'package:mqttstudio/common/utils/shortcuts.dart';
import 'package:mqttstudio/common/widgets/main_appbar.dart';
import 'package:mqttstudio/project/project_commands.dart';

// The menu bar of macOS. Windows and Linux have no menu bar, they get the same commands as Ctrl shortcuts. The web app
// has neither, the browser keeps Ctrl+N, Ctrl+W and the like for itself.
class AppMenuBar extends StatelessWidget {
  final TabController tabController;
  final bool isProjectOpen;
  final Widget child;

  const AppMenuBar({required this.tabController, required this.isProjectOpen, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return child;
    }
    // the menu stays usable while a dialog is open, but its commands are for the main window
    var route = ModalRoute.of(context);
    VoidCallback? whenInFront(Future Function() command) => () async {
          if (route?.isCurrent ?? true) {
            await command();
          }
        };

    // the groups of the file menu
    var projectCommands = [
      [
        _Command('appmenu.newproject'.tr(), commandShortcut(LogicalKeyboardKey.keyN), whenInFront(newProject)),
        _Command('appmenu.openproject'.tr(), commandShortcut(LogicalKeyboardKey.keyO), whenInFront(openProject)),
      ],
      [
        _Command('appmenu.saveproject'.tr(), commandShortcut(LogicalKeyboardKey.keyS),
            isProjectOpen ? whenInFront(saveProject) : null),
        _Command('appmenu.closeproject'.tr(), commandShortcut(LogicalKeyboardKey.keyW),
            isProjectOpen ? whenInFront(closeProject) : null),
      ],
      [_Command('appmenu.projectsettings'.tr(), null, isProjectOpen ? whenInFront(editProjectSettings) : null)],
    ];
    var tabCommands = [
      _tabCommand('appmenu.topicviewer'.tr(), LogicalKeyboardKey.digit1, MainAppBar.topicViewerTab, whenInFront),
      _tabCommand('appmenu.simulator'.tr(), LogicalKeyboardKey.digit2, MainAppBar.simulatorTab, whenInFront),
      _tabCommand('appmenu.recorder'.tr(), LogicalKeyboardKey.digit3, MainAppBar.recorderTab, whenInFront),
      _tabCommand('appmenu.documentation'.tr(), LogicalKeyboardKey.digit4, MainAppBar.documentationTab, whenInFront),
    ];

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return PlatformMenuBar(menus: _buildMenus(projectCommands, tabCommands), child: child);
    }
    return CallbackShortcuts(
      bindings: {
        for (var command in [...projectCommands.expand((group) => group), ...tabCommands])
          if (command.shortcut != null && command.onSelected != null) command.shortcut!: command.onSelected!,
      },
      // the shortcuts need the focus inside the window, also before anything was clicked
      child: Focus(autofocus: true, child: child),
    );
  }

  _Command _tabCommand(String label, LogicalKeyboardKey key, int tab,
          VoidCallback? Function(Future Function() command) whenInFront) =>
      _Command(label, commandShortcut(key), whenInFront(() async => tabController.animateTo(tab)));

  List<PlatformMenuItem> _buildMenus(List<List<_Command>> projectCommands, List<_Command> tabCommands) {
    return [
      _buildAppMenu(),
      PlatformMenu(label: 'appmenu.file'.tr(), menus: [
        for (var group in projectCommands) PlatformMenuItemGroup(members: group.map((c) => c.toMenuItem()).toList()),
      ]),
      _buildEditMenu(),
      PlatformMenu(label: 'appmenu.view'.tr(), menus: [
        PlatformMenuItemGroup(members: tabCommands.map((c) => c.toMenuItem()).toList()),
        PlatformMenuItemGroup(members: [PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.toggleFullScreen)]),
      ]),
      PlatformMenu(label: 'appmenu.window'.tr(), menus: [
        PlatformMenuItemGroup(members: [
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.minimizeWindow),
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
        ]),
        PlatformMenuItemGroup(
            members: [PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.arrangeWindowsInFront)]),
      ]),
      PlatformMenu(label: 'appmenu.help'.tr(), menus: [
        PlatformMenuItem(label: 'appmenu.website'.tr(), onSelected: openWebsite),
        PlatformMenuItem(label: 'appmenu.email'.tr(), onSelected: writeEmail),
      ]),
    ];
  }

  // macOS titles the first menu with the app name
  PlatformMenu _buildAppMenu() {
    return PlatformMenu(label: 'MQTT Studio', menus: [
      PlatformMenuItemGroup(members: [
        PlatformMenuItem(label: 'navigator.about_menuitem'.tr(), onSelected: showAboutMqttStudio),
      ]),
      PlatformMenuItemGroup(members: [PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.servicesSubmenu)]),
      PlatformMenuItemGroup(members: [
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hideOtherApplications),
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.showAllApplications),
      ]),
      PlatformMenuItemGroup(members: [PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit)]),
    ]);
  }

  // The menu takes ⌘C and the like before the text fields see them, so its items send the text fields' own intents
  // to the focused widget.
  PlatformMenu _buildEditMenu() {
    return PlatformMenu(label: 'appmenu.edit'.tr(), menus: [
      PlatformMenuItemGroup(members: [
        _editItem('appmenu.undo'.tr(), LogicalKeyboardKey.keyZ, UndoTextIntent(SelectionChangedCause.keyboard)),
        _editItem('appmenu.redo'.tr(), LogicalKeyboardKey.keyZ, RedoTextIntent(SelectionChangedCause.keyboard),
            shift: true),
      ]),
      PlatformMenuItemGroup(members: [
        _editItem('appmenu.cut'.tr(), LogicalKeyboardKey.keyX, CopySelectionTextIntent.cut(SelectionChangedCause.keyboard)),
        _editItem('appmenu.copy'.tr(), LogicalKeyboardKey.keyC, CopySelectionTextIntent.copy),
        _editItem('appmenu.paste'.tr(), LogicalKeyboardKey.keyV, PasteTextIntent(SelectionChangedCause.keyboard)),
        _editItem('appmenu.selectall'.tr(), LogicalKeyboardKey.keyA, SelectAllTextIntent(SelectionChangedCause.keyboard)),
      ]),
    ]);
  }

  PlatformMenuItem _editItem(String label, LogicalKeyboardKey key, Intent intent, {bool shift = false}) {
    return PlatformMenuItem(
        label: label,
        shortcut: commandShortcut(key, shift: shift),
        onSelected: () {
          var focused = FocusManager.instance.primaryFocus?.context;
          if (focused != null) {
            Actions.maybeInvoke(focused, intent);
          }
        });
  }
}

class _Command {
  final String label;
  final SingleActivator? shortcut;
  // null disables the command
  final VoidCallback? onSelected;

  _Command(this.label, this.shortcut, this.onSelected);

  PlatformMenuItem toMenuItem() => PlatformMenuItem(label: label, shortcut: shortcut, onSelected: onSelected);
}
