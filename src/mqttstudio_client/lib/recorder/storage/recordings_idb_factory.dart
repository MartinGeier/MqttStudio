import 'package:idb_shim/idb_client_memory.dart';

// Not in a browser there is no IndexedDB; the desktop keeps recordings in a folder
IdbFactory get recordingsIdbFactory => idbFactoryMemory;
