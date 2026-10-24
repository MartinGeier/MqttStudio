// The browser asks before the page is closed or reloaded while guard() returns true. Nothing to do on desktop, where
// the app asks itself (AppLifecycleListener).
void installLeavePageGuard(bool Function() guard) {}
