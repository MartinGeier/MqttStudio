import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

class SrxLocalDatabaseController {
  String _dbFilename = 'local.db';
  Database? _database;

  Database get database {
    if (_database != null) {
      return _database!;
    } else {
      throw new Exception('Database has not been opened!');
    }
  }

  Future openDatabase() async {
    var dir = await getApplicationDocumentsDirectory();
    await dir.create(recursive: true);
    var dbPath = join(dir.path, _dbFilename);
    _database = await databaseFactoryIo.openDatabase(dbPath);
  }
}
