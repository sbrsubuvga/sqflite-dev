import 'package:sqflite_common/sqlite_api.dart';
import 'database_wrapper.dart';

/// Helper class for opening databases with automatic workbench support
/// Similar to sqflite_orm's DatabaseManager.initialize() with webDebug option
class WorkbenchHelper {
  /// Enable workbench on an already opened database
  ///
  /// This is a convenience method that enables the workbench after opening a database.
  /// Similar to sqflite_orm's approach where you can enable the web UI automatically.
  ///
  /// [database] - The opened database instance
  /// [webDebug] - Enable workbench (default: true)
  /// [webDebugPort] - Port for workbench server (default: 8080)
  /// [webDebugName] - Custom name for database in workbench UI
  ///
  /// Example:
  /// ```dart
  /// final db = await openDatabase('app.db', version: 1);
  /// WorkbenchHelper.enableWorkbench(
  ///   db,
  ///   webDebug: true,
  ///   webDebugPort: 8080,
  ///   webDebugName: 'MyAppDB',
  /// );
  /// ```
  static void enableWorkbench(
    Database database, {
    bool webDebug = true,
    int webDebugPort = 8080,
    String? webDebugName,
  }) {
    if (webDebug) {
      database.enableWorkbench(
        webDebug: webDebug,
        webDebugName: webDebugName,
        webDebugPort: webDebugPort,
      );
    }
  }

  /// Open a database and automatically enable workbench
  ///
  /// This wraps the standard openDatabase call and automatically enables
  /// the workbench, similar to sqflite_orm's DatabaseManager.initialize().
  ///
  /// You still need to call openDatabase yourself, but this provides
  /// a convenient way to enable workbench in one step.
  ///
  /// Example:
  /// ```dart
  /// // Using with sqflite (mobile)
  /// import 'package:sqflite/sqflite.dart';
  /// final db = await openDatabase('app.db', version: 1);
  /// WorkbenchHelper.autoEnable(db, webDebugPort: 8080);
  ///
  /// // Using with sqflite_common_ffi (desktop)
  /// import 'package:sqflite_common_ffi/sqflite_ffi.dart';
  /// sqfliteFfiInit();
  /// databaseFactory = databaseFactoryFfi;
  /// final db = await openDatabase('app.db', version: 1);
  /// WorkbenchHelper.autoEnable(db, webDebugPort: 8080);
  /// ```
  static void autoEnable(
    Database database, {
    bool webDebug = true,
    int webDebugPort = 8080,
    String? webDebugName,
  }) {
    enableWorkbench(
      database,
      webDebug: webDebug,
      webDebugPort: webDebugPort,
      webDebugName: webDebugName,
    );
  }
}
