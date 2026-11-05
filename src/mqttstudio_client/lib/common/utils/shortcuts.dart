import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// ⌘ on Apple platforms, Ctrl elsewhere. In the browser this follows the user's OS.
bool get usesCommandKey => defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;

// A shortcut with the platform's command modifier, e.g. ⌘S on macOS and Ctrl+S on Windows
SingleActivator commandShortcut(LogicalKeyboardKey key, {bool shift = false}) =>
    SingleActivator(key, meta: usesCommandKey, control: !usesCommandKey, shift: shift);
