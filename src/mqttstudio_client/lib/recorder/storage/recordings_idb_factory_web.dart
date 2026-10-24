import 'package:idb_shim/idb_browser.dart';

// IndexedDB of the browser, memory when the browser blocks it
IdbFactory get recordingsIdbFactory => idbFactoryBrowser;
