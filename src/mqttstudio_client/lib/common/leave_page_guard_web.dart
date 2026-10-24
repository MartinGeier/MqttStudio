import 'dart:js_interop';
import 'package:web/web.dart' as web;

// The browser asks before the page is closed or reloaded while guard() returns true. It shows its own text.
void installLeavePageGuard(bool Function() guard) {
  web.window.addEventListener(
      'beforeunload',
      ((web.Event event) {
        if (guard()) {
          event.preventDefault();
        }
      }).toJS);
}
